#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Launch hook of the Notti SDK. Implementation detail, not API: `+load` asks `NottiDelegateInstaller`
/// (Swift, in `NottiSDK`) to install the delegate integration at process launch (DEL-01).
///
/// The counters exist only for the proof tests and the CI build check. They are not documented API.
@interface NottiBootstrap : NSObject

/// How many times `+load` ran in this process (1 when the hook is linked).
@property (class, readonly) NSUInteger loadCount;

/// How many times `+load` found and called `NottiDelegateInstaller`.
@property (class, readonly) NSUInteger installCount;

@end

NS_ASSUME_NONNULL_END
