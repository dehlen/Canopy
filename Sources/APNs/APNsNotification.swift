import LegibleError
import Foundation

private let release = APNs(production: true)
private let debug = APNs(production: false)

public enum APNsNotification {
    case silent([String: Any])
    case alert(body: String, title: String?, subtitle: String?, category: String?, threadId: String?, extra: [String: Any]?, id: String?, collapseId: String?)

    public init(body: String, title: String? = nil, subtitle: String? = nil, category: String? = nil, threadId: String? = nil, extra: [String: Any]? = nil, id: String? = nil, collapseId: String? = nil) {
        self = .alert(body: body, title: title, subtitle: subtitle, category: category, threadId: threadId, extra: extra, id: id, collapseId: collapseId)
    }

    public func send(to: [APNSConfiguration: [String]], errorHandler: @escaping (APNsError) -> Void = { print("error:", $0.legibleDescription) }) throws {
        let json = try JSONSerialization.data(withJSONObject: payload)
        for (conf, tokens) in to {
            let apns = conf.isProduction ? release : debug
            for token in tokens {
                apns.send(to: token, topic: conf.topic, json: json, id: id, collapseId: collapseId, errorHandler: errorHandler)
            }
        }
    }

    var payload: [String: Any] {
        switch self {
        case .silent(let extra):
            var payload = extra
            payload["aps"] = ["content-available": 1]
            return payload
        case .alert(let body, let title, let subtitle, let category, let threadId, let extra, _, _):
            var alert = ["body": String(body.prefix(3600))]  // 4K max size
            alert["title"] = title
            alert["subtitle"] = subtitle

            var aps: [String: Any] = ["alert": alert]
            aps["thread-id"] = threadId
            aps["category"] = category

            var payload: [String: Any] = extra ?? [:]
            payload["aps"] = aps

            return payload
        }
    }

    var id: String? {
        switch self {
        case .alert(_, _, _, _, _, _, let id, _):
            return id
        case .silent:
            return nil
        }
    }

    var collapseId: String? {
        switch self {
        case .alert(_, _, _, _, _, _, _, let id):
            return id
        case .silent:
            return nil
        }
    }
}
