// The song's language menu (SongLanguage.h).
#import "Core/SGCore.h"
#import "LyricsText.h"
#import "SongLanguage.h"

// The languages offered to pick a song's language from, besides the detected one.
static NSArray<NSString *> *pickable(void) {
    return @[@"ko", @"ja", @"en", @"zh", @"es", @"fr", @"de", @"pt", @"it", @"ru", @"th", @"vi", @"id", @"tl", @"hi", @"ar", @"tr"];
}

NSString *SGRLanguageName(NSString *tag) {
    if (!tag.length) return nil;
    NSLocale *here = [NSLocale localeWithLocaleIdentifier:NSLocale.preferredLanguages.firstObject ?: @"en"];
    return [here localizedStringForLanguageCode:tag] ?: [here localizedStringForLocaleIdentifier:tag] ?: tag;
}

// Applies the rule now, to the switches every lyrics view reads.
static void follow(NSString *language) {
    BOOL translation = NO, pronunciation = NO;
    if (!SGLyricsLanguageRule(language, &translation, &pronunciation)) return;
    if (SGFlag(SGRKeyLyricsTranslation, NO) != translation) SGRSetLyricsTextShown(SGRLyricsTextTranslation, translation);
    if (SGFlag(SGRKeyLyricsPronunciation, NO) != pronunciation) SGRSetLyricsTextShown(SGRLyricsTextPronunciation, pronunciation);
}

UIMenu *SGRSongLanguageMenu(NSString *trackID, NSString *detected, void (^apply)(void)) {
    NSString *set = SGLyricsTrackLanguage(trackID);
    NSString *language = set ?: detected;
    NSMutableArray<UIMenuElement *> *picks = [NSMutableArray array];
    UIAction *automatic = [UIAction actionWithTitle:SGL(@"settings.songlanguage.automatic", @"Automatic")
                                              image:nil identifier:nil handler:^(UIAction *action) {
        if (![trackID isEqualToString:SGKaraokePlayingTrack()]) return;
        SGLyricsSetTrackLanguage(trackID, nil);
        follow(detected);
        if (apply) apply();
    }];
    automatic.subtitle = detected ? SGRLanguageName(detected) : SGL(@"settings.songlanguage.unsure", @"Not sure");
    automatic.state = set ? UIMenuElementStateOff : UIMenuElementStateOn;
    [picks addObject:automatic];
    NSMutableArray<NSString *> *tags = [pickable() mutableCopy];
    if (detected && ![tags containsObject:detected]) [tags insertObject:detected atIndex:0];
    if (set && ![tags containsObject:set]) [tags insertObject:set atIndex:0];
    for (NSString *tag in tags) {
        UIAction *pick = [UIAction actionWithTitle:SGRLanguageName(tag) image:nil identifier:nil handler:^(UIAction *action) {
            if (![trackID isEqualToString:SGKaraokePlayingTrack()]) return;
            SGLyricsSetTrackLanguage(trackID, tag);
            follow(tag);
            if (apply) apply();
        }];
        pick.state = [set isEqualToString:tag] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [picks addObject:pick];
    }
    UIMenu *choose = [UIMenu menuWithTitle:SGL(@"settings.songlanguage.choose", @"Song Language") image:[UIImage systemImageNamed:@"globe"]
                                identifier:nil options:0 children:picks];
    choose.subtitle = language ? SGRLanguageName(language) : SGL(@"settings.songlanguage.unsure", @"Not sure");
    if (!language) return [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[choose]];

    // The rule: what the switches are now, kept for the language, so the next song in it opens the same way.
    BOOL translation = NO, pronunciation = NO;
    BOOL ruled = SGLyricsLanguageRule(language, &translation, &pronunciation);
    NSString *name = SGRLanguageName(language);
    UIAction *keep = [UIAction actionWithTitle:[NSString stringWithFormat:SGL(@"settings.songlanguage.keep.format", @"Keep for %@ Songs"), name]
                                         image:[UIImage systemImageNamed:@"pin"] identifier:nil handler:^(UIAction *action) {
        if (![trackID isEqualToString:SGKaraokePlayingTrack()]) return;
        SGLyricsSetLanguageRule(language, SGFlag(SGRKeyLyricsTranslation, NO), SGFlag(SGRKeyLyricsPronunciation, NO));
        if (apply) apply();
    }];
    keep.subtitle = SGL(@"settings.songlanguage.keep.subtitle", @"Translation and pronunciation as they are now");
    if (ruled) {
        NSMutableArray<NSString *> *shown = [NSMutableArray array];
        if (translation) [shown addObject:SGL(@"settings.songlanguage.rule.translation", @"translation")];
        if (pronunciation) [shown addObject:SGL(@"settings.songlanguage.rule.pronunciation", @"pronunciation")];
        keep.subtitle = shown.count ? [NSString stringWithFormat:SGL(@"settings.songlanguage.rule.shows.format", @"Kept: shows %@"), [shown componentsJoinedByString:@", "]]
                                    : SGL(@"settings.songlanguage.rule.none", @"Kept: shows neither");
        keep.state = UIMenuElementStateOn;
    }
    return [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[choose, keep]];
}
