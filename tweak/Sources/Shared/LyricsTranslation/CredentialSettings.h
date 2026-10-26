#import <UIKit/UIKit.h>

NSString *SGLyricsCleanCredential(NSString *text, NSUInteger maxCharacters);
void SGLyricsCredentialPrompt(NSString *title, NSString *message, NSString *placeholder,
                             BOOL (^valid)(NSString *), void (^save)(NSString *),
                             BOOL (^hasKey)(void), void (^remove)(void));
