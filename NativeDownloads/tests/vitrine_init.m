// Exercise the production SGModPage init hook, including init replacement/nil.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <assert.h>
#import "AudioProbeUI.h"

static NSUInteger destroyed;
static NSArray *receivedSections;
static __weak id allocatedReceiver;
static __weak id replacement;
static NSUInteger mode;

@interface SGModPage : NSObject
- (instancetype)initWithTitle:(NSString *)title intro:(NSString *)intro
                     sections:(NSArray *)sections footer:(NSString *)footer;
@end
@implementation SGModPage
- (instancetype)initWithTitle:(NSString *)title intro:(NSString *)intro
                     sections:(NSArray *)sections footer:(NSString *)footer {
    receivedSections=sections;
    if(mode==1) {
        self=(id)[NSObject new];
        replacement=self;
        return self;
    }
    if(mode==2)return nil;
    return [super init];
}
- (void)dealloc {destroyed++;}
@end

// Match Vitrine's exported row factories; no page is presented by this fixture.
__attribute__((visibility("default")))
id SGPageRow(NSString *title,UIViewController *(^page)(void)) {return title;}
__attribute__((visibility("default")))
id SGActionRow(NSString *title,NSString *subtitle,void (^action)(void)) {return title;}
__attribute__((visibility("default")))
id SGWithTile(id row,NSString *symbol,UIColor *color) {return row;}
__attribute__((visibility("default")))
id SGSection(NSString *title,NSArray *rows) {return rows;}

int main(void) {
    @autoreleasepool {
        SAPInstallDownloadSettings();
        for(mode=0;mode<3;mode++) {
            NSUInteger before=destroyed;
            __weak id result;
            @autoreleasepool {
                SGModPage *page=[SGModPage alloc];
                allocatedReceiver=page;
                page=[page initWithTitle:@"Vitrine" intro:nil sections:@[@"existing"] footer:nil];
                result=page;
                assert(receivedSections.count==2);
                assert([receivedSections[0] isEqual:@"existing"]);
                assert([receivedSections[1] count]==2); // one manager and one Send log
                if(mode==0)assert(page==allocatedReceiver && destroyed==before);
                if(mode==1)assert(allocatedReceiver==nil && page==replacement && destroyed==before+1);
                if(mode==2)assert(page==nil && allocatedReceiver==nil && destroyed==before+1);
            }
            assert(result==nil && replacement==nil && destroyed==before+1);
        }
        mode=0;
        @autoreleasepool {
            id page=[[SGModPage alloc] initWithTitle:@"Other" intro:nil sections:@[@"existing"] footer:nil];
            assert(page && receivedSections.count==1);
        }
        puts("PASS: production Vitrine init hook preserves +1, substituted/nil receiver ownership and root-only rows");
    }
    return 0;
}
