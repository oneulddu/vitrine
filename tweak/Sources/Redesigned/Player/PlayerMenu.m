// Player redesign: the ⋯ opens the system menu (Redesigned/ContextMenu): Share, Add to playlist and Add to
// queue in a row at its top, then the player's own items here, then More with the rest of Spotify's rows. The
// player's items take over what Speed and pitch's block is on Spotify's sheet:
//
//     Speed, Pitch & Reverb   opens the sliders in a popover from the ⋯ (SGPlayerShowSpeedPitchPanel): speed,
//                             pitch, reverb and Pitch follows speed, as on Spotify's sheet (issue #14)
//     Search Lyrics           LRCLIB searched by hand for the song, its pick pinned to it (Redesigned/Lyrics/LyricsTools.h)
//     Show Fluid Artwork, Show Animated Artwork, Show Visualizer
//                             a button for each of the two the background is not, while it is one of the
//                             three, named for what it switches to
//     Lyrics Source           a song's lyrics from another source than the one the order chose (issue #67): its
//                             items are the sources with lines for the song so far, asked as the ⋯ opens
//
// The item says under its name what is not as Spotify plays it, so the menu reads as a settings summary.
#import "Core/SGCore.h"
#import "Redesigned/ContextMenu/ContextMenu.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SpeedPitch.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Player.h"
#import "Redesigned/Lyrics/LyricsTools.h"
#import "Redesigned/Lyrics/LyricsLook.h"
#import "Core/SGLocalize.h"
#import "Shared/LyricsPiP/LyricsPiP.h"
#import "PlayerQueue.h"

static __weak UIView *sg_moreButton;   // the ⋯ the sliders' panel comes from

static UIImage *symbol(NSString *name) {
    return [UIImage systemImageNamed:name];
}

static NSString *speedText(double speed) {
    NSString *text = [NSString stringWithFormat:@"%.2f", speed];
    while ([text hasSuffix:@"0"]) text = [text substringToIndex:text.length - 1];
    if ([text hasSuffix:@"."]) text = [text substringToIndex:text.length - 1];
    return [text stringByAppendingString:@"×"];
}

static NSString *semitonesText(float semitones) {
    if (semitones == 0) return @"Original";
    return [NSString stringWithFormat:@"%@%.0f %@", semitones > 0 ? @"+" : @"−", fabsf(semitones), fabsf(semitones) == 1 ? @"Semitone" : @"Semitones"];
}

// While pitch follows a speed that is not normal, the speed sets the pitch and the semitones are not played
// (SGTimePitch.h), so they stand aside, as on the sheet.
static BOOL pitchFollowing(void) {
    return SGPlayerSpeedAllowed() && SGPlayerPitchFollowsSpeed() && SGPlayerSpeed() != 1;
}

// One item for the three, which says what is not as Spotify plays it, or Normal.
static UIAction *soundMenu(void) {
    NSMutableArray<NSString *> *changed = [NSMutableArray array];
    if (SGPlayerSpeedAllowed() && fabs(SGPlayerSpeed() - 1) >= 0.01) [changed addObject:speedText(SGPlayerSpeed())];
    if (SGPlayerPitchAvailable() && !pitchFollowing() && SGPlayerPitch() != 0) [changed addObject:semitonesText(SGPlayerPitch())];
    if (SGPlayerReverb() > 0) [changed addObject:[NSString stringWithFormat:@"Reverb %.0f%%", SGPlayerReverb()]];
    UIAction *open = [UIAction actionWithTitle:SGL(@"settings.player.sound_menu", @"Speed, Pitch & Reverb") image:symbol(@"slider.horizontal.3") identifier:nil
                                       handler:^(UIAction *action) { SGPlayerShowSpeedPitchPanel(sg_moreButton); }];
    open.subtitle = changed.count ? [changed componentsJoinedByString:@", "] : @"Normal";
    return open;
}

static NSString *sheetKind(void);

// Automatic, checked while nothing is picked and naming what the order chose, then the sources with lines for
// the track, in the order, the one picked checked, and the ones still asked named in a row of their own. The
// sources' rows are one line each, so the list fits without scrolling: a scrolled list runs under the
// submenu's title.
static NSArray<UIMenuElement *> *sourceItems(NSString *track, NSDictionary<NSString *, SGLyricsResult *> *offers, NSArray<NSString *> *asking) {
    NSString *current = SGLyricsChosenSource(track);
    UIAction *automatic = [UIAction actionWithTitle:SGL(@"settings.lyricssources.pick.automatic", @"Automatic") image:nil identifier:nil
                                            handler:^(UIAction *action) { SGLyricsChooseAutomatic(track); }];
    automatic.subtitle = current ? SGL(@"settings.lyricssources.pick.order", @"As the order chooses") : SGLyricsCreditFor(track);
    automatic.state = current ? UIMenuElementStateOff : UIMenuElementStateOn;
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray arrayWithObject:automatic];
    for (NSString *key in SGLyricsOrder()) {
        SGLyricsResult *offer = offers[key];
        if (!offer) continue;
        SGLyricsProvider *provider = SGLyricsProviderFor(key);
        UIAction *pick = [UIAction actionWithTitle:provider.name image:nil identifier:nil
                                           handler:^(UIAction *action) { SGLyricsChooseSource(track, key); }];
        pick.state = [key isEqualToString:current] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [items addObject:pick];
    }
    if (asking.count) {
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (NSString *key in SGLyricsOrder()) if ([asking containsObject:key]) [names addObject:SGLyricsProviderFor(key).name];
        UIAction *waiting = [UIAction actionWithTitle:SGL(@"settings.lyricssources.offers.asking", @"Still Asking") image:nil identifier:nil handler:^(UIAction *action) {}];
        waiting.subtitle = [names componentsJoinedByString:@", "];
        waiting.attributes = UIMenuElementAttributesDisabled;
        [items addObject:waiting];
    } else if (items.count == 1) {
        UIAction *none = [UIAction actionWithTitle:SGL(@"settings.lyricssources.offers.empty", @"No Source Has Lyrics") image:nil identifier:nil handler:^(UIAction *action) {}];
        none.attributes = UIMenuElementAttributesDisabled;
        [items addObject:none];
    }
    return items;
}

static UIMenu *lyricsSourceMenu(void) {
    NSString *track = SGKaraokePlayingTrack();
    if (!SGLyricsEnabled() || !track.length || [sheetKind() isEqualToString:@"episode"]) return nil;
    // The sources are asked as the ⋯ opens, and the submenu lists what has answered by the time it opens,
    // at once: a loading row swapped for the items changes its size under the finger, which clips it. A
    // source still out is named, and shows the next time.
    SGLyricsOffersSoFar(track, NULL);
    UIDeferredMenuElement *sources = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
        NSArray<NSString *> *asking = nil;
        NSDictionary<NSString *, SGLyricsResult *> *offers = SGLyricsOffersSoFar(track, &asking);
        completion(sourceItems(track, offers, asking));
    }];
    UIMenu *menu = [UIMenu menuWithTitle:SGL(@"settings.lyricssources.pick.menu", @"Lyrics Source") image:symbol(@"quote.bubble") identifier:nil options:0 children:@[sources]];
    menu.subtitle = SGLyricsCreditFor(track);
    return menu;
}

static NSArray<UIMenuElement *> *playerItems(void) {
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray arrayWithObject:soundMenu()];
    [items addObject:[UIAction actionWithTitle:SGLyricsPiPMenuTitle() image:symbol(@"pip") identifier:nil
        handler:^(UIAction *action) { SGLyricsPiPToggle(sg_moreButton); }]];
    // What plays after this, a song's or an episode's (PlayerQueue.m).
    [items addObject:[UIAction actionWithTitle:SGL(@"settings.player.queue.menu", @"Playing Next") image:symbol(@"list.bullet") identifier:nil
        handler:^(UIAction *action) { SGRPlayerShowQueue(sg_moreButton); }]];
    // Not for a podcast: LRCLIB has songs.
    UIAction *search = [sheetKind() isEqualToString:@"episode"] ? nil : SGRLyricsSearchAction(SGKaraokePlayingTrack());
    if (search) [items addObject:search];
    if (![sheetKind() isEqualToString:@"episode"])
        [items addObject:SGRLyricsStyleMenu(SGL(@"settings.lyricsstyle.menu", @"Lyrics Style"))];
    if (SGPlayerMenuOffersAnimatedArtwork()) {
        // Buttons named for what they do, not checkmarks: the HIG's changeable label for a toggled item.
        NSArray<NSArray *> *backgrounds = @[
            @[@(SGRPlayerBackgroundFluid), @"Show Fluid Artwork", @"drop"],
            @[@(SGRPlayerBackgroundAnimated), @"Show Animated Artwork", @"play.rectangle.on.rectangle"],
            @[@(SGRPlayerBackgroundVisualiser), @"Show Visualizer", @"waveform"],
        ];
        SGRPlayerBackgroundKind current = SGRPlayerBackground();
        for (NSArray *background in backgrounds) {
            SGRPlayerBackgroundKind kind = [background[0] integerValue];
            if (kind == current) continue;
            [items addObject:[UIAction actionWithTitle:background[1] image:symbol(background[2]) identifier:nil
                                               handler:^(UIAction *action) { SGRPlayerMenuSetBackground(kind); }]];
        }
    }
    UIMenu *lyrics = lyricsSourceMenu();
    if (lyrics) [items addObject:lyrics];
    return items;
}

// What the player is playing, from its URI (spotify:track:…, spotify:episode:…, spotify:local:…): a podcast's
// sheet has other rows than a song's.
static NSString *sheetKind(void) {
    NSArray<NSString *> *parts = [SGURIString(SGPlayerState().track.URI) componentsSeparatedByString:@":"];
    return parts.count > 2 ? parts[1] : @"";
}

void SGRPlayerMenuWatch(UIView *button) {
    sg_moreButton = button;
    SGRSystemMenuWatch(button, ^NSArray<UIMenuElement *> *{ return playerItems(); }, ^NSString *{ return sheetKind(); });
}
