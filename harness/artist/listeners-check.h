// Behaviour checks use the real header and collection hooks. About is deliberately
// far outside the viewport: scrolling back must not forget a known destination.
static UIView *listenersFindID(UIView *root, NSString *identifier) {
    if ([root.accessibilityIdentifier isEqualToString:identifier]) return root;
    for (UIView *child in root.subviews) {
        UIView *found = listenersFindID(child, identifier);
        if (found) return found;
    }
    return nil;
}

static NSUInteger listenersTextCount(UIView *root, NSString *text) {
    if (root.hidden || root.alpha == 0 || root.accessibilityElementsHidden) return 0;
    // UIKit loads UILabel's accessibility implementation when an AX client
    // connects. The headless harness checks rendered text and exclusion flags,
    // not the service-dependent default of isAccessibilityElement.
    NSUInteger count = [root isKindOfClass:UILabel.class] &&
        [((UILabel *)root).text isEqualToString:text] ? 1 : 0;
    for (UIView *child in root.subviews) count += listenersTextCount(child, text);
    return count;
}

static NSArray *listenersItems(BOOL about) {
    NSMutableArray *items = [NSMutableArray array];
    // Offscreen destination, not a hand-built visible-cell flag.
    for (NSUInteger i = 0; i < 60; i++)
        [items addObject:@[@"Components.UI.RetrievalRowElementUI", @64, @"A song"]];
    [items addObject:about ? @[@"Components.UI.CreatorBiographyCard", @180]
                          : @[@"Components.UI.RetrievalRowElementUI", @64, @"No biography"]];
    return items;
}

static void listenersExpect(UIView *root, UIView *header, NSString *text, NSUInteger count, NSString *reason) {
    [header layoutIfNeeded];
    UIView *info = veilFind(root, @"SGRHeaderInfo");
    [info layoutIfNeeded];
    NSUInteger actual = listenersTextCount(info, text);
    if (actual != count) {
        NSMutableArray *labels = [NSMutableArray array];
        for (UIView *view in info.subviews) {
            if (![view isKindOfClass:UILabel.class]) continue;
            [labels addObject:[NSString stringWithFormat:@"%@ hidden=%d alpha=%.2f a11y=%d elementsHidden=%d",
                ((UILabel *)view).text, view.hidden, view.alpha, view.isAccessibilityElement, view.accessibilityElementsHidden]];
        }
        HARNESS_FAIL(@"listeners %@: expected %lu visible/accessibility representations, got %lu; info=%@ labels=%@",
                     reason, (unsigned long)count, (unsigned long)actual, info, labels);
    }
}

static void listenersReconfigure(UICollectionView *list, dispatch_block_t completed) {
    UICollectionViewDiffableDataSource *dataSource = (id)list.dataSource;
    NSIndexPath *path = [NSIndexPath indexPathForItem:60 inSection:0];
    UICollectionViewCell *retained = [list cellForItemAtIndexPath:path];
    HARNESS_CHECK(retained);
    NSDiffableDataSourceSnapshot *snapshot = [dataSource snapshot];
    [snapshot reconfigureItemsWithIdentifiers:@[@60]];
    [dataSource applySnapshot:snapshot animatingDifferences:NO completion:^{
        [list layoutIfNeeded];
        // A test-fixture guarantee: exercise reconfiguration, not dequeue/reuse.
        HARNESS_CHECK([list cellForItemAtIndexPath:path] == retained);
        [retained setNeedsLayout];
        [retained layoutIfNeeded];
        completed();
    }];
}

static void listenersTransitions(UIViewController *root, UIView *header, UIView *more,
                                UICollectionView *list, SGRListSource *source, BOOL moved) {
    NSString *text = @"91,2 M auditeurs par mois";
    // Header-first: an existing About cell is configured for B without reuse.
    more.accessibilityIdentifier = @"Components.UI.ContextMenuButton-artist-B";
    [header setNeedsLayout];
    UICollectionViewCell *previous = [list cellForItemAtIndexPath:[NSIndexPath indexPathForItem:60 inSection:0]];
    [previous setNeedsLayout];
    [previous layoutIfNeeded];
    listenersExpect(root.view, header, text, 1, @"new header before About configuration");
    listenersReconfigure(list, ^{
        listenersExpect(root.view, header, text, moved ? 0 : 1, @"retained About reconfigured for new artist");

        // Source-first: the native identity/configuration changes before the
        // redesigned header has had a pass. Its valid C receipt must survive it.
        more.accessibilityIdentifier = @"Components.UI.ContextMenuButton-artist-C";
        listenersReconfigure(list, ^{
            [header setNeedsLayout];
            listenersExpect(root.view, header, text, moved ? 0 : 1, @"configuration before header pass");

            // A's stale About was configured while its artist was unavailable.
            // Seeing it for the first time under D cannot confer D's identity.
            more.accessibilityIdentifier = @"Components.UI.ContextMenuButton";
            listenersReconfigure(list, ^{
                source.items = listenersItems(NO);
                more.accessibilityIdentifier = @"Components.UI.ContextMenuButton-artist-D-without-about";
                [header setNeedsLayout];
                UICollectionViewCell *stale = [list cellForItemAtIndexPath:[NSIndexPath indexPathForItem:60 inSection:0]];
                [stale setNeedsLayout];
                [stale layoutIfNeeded];
                listenersExpect(root.view, header, text, 1, @"unstamped stale About cannot belong to new artist");
                listenersReconfigure(list, ^{
                    listenersExpect(root.view, header, text, 1, @"new artist configured without About");

                    // Removing About in the source before the next header's
                    // identity changes must also leave the new header intact.
                    more.accessibilityIdentifier = @"Components.UI.ContextMenuButton-artist-E-without-about";
                    [header setNeedsLayout];
                    listenersExpect(root.view, header, text, 1, @"source without About before new header");
                    NSLog(@"[harness] PASS artist listeners: unavailable, late text, localized, accessibility, About, offscreen, recycled, reconfigured");
                    exit(0);
                });
            });
        });
    });
}

static void verifyListeners(UIViewController *root, UIView *header, UICollectionView *list, SGRListSource *source) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    BOOL moved = [defaults boolForKey:@"spotifyglass.redesign.artist.listenersInAbout"] &&
                 ![defaults boolForKey:@"spotifyglass.redesign.artist.hide.about"];
    NSString *original = @"58,4M monthly listeners";
    NSString *localized = @"월별 리스너 123,456,789,012명 — 매달 전 세계에서 듣는 사람";
    UILabel *metadata = (UILabel *)listenersFindID(header, @"Components.Header.UI.Metadata-internal");
    UIView *more = listenersFindID(header, @"Components.UI.ContextMenuButton-7n2wHs1TKAczGzO7Dd2rGr");
    HARNESS_CHECK(metadata && more);
    listenersExpect(root.view, header, original, 1, @"artist without About");

    // Late localized metadata must reach the header without a caller asking the
    // header to lay itself out; only UIKit's existing dirty passes are drained.
    metadata.text = localized;
    if (![defaults boolForKey:@"spotifyglass.redesign.artist.listenersInAbout"]) [header setNeedsLayout];
    listenersExpect(root.view, header, localized, 1, @"late localized metadata");
    root.traitOverrides.preferredContentSizeCategory = UIContentSizeCategoryAccessibilityExtraExtraExtraLarge;
    [root.view layoutIfNeeded];
    listenersExpect(root.view, header, localized, 1, @"accessibility text size keeps the full source");

    source.items = listenersItems(YES);
    [list reloadData];
    [list layoutIfNeeded];
    [list scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:60 inSection:0]
                atScrollPosition:UICollectionViewScrollPositionBottom animated:NO];
    [list layoutIfNeeded];
    dispatch_async(dispatch_get_main_queue(), ^{
        [list layoutIfNeeded];
        [header layoutIfNeeded];
        listenersExpect(root.view, header, localized, moved ? 0 : 1, @"About present / option off / About hidden");
        [list setContentOffset:CGPointZero animated:NO];
        [list layoutIfNeeded];
        listenersExpect(root.view, header, localized, moved ? 0 : 1, @"About offscreen remains a destination");

        metadata.attributedText = [[NSAttributedString alloc] initWithString:@"91,2 M auditeurs par mois"];
        if (!moved) [header setNeedsLayout];
        listenersExpect(root.view, header, @"91,2 M auditeurs par mois", moved ? 0 : 1, @"late attributed count");

        source.items = listenersItems(NO);
        [list reloadData];
        [list layoutIfNeeded];
        listenersExpect(root.view, header, @"91,2 M auditeurs par mois", 1, @"About removed from the same artist");
        source.items = listenersItems(YES);
        [list reloadData];
        [list layoutIfNeeded];
        [list scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:60 inSection:0]
                    atScrollPosition:UICollectionViewScrollPositionBottom animated:NO];
        [list layoutIfNeeded];
        listenersExpect(root.view, header, @"91,2 M auditeurs par mois", moved ? 0 : 1, @"About restored");

        if ([defaults boolForKey:@"spotifyglass.redesign.artist.hide.about"]) {
            // A collapsed About has no retained visible cell to reconfigure.
            // Check its actual contract instead: rebinding the artist cannot
            // remove the header line when the destination is disabled.
            more.accessibilityIdentifier = @"Components.UI.ContextMenuButton-hidden-about-artist";
            [header setNeedsLayout];
            listenersExpect(root.view, header, @"91,2 M auditeurs par mois", 1, @"recycled page with About hidden");
            NSLog(@"[harness] PASS artist listeners: hidden About, late text, localized, accessibility, recycled");
            exit(0);
        }
        listenersTransitions(root, header, more, list, source, moved);
    });
}
