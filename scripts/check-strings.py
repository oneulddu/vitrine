#!/usr/bin/env python3
"""Keeps the mod's translations in step with its sources (docs/tweaks.md, Localization).

  scripts/check-strings.py          check, exit 1 on a problem
  scripts/check-strings.py --sync   also rewrite en.lproj from the SGL(...) calls in tweak/Sources

Checks: every SGL(@"key", @"English") key is well formed and stands for one English text; en.lproj holds exactly
those keys and texts; every other .lproj has the same keys, and each translation reads the same format specifiers
(kind and number, in argument order; %2$@ may reorder them); the bundle's Info.plist and tables lint; and the
settings files pass no new untranslated text to a row, section, alert or label (scripts/strings-allow.txt lists the
deliberate exceptions, such as brand names)."""
import os, re, subprocess, sys, shutil

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
SOURCES = os.path.join(ROOT, 'tweak', 'Sources')
BUNDLE = os.path.join(ROOT, 'tweak', 'layout', 'Library', 'Application Support', 'Vitrine.bundle')
ALLOW = os.path.join(ROOT, 'scripts', 'strings-allow.txt')
KEY = re.compile(r'^[a-z0-9]+(\.[a-z0-9_]+)+$')
problems = []

def problem(msg):
    problems.append(msg)

# --- Objective-C literals --------------------------------------------------------------------------------------
def literals(text):
    """@"..." literals, adjacent ones joined, comments and char literals skipped: (start, end, raw content)."""
    i, n, units, cur = 0, len(text), [], None
    while i < n:
        c = text[i]
        if text.startswith('//', i):
            j = text.find('\n', i); i = n if j < 0 else j; continue
        if text.startswith('/*', i):
            j = text.find('*/', i + 2); i = n if j < 0 else j + 2; continue
        if c == "'":
            j = i + 1
            while j < n and text[j] not in "'\n":
                j += 2 if text[j] == '\\' else 1
            i = j + 1
            if cur: units.append(cur); cur = None
            continue
        if c == '"' or (c == '@' and text.startswith('@"', i)):
            s, j = i, i + (2 if c == '@' else 1)
            while j < n and text[j] not in '"\n':
                j += 2 if text[j] == '\\' else 1
            content = text[s + (2 if c == '@' else 1):j]
            if cur and not text[cur[1]:s].strip():
                cur = (cur[0], j + 1, cur[2] + content, cur[3])
            else:
                if cur: units.append(cur)
                cur = (s, j + 1, content, c == '@')
            i = j + 1; continue
        if not c.isspace() and cur:
            units.append(cur); cur = None
        i += 1
    if cur: units.append(cur)
    return [(s, e, t) for s, e, t, objc in units if objc]

def unescape(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s):
            d = s[i + 1]
            if d in 'uU' and re.match(r'[0-9a-fA-F]{4}', s[i + 2:i + 6]):
                out.append(chr(int(s[i + 2:i + 6], 16))); i += 6; continue
            out.append({'n': '\n', 't': '\t', 'r': '\r', '"': '"', '\\': '\\', "'": "'", '0': '\0'}.get(d, d)); i += 2; continue
        out.append(c); i += 1
    return ''.join(out)

def escape(s):
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\t', '\\t')

# --- format specifiers, read the way Core/SGLocalize.m reads them -------------------------------------------------
SPEC = re.compile(r'%(?:(\d+)\$)?[0-9.\-+#*]*([hlqLzjt]*[@dDiuUxXoOfFeEgGaAcCsSp])')
def specifiers(s):
    """{position: type}, '*' for a width or precision read from the arguments; None when one position is read as
    two types (Core/SGLocalize.m then never uses the translation)."""
    found, nxt = {}, 1
    s = s.replace('%%', '')
    def read(pos, kind):
        if found.get(pos, kind) != kind: return False
        found[pos] = kind
        return True
    for m in SPEC.finditer(s):
        stars = m.group(0).count('*')
        if m.group(1) and stars: return None
        for _ in range(stars):
            if not read(nxt, '*'): return None
            nxt += 1
        pos = int(m.group(1)) if m.group(1) else nxt
        if not read(pos, m.group(2)): return None
        nxt = pos + 1
    return found

# --- .strings ----------------------------------------------------------------------------------------------------
STR_ENTRY = re.compile(r'\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;')
def read_strings(path):
    text = open(path, encoding='utf-8').read()
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'(?m)^\s*//.*$', '', text)
    table, pos = {}, 0
    for m in STR_ENTRY.finditer(text):
        if text[pos:m.start()].strip():
            problem(f'{os.path.relpath(path, ROOT)}: cannot read near {text[pos:m.start()].strip()[:40]!r}')
        key, value = unescape(m.group(1)), unescape(m.group(2))
        if key in table: problem(f'{os.path.relpath(path, ROOT)}: {key} appears twice')
        table[key] = value
        pos = m.end()
    if text[pos:].strip(): problem(f'{os.path.relpath(path, ROOT)}: cannot read near {text[pos:].strip()[:40]!r}')
    return table

def write_strings(path, table, header):
    lines = [header, '']
    group = None
    for key in sorted(table):
        g = '.'.join(key.split('.')[:2])
        if group is not None and g != group: lines.append('')
        group = g
        lines.append(f'"{key}" = "{escape(table[key])}";')
    open(path, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')

# --- sources -----------------------------------------------------------------------------------------------------
SGL_HEAD = re.compile(r'SGL\(\s*@"([^"\\]*)"\s*,\s*$')
ROW_CALL = re.compile(r'\bSG(?:Switch|Hide|Shown|Option|Unstable|Flag|Kill|Stat|Action|Warning|Page|Choice|Slider|Menu|Link|StatAction)Row\(|\bSG(?:Noted)?Section\(|SGModPage alloc')
UI_BEFORE = re.compile(
    r'(?:\bSG\w*Row\(|\bSG(?:Noted)?Section\(|\b(?:choice|menu|page|switch|option|hide|flag|kill|stat|action)Row\(|'
    r'initWithTitle:|\bintro:|\bfooter:|alertControllerWithTitle:|\bmessage:|actionWithTitle:|menuWithTitle:|setTitle:|'
    r'SGPickColor\(|\.(?:title|subtitle|text|placeholder|info|warning|choiceFooter|accessibilityLabel|accessibilityHint|'
    r'accessibilityValue|prompt)\s*=)\s*$')
LIST_BEFORE = re.compile(r'(?:@\[|,)\s*$')
LIST_LINE = re.compile(r'Row\(|choiceNotes|\.menu\s*=|SGNotedSection')

def source_files():
    for base, _, names in os.walk(SOURCES):
        for name in names:
            if name.endswith(('.m', '.x', '.xm', '.mm')):
                yield os.path.join(base, name)

def scan_sources():
    used, ui = {}, []
    for path in sorted(source_files()):
        text = open(path, encoding='utf-8').read()
        rel = os.path.relpath(path, SOURCES)
        settings = 'SGL(' in text or ROW_CALL.search(text)
        for s, e, raw in literals(text):
            before = text[max(0, s - 200):s]
            head = SGL_HEAD.search(before)
            if head:
                key, english = head.group(1), unescape(raw)
                if not KEY.match(key): problem(f'{rel}: badly formed key {key!r}')
                prev = used.get(key)
                if prev and prev[0] != english:
                    problem(f'{rel}: {key} stands for two texts: {prev[0]!r} ({prev[1]}) and {english!r}')
                used.setdefault(key, (english, rel))
                continue
            if re.search(r'SGL\(\s*$', before): continue   # the key itself
            if not settings: continue
            line_start = text.rfind('\n', 0, s) + 1
            line = text[line_start:text.find('\n', s) if text.find('\n', s) >= 0 else len(text)]
            if re.search(r'SGLog\(|NSLog\(', line): continue
            if UI_BEFORE.search(before) or (LIST_BEFORE.search(before) and LIST_LINE.search(line)) or \
               (re.search(r'\)\s*,\s*$', before) and 'Row(' in line):
                text_ = unescape(raw)
                # Words, not identifiers: a space, or a capital first. Flag keys and symbol names have neither.
                if len(re.findall(r'[A-Za-z]', text_)) >= 2 and (' ' in text_.strip() or text_[:1].isupper()):
                    ui.append((rel, text.count('\n', 0, s) + 1, text_))
    return used, ui

def main():
    sync = '--sync' in sys.argv
    used, ui = scan_sources()
    en_path = os.path.join(BUNDLE, 'en.lproj', 'Localizable.strings')
    english = {k: v[0] for k, v in used.items()}
    if sync:
        write_strings(en_path, english, '/* Vitrine\'s English, written by scripts/check-strings.py --sync from the SGL(...) calls in tweak/Sources. */')
    en = read_strings(en_path) if os.path.exists(en_path) else {}
    for k in sorted(set(english) - set(en)): problem(f'en.lproj lacks {k} (run scripts/check-strings.py --sync)')
    for k in sorted(set(en) - set(english)): problem(f'en.lproj has {k}, which no SGL(...) uses (run --sync)')
    for k in sorted(set(en) & set(english)):
        if en[k] != english[k]: problem(f'en.lproj {k} reads {en[k]!r}, the source {english[k]!r} (run --sync)')
    langs = sorted(d for d in os.listdir(BUNDLE) if d.endswith('.lproj') and d != 'en.lproj')
    for lang in langs:
        path = os.path.join(BUNDLE, lang, 'Localizable.strings')
        table = read_strings(path)
        for k in sorted(set(english) - set(table)): problem(f'{lang} lacks {k}: {english[k]!r}')
        for k in sorted(set(table) - set(english)): problem(f'{lang} has {k}, which no SGL(...) uses')
        for k in sorted(set(table) & set(english)):
            read, wanted = specifiers(table[k]), specifiers(english[k])
            if read is None or wanted is None or read != wanted:
                problem(f'{lang} {k}: specifiers {read} differ from the English {wanted}')
            if not table[k].strip(): problem(f'{lang} {k} is empty')
    allowed = set()
    if os.path.exists(ALLOW):
        for line in open(ALLOW, encoding='utf-8'):
            line = line.rstrip('\n')
            if line and not line.startswith('#'):
                allowed.add(tuple(line.split('\t', 1)) if '\t' in line else ('*', line))
    for rel, line, text in ui:
        if ('*', text) in allowed or (rel, text) in allowed: continue
        problem(f'{rel}:{line}: untranslated text {text!r}: wrap it in SGL(@"key", ...) or list it in scripts/strings-allow.txt')
    if shutil.which('plutil'):
        targets = [os.path.join(BUNDLE, 'Info.plist')] + [os.path.join(BUNDLE, d, 'Localizable.strings') for d in ['en.lproj'] + langs]
        for t in targets:
            r = subprocess.run(['plutil', '-lint', t], capture_output=True, text=True)
            if r.returncode: problem(f'plutil: {r.stdout.strip() or r.stderr.strip()}')
    else:
        print('check-strings: plutil not found, the plist lint is skipped')
    for p in problems: print('check-strings:', p, file=sys.stderr)
    print(f'check-strings: {len(english)} keys, {len(langs)} translation(s), {len(problems)} problem(s)')
    sys.exit(1 if problems else 0)

if __name__ == '__main__':
    main()

