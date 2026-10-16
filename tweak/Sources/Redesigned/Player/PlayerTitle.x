// The song's title and artist as the redesign shows them: without the extras Simplify song titles takes off, and
// in the user's language when Translate song titles has a translation in (Shared/Lyrics, Shared/LyricsTranslation).
// Spotify's own two labels on the player (now-playing-title-label, now-playing-subtitle-label, PlayerLyrics.x's
// tree) are given a subclass of their own class that draws the shown text whenever Spotify sets its own, the way
// key-value observing subclasses an object: no other label in the app is touched, and each still reads as its class.
#import <objc/runtime.h>
#import <objc/message.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"
#import "Shared/Player/PlayerState.h"
#import "Headers/SPTPlayer.h"
#import "Player.h"

static char kOriginalKey, kRoleKey;
// Spotify's own class's setText: for each subclass made, by the subclass. Found by the class the subclass was
// made of, never by the label's class at the time of the call: key-value observing can put a subclass of its
// own above this one, and the class above would then be this one, and the call would come back here forever.
static NSMutableDictionary<NSString *, NSValue *> *sg_setters;
static BOOL sg_simplify, sg_on;
static __weak UILabel *sg_titleLabel, *sg_artistLabel;

NSString *SGRShownTitle(NSString *trackID, NSString *title, NSString *artist, NSString **shownArtist) {
    NSString *translatedArtist = nil;
    NSString *translated = trackID ? SGLyricsTranslatedTitle(trackID, title, artist, &translatedArtist) : nil;
    NSString *shown = translated.length ? translated : title;
    if (sg_simplify && shown.length) shown = SGLyricsSimplifiedTitle(shown);
    if (shownArtist) *shownArtist = translatedArtist.length ? translatedArtist : artist;
    return shown;
}

static NSString *idOf(SPTPlayerTrack *track) {
    id uri = track.URI;
    NSString *text = [uri isKindOfClass:NSURL.class] ? ((NSURL *)uri).absoluteString : [uri description];
    return [text hasPrefix:@"spotify:track:"] ? [text substringFromIndex:@"spotify:track:".length] : nil;
}

// What the label draws for the text Spotify gave it; nil to draw Spotify's. Only the playing track's own title
// and artist are changed: an ad, a podcast or the DJ's words are left as they are.
static NSString *shownFor(BOOL title, NSString *text) {
    SPTPlayerTrack *track = SGPlayerState().track;
    if (!text.length || !track) return nil;
    if (![text isEqualToString:title ? track.trackTitle : track.artistName]) return nil;
    NSString *artist = nil;
    NSString *shown = SGRShownTitle(idOf(track), track.trackTitle, track.artistName, &artist);
    NSString *out = title ? shown : artist;
    return out.length && ![out isEqualToString:text] ? out : nil;
}

static void setShownText(UILabel *self, SEL _cmd, NSString *text) {
    BOOL title = [objc_getAssociatedObject(self, &kRoleKey) boolValue];
    NSString *shown = sg_on ? shownFor(title, text) : nil;
    objc_setAssociatedObject(self, &kOriginalKey, text, OBJC_ASSOCIATION_COPY_NONATOMIC);
    void (*draw)(id, SEL, NSString *) = NULL;
    for (Class class = object_getClass(self); class && !draw; class = class_getSuperclass(class)) {
        draw = (void *)[sg_setters[NSStringFromClass(class)] pointerValue];
    }
    if (!draw) draw = (void *)class_getMethodImplementation(UILabel.class, _cmd);
    draw(self, _cmd, shown ?: text);
}

// The label's own class with setText: drawing the shown text, made once per class Spotify uses.
static Class shownClassFor(Class original) {
    NSString *name = [@"SGRShownTitle_" stringByAppendingString:NSStringFromClass(original)];
    Class made = NSClassFromString(name);
    if (made) return made;
    made = objc_allocateClassPair(original, name.UTF8String, 0);
    if (!made) return nil;
    if (!sg_setters) sg_setters = [NSMutableDictionary dictionary];
    sg_setters[name] = [NSValue valueWithPointer:(void *)class_getMethodImplementation(original, @selector(setText:))];
    class_addMethod(made, @selector(setText:), (IMP)setShownText, "v@:@");
    // The label still answers with Spotify's class, as one key-value observing has subclassed does.
    Class (^asked)(id) = ^Class(id me) { return original; };
    class_addMethod(made, @selector(class), imp_implementationWithBlock(asked), "#@:");
    objc_registerClassPair(made);
    return made;
}

static void adopt(UILabel *label, BOOL title) {
    if (![label isKindOfClass:UILabel.class]) return;
    Class current = object_getClass(label);
    BOOL ours = NO;
    for (Class class = current; class && !ours; class = class_getSuperclass(class)) ours = [NSStringFromClass(class) hasPrefix:@"SGRShownTitle_"];
    if (!ours) {
        Class shown = shownClassFor(current);
        if (!shown) return;
        objc_setAssociatedObject(label, &kOriginalKey, label.text, OBJC_ASSOCIATION_COPY_NONATOMIC);
        object_setClass(label, shown);
    }
    objc_setAssociatedObject(label, &kRoleKey, @(title), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [label setText:objc_getAssociatedObject(label, &kOriginalKey)];
}

static void refresh(void) {
    UILabel *title = sg_titleLabel, *artist = sg_artistLabel;
    if (title) [title setText:objc_getAssociatedObject(title, &kOriginalKey)];
    if (artist) [artist setText:objc_getAssociatedObject(artist, &kOriginalKey)];
}

void SGRShownTitleWatch(UIView *unit) {
    if (!sg_on || !unit) return;
    UILabel *title = (UILabel *)SGRFindByIdentifier(unit, @"now-playing-title-label", NULL);
    UILabel *artist = (UILabel *)SGRFindByIdentifier(unit, @"now-playing-subtitle-label", NULL);
    if ([title isKindOfClass:UILabel.class] && sg_titleLabel != title) {
        sg_titleLabel = title;
        adopt(title, YES);
    }
    if ([artist isKindOfClass:UILabel.class] && sg_artistLabel != artist) {
        sg_artistLabel = artist;
        adopt(artist, NO);
    }
}

%ctor {
    if (!SGRedesignedUI()) return;
    sg_simplify = SGFlag(SGKeyLyricsSimplifyTitles, NO);
    sg_on = sg_simplify || SGFlag(SGKeyLyricsTranslateTitles, NO);
    if (!sg_on) return;
    [NSNotificationCenter.defaultCenter addObserverForName:SGTranslatedTitleDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        dispatch_async(dispatch_get_main_queue(), ^{ refresh(); });
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:SGTitleTranslationSettingsDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        dispatch_async(dispatch_get_main_queue(), ^{ refresh(); });
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:SGSimplifyTitlesDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        dispatch_async(dispatch_get_main_queue(), ^{
            sg_simplify = SGFlag(SGKeyLyricsSimplifyTitles, NO);
            refresh();
        });
    }];
    SGLog(@"redesign player: titles shown %@%@", sg_simplify ? @"simplified" : @"as they are", SGFlag(SGKeyLyricsTranslateTitles, NO) ? @", translated" : @"");
}
