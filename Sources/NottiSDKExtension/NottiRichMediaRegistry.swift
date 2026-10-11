import Foundation
#if canImport(NottiShared)
import NottiShared
#endif

/// The most recent rich media jobs, so `serviceExtensionTimeWillExpire` can find the job of its notification.
///
/// Finished jobs stay (bounded) so an expiry that races a just-finished job still finds it and the gate
/// refuses a second handler call. A finished job holds no session, task or file.
final class NottiRichMediaRegistry {
    static let capacity = 16

    private let lock = NSLock()
    private var recent: [NottiRichMediaJob] = []

    func add(_ job: NottiRichMediaJob) {
        lock.lock(); defer { lock.unlock() }
        recent.append(job)
        if recent.count > Self.capacity { recent.removeFirst(recent.count - Self.capacity) }
    }

    /// Jobs whose notification `userInfo` equals `userInfo`, or that share a non-empty `delivery_id` with it
    /// (a host may have changed another key of its best-attempt copy).
    func jobs(matching userInfo: [AnyHashable: Any]) -> [NottiRichMediaJob] {
        let wanted = userInfo as NSDictionary
        let wantedId = Self.deliveryId(userInfo[NottiPayloadKeys.deliveryId])
        lock.lock()
        let snapshot = recent
        lock.unlock()
        return snapshot.filter { job in
            let jobId = Self.deliveryId(job.userInfo[NottiPayloadKeys.deliveryId])
            if let wantedId, let jobId { return wantedId == jobId }
            return job.userInfo.isEqual(wanted)
        }
    }

    private static func deliveryId(_ value: Any?) -> String? {
        guard let id = value as? String, !id.isEmpty else { return nil }
        return id
    }
}
