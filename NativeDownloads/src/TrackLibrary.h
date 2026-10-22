#pragma once
#import <Foundation/Foundation.h>

void SAPInstallTrackLibrary(void);
// Add-only, single-shot. All native invocation/completion is asynchronous on main.
// requested is checked immediately before mutation; no read/toggle/remove path.
void SAPAddTrackToLikedSongs(NSString *uri, BOOL (^requested)(void),
                            void (^completion)(NSString *status, NSString *message));
