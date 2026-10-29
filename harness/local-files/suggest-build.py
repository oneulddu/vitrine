#!/usr/bin/env python3
"""Foundation-only Mac contract checks and isolated source mutations; no network."""
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tweak/Sources/Shared/LocalFiles/LocalInfoLookup.m"
MUTATIONS = {
    "brackets": ('text = replace(text, @"\\\\([^()]*\\\\)|\\\\[[^\\\\[\\\\]]*\\\\]", @" ");', '(void)text;'),
    "track-number": ('text = replace(text, @"^\\\\s*\\\\d{1,3}(?:[\\\\s._-]+)", @"");', '(void)text;'),
    "noise-words": ('official|video|audio|lyrics|lyric|hd|hq|4k|visualizer|explicit|remastered|remaster', 'no_matching_noise'),
    "fallback-extension": ('filename.lastPathComponent.stringByDeletingPathExtension', 'filename.lastPathComponent'),
    "duration-boundary": ('distance > kDurationToleranceMilliseconds', 'distance >= kDurationToleranceMilliseconds'),
    "duration-outside": ('kDurationToleranceMilliseconds = 3000', 'kDurationToleranceMilliseconds = 3001'),
    "unknown-duration": ('if (seconds > 0 && distance', 'if (distance'),
    "title-priority": ('@[@"title", @"artist"]', '@[@"artist", @"title"]'),
    "artist-priority": ('similarity(current, a[field]), second = similarity(current, b[field])',
                        'similarity(current, a[field]), second = similarity(current, b[field]); if ([field isEqual:@"artist"]) first = second'),
    "duration-tie": ('first < second ? NSOrderedAscending', 'first > second ? NSOrderedAscending'),
    "diacritics": ('NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch', 'NSCaseInsensitiveSearch'),
    "json-size": ('data.length > SGLocalInfoJSONLimit', 'data.length > SGLocalInfoJSONLimit + 1'),
    "malformed-duration": ('CFGetTypeID((__bridge CFTypeRef)duration) == CFBooleanGetTypeID()', 'NO'),
    "artwork": ('withString:@"600x600bb"', 'withString:@"100x100bb"'),
    "country": ('value:region.lowercaseString', 'value:region.uppercaseString'),
    "cookie-policy": ('config.HTTPShouldSetCookies = NO', 'config.HTTPShouldSetCookies = YES'),
    "low-data-policy": ('config.allowsConstrainedNetworkAccess = NO', 'config.allowsConstrainedNetworkAccess = YES'),
    "timeout": ('kRequestTimeoutSeconds = 15', 'kRequestTimeoutSeconds = 16'),
    "cover-cap": ('4 * 1024 * 1024;', '4 * 1024 * 1024 + 1;'),
    "artwork-host": ('[host hasSuffix:@".mzstatic.com"]', '[host hasSuffix:@"mzstatic.com"]'),
    "initial-host": ('if (!allowedURL(url, search))', 'if (NO)'),
    "redirect-host": ('if (!allowedURL(request.URL, _searchRequest))', 'if (NO)'),
    "search-redirect-host": ('allowedURL(request.URL, _searchRequest)', 'allowedURL(request.URL, NO)'),
    "cache-hit": ('if (cached) { completion(cached, nil); return; }', '(void)cached;'),
    "cache-cap": ('kSearchCacheEntries = 32', 'kSearchCacheEntries = 33'),
    "cache-country": ('NSString *key = url.absoluteString;', 'NSString *key = [[url.absoluteString componentsSeparatedByString:@"&country="] firstObject];'),
    "cache-malformed": ('NSArray *songs = SGLocalInfoParse(data);', 'NSArray *songs = SGLocalInfoParse(data) ?: @[];'),
}

def run():
    original = SOURCE.read_text()
    with tempfile.TemporaryDirectory(prefix="vitrine-suggest-") as temp:
        out = pathlib.Path(temp)
        for name, replacement in [("baseline", None), *MUTATIONS.items()]:
            source = original
            if replacement:
                old, new = replacement
                if source.count(old) != 1:
                    raise SystemExit(f"{name}: mutation target not unique")
                source = source.replace(old, new)
            generated = out / "LocalInfoLookup.m"
            generated.write_text(source)
            subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-Wall", "-Werror",
                "-I" + str(ROOT / "tweak/Sources"), "-I" + str(SOURCE.parent),
                str(ROOT / "harness/local-files/suggest-check.m"), str(generated),
                "-framework", "Foundation", "-o", str(out / "check")], check=True)
            result = subprocess.run([str(out / "check")], capture_output=True, text=True, timeout=10)
            if name == "baseline":
                print(result.stdout, end="")
                if result.returncode:
                    raise SystemExit(result.stderr)
            elif result.returncode != 1 or "FAIL line" not in result.stderr:
                raise SystemExit(f"{name}: mutation survived or crashed: {result.stdout}{result.stderr}")
            else:
                print(f"PASS mutation {name}: rejected")

if __name__ == "__main__":
    run()
