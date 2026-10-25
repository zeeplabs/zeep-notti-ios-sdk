import Foundation

/// Outcome of one `eligible` request (RN `InAppEligibleResult`, 0.8.0). `rateLimited` carries the integer
/// `Retry-After`, unclamped, or nil. `unauthorized` (401) and `forbidden` (403) stay distinct so the engine
/// logs the right line. `terminal` is a 4xx that cannot succeed; `transient` a transport error, 408, 5xx or
/// an unparseable 2xx.
enum NottiInAppEligibleResult {
    case messages([NottiInAppMessage])
    case rateLimited(retryAfterSeconds: Int?)
    case unauthorized
    case forbidden
    case terminal(status: Int)
    case transient
}

/// Outcome of one events request (RN `InAppEventResult`, 0.8.0): `recorded` is any 2xx (201 new,
/// 200 duplicate), `drop` a 4xx that cannot succeed. The other cases mirror `NottiInAppEligibleResult`.
enum NottiInAppEventResult: Equatable {
    case recorded
    case drop
    case rateLimited(retryAfterSeconds: Int?)
    case unauthorized
    case forbidden
    case transient
}

/// Non-blocking client for the two In-App routes (design D5). One request per call, no retry and no wait:
/// `Retry-After`, backoff and give-up rules belong to the engine. The result mapping is RN
/// `NottiApiClient.swift:266-311` (0.8.0). Completions run on the session's delegate queue; callers hop
/// to their own queue. Nothing here logs: no token, id, URL or body can leak from this type (IAM-43).
final class NottiInAppApiClient {

    /// Same per-request timeout as the core client.
    static let requestTimeoutSeconds: TimeInterval = 15

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let session: URLSession
    private let baseUrl: String
    private let appId: String
    private let clientKey: String

    /// Nil when `baseUrl` is not usable (`NottiApiClient.validatedBaseUrl`).
    init?(session: URLSession = .shared, baseUrl: String, appId: String, clientKey: String) {
        guard let validated = NottiApiClient.validatedBaseUrl(baseUrl) else { return nil }
        self.session = session
        self.baseUrl = validated
        self.appId = appId
        self.clientKey = clientKey
    }

    /// `POST /v1/apps/{appId}/in-app-messages/eligible` with exactly `device_id` and `token` (IAM-02).
    func eligible(deviceId: String, token: String, completion: @escaping (NottiInAppEligibleResult) -> Void) {
        guard let url = url(tail: ["eligible"]) else {
            completion(.terminal(status: 0))
            return
        }
        send(url: url, body: ["device_id": deviceId, "token": token]) { status, data, retryAfter in
            completion(Self.eligibleResult(status: status, body: data, retryAfter: retryAfter))
        }
    }

    /// The `eligible` status table. `status` is -1 for a transport error.
    static func eligibleResult(status: Int, body: Data, retryAfter: String?) -> NottiInAppEligibleResult {
        switch status {
        case 200..<300:
            guard let messages = NottiInAppMessageParser.parse(body) else { return .transient }
            return .messages(messages)
        case 429: return .rateLimited(retryAfterSeconds: parseRetryAfter(retryAfter))
        case 401: return .unauthorized
        case 403: return .forbidden
        case 408: return .transient
        case 400..<500: return .terminal(status: status)
        default: return .transient
        }
    }

    /// `POST /v1/apps/{appId}/in-app-messages/{messageId}/events` (IAM-29). `button_id` only for `click`,
    /// `reason` only for `dismiss`: the server answers 422 to either elsewhere.
    func report(
        _ event: NottiInAppEventRecord,
        deviceId: String,
        token: String,
        completion: @escaping (NottiInAppEventResult) -> Void
    ) {
        guard let url = url(tail: [event.messageId, "events"]) else {
            completion(.drop)
            return
        }
        var body: [String: Any] = [
            "device_id": deviceId,
            "token": token,
            "event_id": event.eventId,
            "type": event.type,
            "occurred_at": Self.formatIsoUtc(event.occurredAtMs)
        ]
        if event.type == NottiInAppEventType.click, let buttonId = event.buttonId { body["button_id"] = buttonId }
        if event.type == NottiInAppEventType.dismiss, let reason = event.reason { body["reason"] = reason }
        send(url: url, body: body) { status, _, retryAfter in
            completion(Self.eventResult(status: status, retryAfter: retryAfter))
        }
    }

    /// The events status table (IAM-31). `status` is -1 for a transport error.
    static func eventResult(status: Int, retryAfter: String?) -> NottiInAppEventResult {
        switch status {
        case 200..<300: return .recorded
        case 429: return .rateLimited(retryAfterSeconds: parseRetryAfter(retryAfter))
        case 401: return .unauthorized
        case 403: return .forbidden
        case 408: return .transient
        case 400..<500: return .drop
        default: return .transient
        }
    }

    /// Integer seconds only: a sign, a fraction, an HTTP-date or blank is nil. Capped at `Int32.max`
    /// (RN `parseRetryAfter`, 0.8.0); never clamped otherwise.
    static func parseRetryAfter(_ raw: String?) -> Int? {
        guard
            let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty,
            value.utf8.allSatisfy({ $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") })
        else {
            return nil
        }
        return min(Int(value) ?? Int(Int32.max), Int(Int32.max))
    }

    /// `yyyy-MM-dd'T'HH:mm:ss.SSS'Z'` in UTC (RN `formatIsoUtc`).
    static func formatIsoUtc(_ epochMs: Int64) -> String {
        isoFormatter.string(from: Date(timeIntervalSince1970: Double(epochMs) / 1000))
    }

    /// Each segment is percent-encoded on its own, so an id carrying `/`, `?` or `#` stays one segment.
    private func url(tail: [String]) -> URL? {
        var segments: [String] = []
        for raw in [appId, "in-app-messages"] + tail {
            guard let encoded = NottiApiClient.percentEncodedPathComponent(raw) else { return nil }
            segments.append(encoded)
        }
        return URL(string: "\(baseUrl)/v1/apps/" + segments.joined(separator: "/"))
    }

    /// One request. `status` is -1 on a transport error or an unencodable body.
    private func send(url: URL, body: [String: Any], completion: @escaping (Int, Data, String?) -> Void) {
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            completion(-1, Data(), nil)
            return
        }
        var request = URLRequest(url: url, timeoutInterval: Self.requestTimeoutSeconds)
        request.httpMethod = "POST"
        request.setValue("Bearer \(clientKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        session.dataTask(with: request) { responseData, response, error in
            guard error == nil, let http = response as? HTTPURLResponse else {
                completion(-1, Data(), nil)
                return
            }
            completion(http.statusCode, responseData ?? Data(), http.value(forHTTPHeaderField: "Retry-After"))
        }.resume()
    }
}
