#!/usr/bin/env python3
"""Breaks each rule of the clear-artwork feature once, in a copy of its production file, and requires clear-check
to fail. The production files are never edited: the broken copy replaces one of them through build.sh's STORE,
CATALOG or SETTINGS. Each mutant's old text must occur exactly once, so a refactor that moves it fails loudly here."""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, "../../tweak/Sources/Shared/AnimatedArtwork")
FILES = {
    "STORE": "SGMotionStore.m",
    "CATALOG": "SGMotionCatalog.m",
    "SETTINGS": "AnimatedArtworkSettings.m",
}

ARTIST_STOP = "if (generation != sg_generation) { done(nil, nil, SGMotionArtistArtworkMetadataFailed); return; }\n"

# (rule, variable, old text, new text)
MUTANTS = [
    ("only the store's own clips are removed and counted", "STORE",
     "static BOOL ownedClip(NSURL *file) {\n", "static BOOL ownedClip(NSURL *file) {\n    return YES;\n"),
    ("a clip a consumer holds stays", "STORE",
     "// A clip a consumer holds stays; it goes with the next trim once released.\n"
     "            if ([sg_inUse containsObject:file.URLByResolvingSymlinksInPath.path]) continue;\n", ""),
    ("the size counts the clips", "STORE",
     "            total += size.unsignedLongLongValue;\n        }\n        dispatch_async(dispatch_get_main_queue(), ^{ done(total); });",
     "            total += 0;\n        }\n        dispatch_async(dispatch_get_main_queue(), ^{ done(total); });"),
    ("a clip that cannot be removed is reported", "STORE",
     "                complete = NO;\n            }\n        }\n        if (listing) {", "            }\n        }\n        if (listing) {"),
    ("a download from before the clear does not land after it", "STORE",
     "        owner.cancelled = YES;\n        [owner.task cancel];\n", "        [owner.task cancel];\n"),
    ("a file queued before the clear is not made after it", "STORE",
     "        if (generation != atomic_load(&sg_clearGeneration)) { done(NO); return; }\n", ""),
    ("the answers file is removed", "CATALOG",
     "BOOL gone = [NSFileManager.defaultManager removeItemAtURL:answers error:&error] ||", "BOOL gone = YES ||"),
    ("an answers file that cannot be removed is reported", "CATALOG",
     "if (!gone) complete = NO; dispatch_group_leave(group);", "dispatch_group_leave(group);"),
    ("the size counts the answers file", "CATALOG",
     "total += size.unsignedLongLongValue; dispatch_group_leave(group);", "total += 0; dispatch_group_leave(group);"),
    ("answers and artist images in memory are forgotten", "CATALOG", "    [sg_kept removeAllObjects];\n", ""),
    ("a clear before the first lookup does not read the answers file on main", "CATALOG",
     "sg_answersCleared ? nil : [NSDictionary", "[NSDictionary"),
    ("a lookup from before the clear keeps nothing", "CATALOG",
     "if (generation == sg_generation) {\n            if (keep)", "if (YES) {\n            if (keep)"),
    ("a request after the clear does not join an old lookup", "CATALOG", "    [sg_waiting removeAllObjects];\n    dispatch_group_t group", "    dispatch_group_t group"),
    ("a lookup from before the clear starts no download after it", "CATALOG",
     "        if (generation != sg_generation) { done(nil); return; }   // asked before a clear: no download after it\n", ""),
    ("an artist request is judged by the generation it began in, not the one its search answers in", "CATALOG",
     "    NSUInteger generation = sg_generation;\n    artistRecords(artist, ^(NSArray *records) {\n        " + ARTIST_STOP,
     "    artistRecords(artist, ^(NSArray *records) {\n        NSUInteger generation = sg_generation;\n"),
    ("an artist request stops after its search when a clear came", "CATALOG",
     "        " + ARTIST_STOP + "        NSString *identity", "        NSString *identity"),
    ("an artist request stops after its discography when a clear came", "CATALOG",
     "            " + ARTIST_STOP + "            NSDictionary *match", "            NSDictionary *match"),
    ("an artist request stops after its video resource when a clear came", "CATALOG",
     "            " + ARTIST_STOP + "            dispatch_group_t assets", "            dispatch_group_t assets"),
    ("an artist request starts no clip download after a clear", "CATALOG",
     "                    if (generation != sg_generation) { dispatch_group_leave(assets); return; }   // asked before a clear\n", ""),
    ("Cancel changes nothing", "SETTINGS",
     "style:UIAlertActionStyleCancel handler:nil]];\n    [alert addAction:[UIAlertAction actionWithTitle:SGL(@\"settings.artwork_clear.alert.action\"",
     "style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { clearCache(); }]];\n    [alert addAction:[UIAlertAction actionWithTitle:SGL(@\"settings.artwork_clear.alert.action\""),
    ("a failed clear is said to the user", "SETTINGS", "        if (!complete)\n", "        if (NO)\n"),
]


def main():
    survivors = []
    with tempfile.TemporaryDirectory() as folder:
        for number, (rule, variable, old, new) in enumerate(MUTANTS):
            source = open(os.path.join(ART, FILES[variable])).read()
            if source.count(old) != 1:
                sys.exit(f"mutant '{rule}': its text occurs {source.count(old)} times in {FILES[variable]}")
            broken = os.path.join(folder, f"{number}-{FILES[variable]}")
            open(broken, "w").write(source.replace(old, new))
            out = os.path.join(folder, f"out{number}")
            result = subprocess.run(["sh", os.path.join(HERE, "build.sh")], capture_output=True, text=True,
                                    env={**os.environ, "OUT": out, variable: broken})
            built = os.path.exists(os.path.join(out, "artwork-clear-check"))
            if not built:
                sys.exit(f"mutant '{rule}' does not build:\n{result.stderr}")
            failed = result.returncode != 0 and "[harness] FAIL" in result.stderr
            print(("caught   " if failed else "SURVIVED ") + rule, flush=True)
            if not failed:
                survivors.append(rule)
    sys.exit(f"{len(survivors)} mutants survived" if survivors else 0)


main()
