@import XCTest;
@import NottiSDK;
@import UIKit;
@import UserNotifications;

// API-13: every P1 capability is callable from Objective-C. These tests only use
// the public ObjC surface (no internal seam), so they run against the shared
// runtime and avoid anything that reaches the network: initialize is called with
// invalid values (ignored and logged without values), and profile calls made
// before initialize are either dropped or undone.

@interface NottiObjCTests : XCTestCase
@end

@implementation NottiObjCTests

- (void)tearDown {
    NottiSDK.logLevel = NottiLogLevelError;
    [super tearDown];
}

- (void)testNottiEntryPointsAreCallable {
    // Invalid on purpose: empty appId is ignored by the facade (no network).
    [NottiSDK initializeWithAppId:@"" clientKey:@"" baseUrl:nil];
    [NottiSDK initializeWithAppId:@"" clientKey:@"" baseUrl:@"https://notti.example.invalid"];
    [NottiSDK initializeWithAppId:@"" clientKey:@"" baseUrl:nil opensInAppURLs:NO]; // AD-020 selector, ignored
    [NottiSDK login:@"user-fixture"];   // dropped before initialize
    [NottiSDK logout];
    (void)NottiSDK.deviceId;         // nil or a persisted id
    [NottiSDK setLocationSharingEnabled:NO];

    __block NSInteger deviceIdCalls = 0;
    NottiSubscription *subscription = [NottiSDK addDeviceIdChangedListener:^(NSString *deviceId) {
        (void)deviceId;
        deviceIdCalls += 1;
    }];
    XCTAssertNotNil(subscription);
    [subscription remove];
    [subscription remove]; // idempotent
    XCTAssertEqual(deviceIdCalls, 0);
}

// IAM-24, IAM-44: the In-App entry points compile only with these selector names. Before initialize
// `trackEvent:` is a no-op, so nothing reaches the network.
- (void)testInAppEntryPointsAreCallable {
    [NottiSDK trackEvent:@"fixture_event"];
    [NottiSDK trackEvent:@""];

    __block NSInteger clicks = 0;
    NottiSubscription *subscription = [NottiInAppMessages addClickListener:^(NSDictionary *click) {
        (void)click;
        clicks += 1;
    }];
    XCTAssertNotNil(subscription);
    [subscription remove];
    XCTAssertEqual(clicks, 0);
}

- (void)testLogLevelRoundTripsThroughTheObjCEnum {
    XCTAssertEqual(NottiSDK.logLevel, NottiLogLevelError, @"default level");
    NSArray<NSNumber *> *levels = @[
        @(NottiLogLevelNone), @(NottiLogLevelError), @(NottiLogLevelWarn),
        @(NottiLogLevelInfo), @(NottiLogLevelDebug), @(NottiLogLevelVerbose)
    ];
    for (NSNumber *level in levels) {
        NottiSDK.logLevel = (NottiLogLevel)level.integerValue;
        XCTAssertEqual(NottiSDK.logLevel, (NottiLogLevel)level.integerValue);
    }
}

- (void)testUserEntryPointsAreCallable {
    // Tags and subscription need a registered device: dropped before initialize.
    [NottiUser addTag:@"plan" value:@"vip"];
    [NottiUser addTags:@{@"lang": @"pt", @"count": @3}];
    [NottiUser removeTag:@"plan"];
    [NottiUser removeTags:@[@"lang", @"count"]];
    [NottiUser setSubscription:YES];
    // Email and phone are persisted before initialize: set, then undo.
    [NottiUser setEmail:@"user@example.invalid"];
    [NottiUser clearEmail];
    [NottiUser setPhone:@"+10000000000"];
    [NottiUser clearPhone];
}

- (void)testNotificationsEntryPointsAreCallable {
    XCTestExpectation *permission = [self expectationWithDescription:@"permission completion"];
    [NottiNotifications requestPermission:^(BOOL granted) {
        XCTAssertTrue(NSThread.isMainThread);
        XCTAssertFalse(granted, @"before initialize the core answers NO without prompting");
        [permission fulfill];
    }];

    NottiSubscription *received = [NottiNotifications addReceivedListener:^(NSDictionary *payload) {
        (void)payload;
    }];
    NottiSubscription *clicked = [NottiNotifications addClickedListener:^(NSDictionary *payload) {
        (void)payload;
    }];
    XCTAssertNotNil(received);
    XCTAssertNotNil(clicked);
    [received remove];
    [clicked remove];
    XCTAssertNil([NottiNotifications takeInitialClick]);

    [self waitForExpectationsWithTimeout:10 handler:nil];
}

// DEL-12: the five manual forwarding methods are callable from Objective-C. UNNotification and
// UNNotificationResponse have no public initializer, so the fixtures are allocated and filled by KVC.
// The shared runtime is used: while swizzling is active the calls are ignored (no network, no event).
- (UNNotification *)fixtureNotification {
    return [self fixtureNotificationWithUserInfo:@{
        @"aps": @{@"alert": @{@"title": @"Title fixture", @"body": @"Body fixture"}},
        @"notification_id": @"n-objc-fixture",
        @"delivery_id": @"d-objc-fixture"
    }];
}

- (UNNotification *)fixtureNotificationWithUserInfo:(NSDictionary *)userInfo {
    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    content.userInfo = userInfo;
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:@"req-objc-fixture"
                                                                          content:content
                                                                          trigger:nil];
    UNNotification *notification = [NSClassFromString(@"UNNotification") new];
    [notification setValue:request forKey:@"request"];
    [notification setValue:[NSDate date] forKey:@"date"];
    return notification;
}

- (void)testManualForwardingEntryPointsAreCallable {
    [NottiNotifications didRegisterForRemoteNotificationsWithDeviceToken:[NSData data]];
    [NottiNotifications didFailToRegisterForRemoteNotificationsWithError:
        [NSError errorWithDomain:@"fixture.apns" code:1 userInfo:nil]];
    UIBackgroundFetchResult result = [NottiNotifications didReceiveRemoteNotification:@{@"aps": @{@"content-available": @1}}];
    XCTAssertEqual(result, UIBackgroundFetchResultNoData);

    UNNotification *notification = [self fixtureNotification];
    UNNotificationPresentationOptions options = [NottiNotifications willPresentNotification:notification];
    XCTAssertEqual(options, UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList |
                            UNNotificationPresentationOptionSound | UNNotificationPresentationOptionBadge);

    UNNotificationResponse *response = [NSClassFromString(@"UNNotificationResponse") new];
    [response setValue:notification forKey:@"notification"];
    [response setValue:UNNotificationDefaultActionIdentifier forKey:@"actionIdentifier"];
    [NottiNotifications didReceiveNotificationResponse:response];
}

// A notification that is not a Notti push (no `aps`, no `notification_id`) gets no presentation options.
- (void)testManualWillPresentOfANonNottiNotificationReturnsNoOptions {
    UNNotification *local = [self fixtureNotificationWithUserInfo:@{@"custom": @"fixture"}];

    UNNotificationPresentationOptions options = [NottiNotifications willPresentNotification:local];

    XCTAssertEqual(options, (UNNotificationPresentationOptions)0);
}

@end
