// The redesign's Artists page: Apple Music's logo in place of the name on an artist's page, its animated artwork and
// photo, and what the redesign takes off the page. It leads with a preview of an artist's page
// (Kit/SGRPagePreview.h) that follows them.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Redesigned/Kit/SGRTokens.h"
#import "Redesigned/Kit/SGRPagePreview.h"
#import "Artist.h"

// The mock artist's photo, Spotify's and Apple Music's, and the popular tracks under the header.
static const NSUInteger kPhoto = 6, kApplePhoto = 2, kPopularTracks = 3, kAboutLines = 3;
// The Music, Video and Merch strip: a capsule each, the first lit.
static const NSUInteger kTabs = 3;
static const CGFloat kTab = 24, kTabWidth = 64, kTabGap = 8, kTabBar = 6, kTabBarShare = 0.6;
// The Artist pick and the Release countdown: a card with a cover or a glyph at its leading end and two lines.
static const CGFloat kCardRow = 48, kCardRadius = 10, kCardPad = 8, kCardGlyph = 18, kCardLine = 7, kCardLineGap = 6;
static const CGFloat kCardTitleShare = 0.5, kCardDetailShare = 0.32;   // of the room for text

// A card of the Music list: `leading` (a cover, or a glyph on glass) and a title over a line of detail.
static UIView *addCardRow(SGRPagePreview *card, UIView *leading) {
    UIView *body = [UIView new];
    body.clipsToBounds = YES;
    body.layer.cornerCurve = kCACornerCurveContinuous;
    UIView *title = SGRPreviewBar(SGRPrimary()), *detail = SGRPreviewBar(SGRSecondary());
    for (UIView *view in @[leading, title, detail]) [body addSubview:view];
    __weak SGRPagePreview *weakCard = card;
    UIView *part = [card addPartWithLayout:^CGFloat(UIView *view, CGFloat width, CGFloat unit) {
        // On the field of the photo shown.
        body.backgroundColor = SGRElevated(weakCard.fieldColor);
        CGFloat height = kCardRow * unit, pad = kCardPad * unit, side = height - 2 * pad, line = kCardLine * unit;
        body.frame = CGRectMake(SGRPagePreviewMargin, 0, width - 2 * SGRPagePreviewMargin, height);
        body.layer.cornerRadius = kCardRadius * unit;
        leading.frame = CGRectMake(pad, pad, side, side);
        leading.layer.cornerRadius = kCardRadius / 2 * unit;
        if (leading.subviews.count) SGRPreviewCenter(leading.subviews[0], leading.bounds, kCardGlyph * unit);
        CGFloat x = CGRectGetMaxX(leading.frame) + pad, room = body.bounds.size.width - x - pad, middle = height / 2;
        title.frame = CGRectMake(x, middle - line - kCardLineGap * unit / 2, room * kCardTitleShare, line);
        detail.frame = CGRectMake(x, middle + kCardLineGap * unit / 2, room * kCardDetailShare, line);
        return height;
    }];
    [part addSubview:body];
    return part;
}

// An artist as the redesign lays it out, from the top: the photo (Apple Music's while asked for, a badge on it while
// its animated artwork is) with the name, or the logo, the listeners and the controls; the Music, Video and Merch
// strip, the Release countdown and the Artist pick while they are kept; the popular tracks; the videos while kept;
// the discography; About while kept; over them the back button and the ⋯.
static SGRPagePreview *artistPreview(NSDictionary<NSString *, NSString *> *names) {
    SGRPagePreview *card = [[SGRPagePreview alloc] initWithLabel:SGL(@"settings.artist.preview.a11y", @"Preview of an artist")];
    SGRPreviewHeader *header = SGRPreviewAddHeader(card, kPhoto, @"livephoto", @"person.badge.plus");

    NSMutableArray<UIView *> *tabViews = [NSMutableArray array];
    for (NSUInteger i = 0; i < kTabs; i++) {
        UIView *tab = i == 0 ? SGRPreviewBar(SGRPrimary()) : SGRPreviewGlass();
        [tab addSubview:SGRPreviewBar(i == 0 ? UIColor.blackColor : SGRSecondary())];
        [tabViews addObject:tab];
    }
    UIView *tabs = [card addPartWithLayout:^CGFloat(UIView *view, CGFloat width, CGFloat unit) {
        CGFloat height = kTab * unit, tabWidth = kTabWidth * unit, bar = kTabBar * unit;
        [tabViews enumerateObjectsUsingBlock:^(UIView *tab, NSUInteger i, BOOL *stop) {
            tab.frame = CGRectMake(SGRPagePreviewMargin + i * (tabWidth + kTabGap * unit), 0, tabWidth, height);
            tab.layer.cornerRadius = height / 2;
            tab.subviews[0].frame = CGRectMake(tabWidth * (1 - kTabBarShare) / 2, (height - bar) / 2, tabWidth * kTabBarShare, bar);
        }];
        return height;
    }];
    for (UIView *tab in tabViews) [tabs addSubview:tab];
    tabs.accessibilityLabel = names[SGRKeyArtistHideTabs];

    UIView *calendar = SGRPreviewGlass();
    SGRPreviewAddSymbol(calendar, @"calendar", SGRPrimary());
    UIView *countdown = addCardRow(card, calendar);
    countdown.accessibilityLabel = names[SGRKeyArtistHideCountdown];
    UIView *pick = addCardRow(card, SGRPreviewCover(kPhoto + 1));
    pick.accessibilityLabel = names[SGRKeyArtistHidePick];
    SGRPreviewAddTracks(card, kPopularTracks, YES, kPhoto + 2);
    UIView *videos = SGRPreviewAddShelf(card, names[SGRKeyArtistHideVideos], kPhoto + 3, SGRPreviewTilesWide);
    videos.accessibilityLabel = names[SGRKeyArtistHideVideos];
    SGRPreviewAddShelf(card, nil, kPhoto + 4, SGRPreviewTilesSquare);
    UIView *about = SGRPreviewAddParagraph(card, kAboutLines);
    about.accessibilityLabel = names[SGRKeyArtistHideAbout];
    SGRPreviewAddTopBar(card);

    card.state = ^id<NSObject> {
        NSMutableDictionary *state = [NSMutableDictionary dictionary];
        state[SGRKeyArtistLogo] = @(SGEnabled(SGRKeyArtistLogo));
        // As ArtistHeader.x asks: the switch, and Apple Music among the animated artwork's sources.
        state[SGRKeyArtistMotion] = @(SGEnabled(SGRKeyArtistMotion) && SGMotionAppleMusicOn());
        state[SGRKeyArtistApplePhoto] = @(SGHidden(SGRKeyArtistApplePhoto));
        state[SGRKeyArtistHideVideos] = @(SGEnabled(SGRKeyArtistHideVideos));
        state[SGRKeyArtistHideTabs] = @(SGEnabled(SGRKeyArtistHideTabs));
        state[SGRKeyArtistHidePick] = @(SGHidden(SGRKeyArtistHidePick));
        state[SGRKeyArtistHideCountdown] = @(SGHidden(SGRKeyArtistHideCountdown));
        state[SGRKeyArtistHideAbout] = @(SGHidden(SGRKeyArtistHideAbout));
        return state;
    };
    card.apply = ^(SGRPagePreview *preview, NSDictionary *state) {
        BOOL (^on)(NSString *) = ^BOOL(NSString *key) { return [state[key] boolValue]; };
        BOOL logo = on(SGRKeyArtistLogo), motion = on(SGRKeyArtistMotion), applePhoto = on(SGRKeyArtistApplePhoto);
        // The photo shown, and the page's field and the header's dissolve in its color, as ArtistHeader.x takes it.
        NSUInteger photo = applePhoto ? kApplePhoto : kPhoto;
        if (header.showsLogo != logo || header.badge.alpha != motion || header.cover != photo) [preview revealPart:header.part];
        header.showsLogo = logo;
        header.badge.alpha = motion;
        header.cover = photo;
        NSMutableArray<NSString *> *headerNames = [NSMutableArray array];
        for (NSString *key in @[SGRKeyArtistLogo, SGRKeyArtistMotion, SGRKeyArtistApplePhoto]) if (on(key)) [headerNames addObject:names[key]];
        header.part.accessibilityLabel = SGRPreviewList(headerNames);
        [preview setPart:tabs shown:!on(SGRKeyArtistHideTabs)];
        [preview setPart:countdown shown:!on(SGRKeyArtistHideCountdown)];
        [preview setPart:pick shown:!on(SGRKeyArtistHidePick)];
        [preview setPart:videos shown:!on(SGRKeyArtistHideVideos)];
        [preview setPart:about shown:!on(SGRKeyArtistHideAbout)];
    };
    return card;
}

UIViewController *SGRArtistSettingsPage(void) {
    NSArray<SGModRow *> *appleMusic = @[
        SGSwitchRow(SGL(@"settings.artist.logos.title", @"Artist logos"), SGL(@"settings.artist.logos.subtitle", @"In place of the name on an artist's page"), SGRKeyArtistLogo),
        SGSwitchRow(SGL(@"settings.artist.motion.title", @"Animated artist artwork"), nil, SGRKeyArtistMotion),
        SGOptionRow(SGL(@"settings.artist.apple_photo.title", @"Apple Music artist photo"), nil, SGRKeyArtistApplePhoto),
    ];
    NSArray<SGModRow *> *hide = @[
        SGSwitchRow(SGL(@"settings.artist.hide.videos.title", @"Videos"), SGL(@"settings.artist.hide.videos.subtitle", @"In the Music list, and in the Video tab"), SGRKeyArtistHideVideos),
        SGSwitchRow(SGL(@"settings.artist.hide.tabs.title", @"Music, Video and Merch tabs"), SGL(@"settings.artist.hide.tabs.subtitle", @"Without them the Music list is the page"), SGRKeyArtistHideTabs),
        SGHideRow(SGL(@"settings.artist.hide.pick.title", @"Artist pick"), nil, SGRKeyArtistHidePick),
        SGHideRow(SGL(@"settings.artist.hide.countdown.title", @"Release countdown"), SGL(@"settings.artist.hide.countdown.subtitle", @"The pre-save of an upcoming release"), SGRKeyArtistHideCountdown),
        SGHideRow(SGL(@"settings.artist.hide.about.title", @"About"), nil, SGRKeyArtistHideAbout),
    ];
    // The card names what it shows by the rows' own titles, by their keys.
    NSMutableDictionary<NSString *, NSString *> *names = [NSMutableDictionary dictionary];
    for (SGModRow *row in [appleMusic arrayByAddingObjectsFromArray:hide]) names[row.key] = row.title;

    return SGRPagePreviewPage(SGL(@"settings.artist.title", @"Artists"), artistPreview(names), SGRestartNote, @[
        SGNotedSection(SGL(@"settings.artist.apple_music.header", @"Apple Music"), appleMusic,
                       SGL(@"settings.artist.apple_music.note", @"Only the artist's name is sent to Apple Music.")),
        SGSection(SGL(@"settings.artist.hide_on_page.header", @"Hide on an artist's page"), hide),
    ]);
}
