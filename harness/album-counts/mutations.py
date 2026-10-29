"""Run the review regressions against isolated source mutants; never modify the working tree."""
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
counts = ["bash", str(root / "harness/album-counts/check.sh")]
menu = ["bash", str(root / "harness/ui-refinements/menu-check.sh")]
cases = [
    ("rollback", "Redesigned/Kit/SGRHeaderInfo.m",
     "[prefs setBool:YES forKey:SGRKeyFullCoverMigrated];",
     "[prefs removeObjectForKey:SGRKeyFullBleedCovers]; [prefs setBool:YES forKey:SGRKeyFullCoverMigrated];",
     counts, "rollback data retained"),
    ("varint-overflow", "Shared/AdBlock/Protobuf.m",
     "if (shift == 63 && (byte & 0xfe)) return NO;", "",
     counts, "tenth byte cannot wrap"),
    ("field-budget", "Shared/AdBlock/Protobuf.m",
     "if (fields.count == SGPBMaxFields) return nil;", "",
     counts, "over the field budget"),
    ("provider-failure", "Redesigned/Album/AlbumSpotifyCounts.m",
     "if (providerStatus && (providerStatus.wire != 0 || providerStatus.varint != 200)) return nil;",
     "if (providerStatus && (providerStatus.wire != 0 || providerStatus.varint != 200)) continue;",
     counts, "HTTP 200 with failed extension status"),
    ("entity-failure", "Redesigned/Album/AlbumSpotifyCounts.m",
     "if (!status || status.wire != 0 || status.varint != 200) return nil;",
     "if (!status || status.wire != 0 || status.varint != 200) continue;",
     counts, "HTTP 200 with failed extension status"),
    ("response-host", "Shared/SpotifyMetadata/SGSpotifyMetadata.m",
     "![url.host isEqual:kMetadataHost]", "NO",
     counts, "expected error 3"),
    ("endpoint-allowlist", "Shared/SpotifyMetadata/SGSpotifyMetadata.m",
     "} else return nil;", '} else { url.path = @"/other"; }',
     counts, "expected error 1"),
    ("redirect", "Shared/SpotifyMetadata/SGSpotifyMetadata.m",
     'completionHandler(nil);\n    [self finish:metadataError(2, @"Spotify metadata redirects are not allowed.")];',
     "completionHandler(request);",
     counts, "request must have the fixed Spotify origin"),
    ("stream-budget", "Shared/SpotifyMetadata/SGSpotifyMetadata.m",
     "if (data.length > SGSpotifyMetadataMaxResponseBytes - self.bytes.length)", "if (NO)",
     counts, "oversized stream must cancel"),
    ("entry-budget", "Redesigned/Album/AlbumSpotifyCounts.m",
     "++entries > 2 * kMaxTracksPerAlbum", "++entries > 3 * kMaxTracksPerAlbum",
     counts, "more than 1000 reply entries"),
    ("nesting-budget", "Redesigned/Album/AlbumSpotifyCounts.m",
     "if (count && count.wire != 0) return nil;", "",
     counts, "count nesting cannot exceed"),
    ("spotify-row", "Redesigned/Album/AlbumRows.x",
     "text = SGRAlbumSpotifyPlaysText(uri ? state.counts[uri] : nil);", "text = nil;",
     menu, "Spotify fixture completed before its deadline"),
    ("spotify-menu", "Redesigned/Album/AlbumPlaysMenu.x",
     "text = [page.albumURI isEqual:track[0]] ? SGRAlbumSpotifyPlaysText(page.counts[track[1]]) : nil;", "text = nil;",
     menu, "Spotify fixture completed before its deadline"),
]
with tempfile.TemporaryDirectory(prefix="vitrine-count-mutations.") as directory:
    source = pathlib.Path(directory) / "Sources"
    shutil.copytree(root / "tweak/Sources", source)
    env = dict(os.environ, SRC=str(source))
    for name, relative, before, after, command, failure in cases:
        if sys.argv[1:] and name not in sys.argv[1:]:
            continue
        path = source / relative
        original = path.read_text()
        if original.count(before) != 1:
            raise SystemExit(f"FAIL {name}: mutation target is not unique")
        path.write_text(original.replace(before, after, 1))
        try:
            result = subprocess.run(command, env=env, cwd=root, text=True, capture_output=True, timeout=120)
            output = result.stdout + result.stderr
            if result.returncode == 0 or failure not in output:
                raise SystemExit(f"FAIL {name}: expected regression did not fail\n{output}")
            print(f"PASS mutation {name}: rejected by its regression", flush=True)
        finally:
            path.write_text(original)
