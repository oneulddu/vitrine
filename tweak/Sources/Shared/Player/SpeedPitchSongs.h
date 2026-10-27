// Per-song control-side persistence. All calls and observer reports run on main, never render.
#import <Foundation/Foundation.h>
#import "PlayerState.h"

#define SGKeySpeedPitchSongs @"spotifyglass.speedPitch.songs"
#define SGKeySpeedPitchBaseline @"spotifyglass.speedPitch.baseline"
extern NSNotificationName const SGSpeedPitchSongDidChange;
NSString *SGSpeedPitchSongIdentifier(NSString *uri);

@interface SGSpeedPitchSongs : NSObject <SGPlayerStateObserver>
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
@property (nonatomic, readonly) BOOL hasSong;
@property (nonatomic, readonly) BOOL kept;
- (void)setKept:(BOOL)kept;
- (void)valuesChanged:(NSString *)control;
- (void)flush;
@end

void SGSpeedPitchSongsStart(void);
BOOL SGPlayerSongCanKeep(void);
BOOL SGPlayerSongKept(void);
void SGPlayerSongSetKept(BOOL kept);
void SGSpeedPitchSongValuesChanged(NSString *control);
