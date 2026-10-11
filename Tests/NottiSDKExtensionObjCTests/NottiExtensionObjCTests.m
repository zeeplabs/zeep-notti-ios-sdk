@import XCTest;
@import NottiSDKExtension;
@import UserNotifications;

// NSE-16: the two Notification Service Extension entry points are callable from Objective-C with their
// documented selectors. Only paths that start no request are used (no network, no live extension).

@interface NottiExtensionObjCTests : XCTestCase
@end

@implementation NottiExtensionObjCTests

- (void)testBothSelectorsAreCallableFromObjectiveC {
    XCTAssertTrue([NottiNotificationServiceExtension respondsToSelector:@selector(didReceive:withContentHandler:)]);
    XCTAssertTrue([NottiNotificationServiceExtension
        respondsToSelector:@selector(serviceExtensionTimeWillExpireFor:contentHandler:)]);
}

- (void)testExpiryWithNilContentIsANoOp {
    __block NSInteger calls = 0;
    [NottiNotificationServiceExtension serviceExtensionTimeWillExpireFor:nil
                                                          contentHandler:^(UNNotificationContent *content) {
        (void)content;
        calls += 1;
    }];
    XCTAssertEqual(calls, 0);
}

- (void)testARequestWithoutAnImageUrlCallsTheHandlerOnceWithTheOriginalContent {
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = @"fixture title";
    content.body = @"fixture body";
    content.userInfo = @{@"aps": @{@"mutable-content": @1}, @"delivery_id": @"delivery-fixture"};
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:@"fixture-request"
                                                                          content:content
                                                                          trigger:nil];
    __block NSInteger calls = 0;
    __block UNNotificationContent *delivered = nil;

    [NottiNotificationServiceExtension didReceive:request withContentHandler:^(UNNotificationContent *result) {
        calls += 1;
        delivered = result;
    }];

    XCTAssertEqual(calls, 1);
    XCTAssertEqualObjects(delivered.title, @"fixture title");
    XCTAssertEqualObjects(delivered.body, @"fixture body");
    XCTAssertEqual(delivered.attachments.count, 0u);
    XCTAssertEqualObjects(delivered.userInfo, request.content.userInfo);
}

@end
