// Moved verbatim from react-native-notti 52e4b55 ios/Tests/NottiNetworkObserverTests.swift
// (a private nested class there), so later tests (runtime) can share it.

import Network
@testable import NottiSDK

final class FakePathMonitor: NottiPathMonitoring {
    var pathUpdateHandler: ((NWPath.Status) -> Void)?
    private(set) var startCount = 0
    private(set) var cancelCount = 0
    func start(queue: DispatchQueue) { startCount += 1 }
    func cancel() { cancelCount += 1 }
}
