@import XCTest;
@import NottiSDK;

// API-13: every P1 capability is callable from Objective-C. These tests only use
// the public ObjC surface (no internal seam), so they run against the shared
// runtime and avoid anything that reaches the network: initialize is called with
// invalid values (ignored and logged without values), and profile calls made
// before initialize are either dropped or undone.

@interface NottiObjCTests : XCTestCase
@end

@implementation NottiObjCTests

- (void)tearDown {
    Notti.logLevel = NottiLogLevelError;
    [super tearDown];
}

- (void)testNottiEntryPointsAreCallable {
    // Invalid on purpose: empty appId is ignored by the facade (no network).
    [Notti initializeWithAppId:@"" clientKey:@"" baseUrl:nil];
    [Notti initializeWithAppId:@"" clientKey:@"" baseUrl:@"https://notti.example.invalid"];
    [Notti login:@"user-fixture"];   // dropped before initialize
    [Notti logout];
    (void)Notti.deviceId;            // nil or a persisted id
    [Notti setLocationSharingEnabled:NO];

    __block NSInteger deviceIdCalls = 0;
    NottiSubscription *subscription = [Notti addDeviceIdChangedListener:^(NSString *deviceId) {
        (void)deviceId;
        deviceIdCalls += 1;
    }];
    XCTAssertNotNil(subscription);
    [subscription remove];
    [subscription remove]; // idempotent
    XCTAssertEqual(deviceIdCalls, 0);
}

- (void)testLogLevelRoundTripsThroughTheObjCEnum {
    XCTAssertEqual(Notti.logLevel, NottiLogLevelError, @"default level");
    NSArray<NSNumber *> *levels = @[
        @(NottiLogLevelNone), @(NottiLogLevelError), @(NottiLogLevelWarn),
        @(NottiLogLevelInfo), @(NottiLogLevelDebug), @(NottiLogLevelVerbose)
    ];
    for (NSNumber *level in levels) {
        Notti.logLevel = (NottiLogLevel)level.integerValue;
        XCTAssertEqual(Notti.logLevel, (NottiLogLevel)level.integerValue);
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

@end
