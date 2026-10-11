import Foundation

/// Why a rich media download ended without an attachment.
///
/// `code` is the only text that reaches a log line. It is a fixed string, plus `domain#code` for the cases
/// that carry an error. It never holds a URL, host, query, title or body (NSE-13), and the error cases take
/// the `NSError` domain and code only, never a message.
enum NottiRichMediaDropReason: Equatable {
    case invalidURL
    case redirectNotHTTPS
    case httpStatus(Int)
    case oversize
    case noFile
    case deadline
    case expired
    case transport(domain: String, code: Int)
    case moveFailed(domain: String, code: Int)
    case attachmentRejected(domain: String, code: Int)

    var code: String {
        switch self {
        case .invalidURL: return "invalid_url"
        case .redirectNotHTTPS: return "redirect_not_https"
        case .httpStatus(let status): return "http_\(status)"
        case .oversize: return "oversize"
        case .noFile: return "no_file"
        case .deadline: return "deadline"
        case .expired: return "expired"
        case .transport(let domain, let code): return "transport:\(domain)#\(code)"
        case .moveFailed(let domain, let code): return "move_failed:\(domain)#\(code)"
        case .attachmentRejected(let domain, let code): return "attachment_rejected:\(domain)#\(code)"
        }
    }

    static func transport(_ error: Error) -> NottiRichMediaDropReason {
        let nsError = error as NSError
        return .transport(domain: nsError.domain, code: nsError.code)
    }

    static func moveFailed(_ error: Error) -> NottiRichMediaDropReason {
        let nsError = error as NSError
        return .moveFailed(domain: nsError.domain, code: nsError.code)
    }

    static func attachmentRejected(_ error: Error) -> NottiRichMediaDropReason {
        let nsError = error as NSError
        return .attachmentRejected(domain: nsError.domain, code: nsError.code)
    }
}
