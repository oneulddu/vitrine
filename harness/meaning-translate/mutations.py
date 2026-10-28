#!/usr/bin/env python3
"""Run contract mutations against disposable production-source copies, never the working tree."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

here = Path(__file__).resolve().parent
root = here.parent.parent
sheet = root / "tweak/Sources/Redesigned/Lyrics/MeaningSheet.m"
text = root / "tweak/Sources/Shared/LyricsTranslation/TextTranslation.m"
segments = text.with_name("ProseSegments.m")
openai = text.with_name("OpenAITranslate.m")
claude = text.with_name("ClaudeTranslate.m")
gemini = text.with_name("LyricsTranslation.m")

# Each mutation removes one user-visible guarantee. A compile failure is not a killed mutation.
mutations = [
    ("annotation switch", sheet, " && [[self keyOnScreen] isEqual:key]", ""),
    ("dismissal", sheet, "self.viewIfLoaded.window != nil && !self.isBeingDismissed && ", ""),
    ("dismissal ownership", sheet, "[self show];\n    __weak SGRMeaningSheet *weakSelf = self;",
     "[self show];\n    SGRMeaningSheet *weakSelf = self;"),
    ("duplicate taps", sheet, "if ([_inFlight containsObject:key]) return;", ""),
    ("retry", sheet, "[self->_inFlight removeObject:key];", ""),
    ("failure message", sheet, 'self->_failedKey = key;', 'self->_failedKey = nil;'),
    ("target language", sheet, '_lineText ?: @"", SGLyricsGeminiLanguage()];',
     '_lineText ?: @"", @"fixed-language"];'),
    ("show original", sheet, "_original = !_original;", "_original = NO;"),
    ("attribution", sheet, "badge.title = authorName(meaning.author);",
     'badge.title = translated ? @"Translator" : authorName(meaning.author);'),
    ("Genius URL", sheet, "[NSURL URLWithString:_meanings[_index].url]",
     '[NSURL URLWithString:@"https://genius.com/annotations/wrong"]'),
    ("no service", sheet, "_translate.hidden = !SGLyricsTranslateTextsAvailable();",
     "_translate.hidden = NO;"),
    ("tap only", sheet, "- (void)show {\n", "- (void)show {\n"
     "    if (!_inFlight.count && !_translations.count) [self toggleTranslation];\n"),
    ("bounded cache", sheet, "[_translations removeObjectForKey:oldest];", "(void)oldest;"),
    ("content key", sheet, 'meaning.body ?: @"",\n', '@"fixed-body",\n'),
    ("quoted lyric sent", sheet, 'SGLyricsTranslateTexts(@[body, _lineText ?: @""],',
     'SGLyricsTranslateTexts(@[body, @""],'),
    ("no lyric storage", text, "        proseAsk(translator, texts, languageTag, language,",
     '        SGLyricsSaveTranslation(@"meaning", languageTag, @[]);\n'
     "        proseAsk(translator, texts, languageTag, language,"),
    ("configured provider", text,
     "case SGProseTranslatorGoogle: SGGoogleTranslateTexts(texts, languageTag, done); return;",
     "case SGProseTranslatorGoogle: SGBingTranslateTexts(texts, languageTag, done); return;"),
    ("complete reply", text,
     'done(valid && !error ? answer : nil, error ?: (valid ? nil :\n'
     '                SGL(@"settings.translation.text.error.unreadable", @"The translation\'s answer could not be read. Try again.")));',
     "(void)valid; done(answer, error);"),
    ("on-device preparation", text, "from:view done:done", "from:nil done:done"),
    ("AI input budget", segments,
     "if (unit == SGProseSegmentJSONBytes && !segmentFits(piece, limit, unit)) return NO;",
     "if (unit == SGProseSegmentJSONBytes && !segmentFits(piece, limit, unit) && NO) return NO;"),
    ("AI segmentation", text,
     "    SGLyricsTranslateSegments(texts, maxInputBytes, SGProseSegmentJSONBytes,",
     "    if ([NSJSONSerialization dataWithJSONObject:texts options:0 error:nil].length > maxInputBytes) { done(nil, SGLyricsProseTooLong()); return; }\n"
     "    SGLyricsTranslateSegments(texts, maxInputBytes, SGProseSegmentJSONBytes,"),
    ("AI segment failure", text, "if (error || !SGLyricsProseReplyValid(answer, input))", "if (error)"),
    ("AI overall cap", text, "if (segments.count > kMaxAIProseSegments)", "if (segments.count > kMaxAIProseSegments && NO)"),
    ("OpenAI completion metadata", openai, "if (format != SGLyricsReplyJSON)", "if (format == SGLyricsReplyIndexed)"),
    ("Claude completion metadata", claude,
     'if (valid && [reply[@"stop_reason"] isEqual:@"end_turn"]) out = SGLyricsAIArrayIn(text, count);',
     'if (valid) out = SGLyricsAIArrayIn(text, count);'),
    ("Gemini completion metadata", gemini,
     '(format == SGLyricsReplyProse ? [finished isEqual:@"STOP"] : (!finished || [finished isEqual:@"STOP"]))',
     '(!finished || [finished isEqual:@"STOP"])'),
    ("paragraph preservation", segments,
     '[plan addObject:[text substringWithRange:NSMakeRange(contentsEnd, end - contentsEnd)]];',
     '[plan addObject:@""];'),
    ("all segments required", segments,
     'if (error || !SGLyricsProseReplyValid(answer, segments))',
     'if (error)'),
    ("Dynamic Type", sheet,
     '[[UIFontMetrics metricsForTextStyle:UIFontTextStyleSubheadline]\n'
     '            scaledFontForFont:[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]\n'
     '            compatibleWithTraitCollection:weakSelf.traitCollection]',
     '(weakSelf ? [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold] : nil)'),
]

if sys.argv[1:]:
    selected = set(sys.argv[1:])
    if selected - {name for name, *_ in mutations}:
        raise SystemExit("Unknown mutation name")
    mutations = [mutation for mutation in mutations if mutation[0] in selected]

for name, source, before, after in mutations:
    original = source.read_text()
    if original.count(before) != 1:
        raise SystemExit(f"{name}: mutation anchor is not unique")
    with tempfile.TemporaryDirectory(prefix="meaning-mutation.") as directory:
        directory = Path(directory)
        changed = directory / source.name
        changed.write_text(original.replace(before, after))
        provider_mutations = {"AI input budget", "AI segmentation", "AI segment failure", "AI overall cap",
                              "OpenAI completion metadata", "Claude completion metadata",
                              "Gemini completion metadata", "paragraph preservation", "all segments required",
                              "on-device preparation"}
        env = dict(os.environ, OUT=str(directory / "build"), MEANING_UI_ONLY="1")
        env[{sheet: "SHEET_SOURCE", text: "TEXT_SOURCE", segments: "SEGMENTS_SOURCE",
             openai: "OPENAI_SOURCE", claude: "CLAUDE_SOURCE", gemini: "GEMINI_SOURCE"}[source]] = str(changed)
        script = "providers-build.sh" if name in provider_mutations else "build.sh"
        command = [sys.executable, "-B", str(here / "dynamic-type-check.py")] if name == "Dynamic Type" else ["sh", str(here / script)]
        result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=240)
        output = result.stdout + result.stderr
        if result.returncode != 1 or "[harness] FAIL " not in output:
            print(output)
            raise SystemExit(f"{name}: expected a contract failure, exit={result.returncode}")
        failure = next(line for line in output.splitlines() if "[harness] FAIL " in line)
        print(f"{name}: killed — {failure}", flush=True)
print(f"meaning-translate: {len(mutations)} mutations killed")
