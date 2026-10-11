#import "NottiBootstrap.h"

#import <objc/message.h>
#import <stdatomic.h>

static _Atomic NSUInteger gLoadCount = 0;
static _Atomic NSUInteger gInstallCount = 0;

@implementation NottiBootstrap

// Runs before `main`. DEL-14: no UIKit, no I/O, no logging and no access to the runtime or the core here.
// The only work is a class lookup by name and one message send. The Swift installer lives in `NottiSDK`,
// which depends on this target, so a direct reference would be a dependency cycle.
+ (void)load {
    atomic_fetch_add(&gLoadCount, 1);

    Class installer = NSClassFromString(@"NottiDelegateInstaller");
    SEL install = NSSelectorFromString(@"install");
    if (installer == Nil || ![installer respondsToSelector:install]) {
        return;
    }
    ((void (*)(id, SEL))objc_msgSend)(installer, install);
    atomic_fetch_add(&gInstallCount, 1);
}

+ (NSUInteger)loadCount {
    return atomic_load(&gLoadCount);
}

+ (NSUInteger)installCount {
    return atomic_load(&gInstallCount);
}

@end
