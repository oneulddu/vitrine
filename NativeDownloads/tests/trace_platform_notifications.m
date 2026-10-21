// Links the real TracePlatform.m; only its trace sink/report dependencies are spies.
#import <UIKit/UIKit.h>
#import <AVFAudio/AVFAudio.h>
#import "TracePlatform.h"
#import "DiagnosticTrace.h"
#import "NativeOffline.h"
#import "NativeKeyTrace.h"
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static atomic_bool active;
static NSMutableArray<NSNumber *> *recorded;
static BOOL finished;

static void require(BOOL condition,const char *message) {
    if(!condition){fprintf(stderr,"FAIL: %s\n",message);exit(EXIT_FAILURE);}
}

bool SAPTraceIsActive(void) {return atomic_load(&active);}
NSDictionary *SAPTraceHookManifest(void) {return @{};}
NSDictionary *SAPKeyRequestModeReport(void) {return @{};}
NSDictionary *SAPNativeKeyTraceReport(void) {return @{};}
void SAPTraceEvent(const char *category,const char *stage,SAPTraceID operation,NSDictionary *facts) {
    if(strcmp(category,"lifecycle")||strcmp(stage,"notification"))return;
    // Ignore genuine simulator notifications; these values mark only our posts.
    id reason=facts[@"route_change_reason"],interruption=facts[@"interruption_type"];
    NSNumber *marker=[reason isKindOfClass:NSNumber.class]?reason:
        [interruption isKindOfClass:NSNumber.class]?interruption:nil;
    if(marker.integerValue<1000)return;
    require(NSThread.isMainThread,"notification/route processing must finish on main");
    require(SAPTraceIsActive(),"disabled trace sink must never be called");
    [recorded addObject:marker];
}

static void postWhileMainBlocked(NSNotificationName name,NSInteger marker) {
    require(NSThread.isMainThread,"fixture must block the actual main thread");
    NSUInteger before=recorded.count;
    dispatch_semaphore_t returned=dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        @autoreleasepool {
            require(!NSThread.isMainThread,"notification must originate off main");
            NSString *key=[name isEqual:AVAudioSessionRouteChangeNotification]?
                AVAudioSessionRouteChangeReasonKey:AVAudioSessionInterruptionTypeKey;
            [NSNotificationCenter.defaultCenter postNotificationName:name object:nil userInfo:@{key:@(marker)}];
            dispatch_semaphore_signal(returned);
        }
    });
    // The old queue:mainQueue observer deadlocks here until this bounded failure.
    require(dispatch_semaphore_wait(returned,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0,
            "background notification posting waited for the blocked main thread");
    require(recorded.count==before,"notification handling must be asynchronously deferred");
}

static void finishFreshDelivery(void) {
    require([recorded isEqualToArray:@[@1001,@1002,@5001]],
            "only live-generation notifications may record, including after re-enable");
    atomic_store(&active,false);
    SAPTracePlatformSetActive(false);
    dispatch_async(dispatch_get_main_queue(),^{finished=YES;});
}

static void freshRegistration(void) {
    postWhileMainBlocked(AVAudioSessionRouteChangeNotification,5001);
    dispatch_async(dispatch_get_main_queue(),^{finishFreshDelivery();});
}

static void afterDisabledTeardown(void) {
    postWhileMainBlocked(AVAudioSessionRouteChangeNotification,4001);
    require(recorded.count==2,"posting after disabled teardown must not record");
    atomic_store(&active,true);
    SAPTracePlatformSetActive(true);
    dispatch_async(dispatch_get_main_queue(),^{freshRegistration();});
}

static void verifyDisabledDelivery(void) {
    require(recorded.count==2,"queued-before-disable and posted-while-disabled events must not record");
    SAPTracePlatformSetActive(false);
    dispatch_async(dispatch_get_main_queue(),^{afterDisabledTeardown();});
}

static void verifyGenerationDrop(void) {
    require(recorded.count==2,"events queued before disable/re-enable must not enter the new generation");
    postWhileMainBlocked(AVAudioSessionRouteChangeNotification,3001);
    // Hold the platform generation fixed here to exercise the separate active
    // check at delivery, rather than letting a generation check hide its absence.
    atomic_store(&active,false);
    postWhileMainBlocked(AVAudioSessionInterruptionNotification,3002);
    dispatch_async(dispatch_get_main_queue(),^{verifyDisabledDelivery();});
}

static void queueStaleGeneration(void) {
    require([recorded isEqualToArray:@[@1001,@1002]],"route and interruption notifications must both deliver");
    postWhileMainBlocked(AVAudioSessionRouteChangeNotification,2001);
    postWhileMainBlocked(AVAudioSessionInterruptionNotification,2002);
    atomic_store(&active,false);
    SAPTracePlatformSetActive(false);
    atomic_store(&active,true);
    SAPTracePlatformSetActive(true);
    // Old deliveries are ahead of re-registration in the queue, but must still
    // be rejected: SetActive invalidates their generation synchronously.
    dispatch_async(dispatch_get_main_queue(),^{verifyGenerationDrop();});
}

static void normalInterruption(void) {
    require([recorded isEqualToArray:@[@1001]],"live route notification must deliver after main unblocks");
    postWhileMainBlocked(AVAudioSessionInterruptionNotification,1002);
    dispatch_async(dispatch_get_main_queue(),^{queueStaleGeneration();});
}

int main(void) {
    @autoreleasepool {
        require(NSThread.isMainThread,"fixture entry must run on main");
        recorded=[NSMutableArray array];
        atomic_store(&active,true);
        SAPTracePlatformSetActive(true);
        dispatch_async(dispatch_get_main_queue(),^{
            postWhileMainBlocked(AVAudioSessionRouteChangeNotification,1001);
            dispatch_async(dispatch_get_main_queue(),^{normalInterruption();});
        });
        NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:15];
        NSTimer *keepAlive=[NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *timer){
            require(deadline.timeIntervalSinceNow>0,"main-queue delivery fixture timed out");
        }];
        while(!finished)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        [keepAlive invalidate];
        puts("PASS: production TracePlatform notifications return off-main without waiting; delivery stays on main; disabled and stale-generation events drop");
    }
    return 0;
}
