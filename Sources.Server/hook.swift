import Foundation
import PerfectHTTP

protocol Notificatable {
    var title: String? { get }
    var body: String? { get }
}

extension Notificatable {
    var body: String? { return nil }
}

struct PingEvent: Decodable, Notificatable {
    let hook: Hook
    let sender: Sender

    // which is set depends on Hook.type
    let organization: Sender?
    let repository: Repository?

    struct Hook: Decodable {
        let type: String
    }

    var title: String? {
        switch hook.type.lowercased() {
        case "organization":
            guard let login = organization?.login else { return nil }
            return "Subscribed to the \(login) organization"
        case "repository":
            guard let repo = repository?.full_name else { return nil }
            return "Subscribed to \(repo)"
        default:
            return nil
        }
    }
}

struct Sender: Decodable {
    let login: String
}
struct Repository: Decodable {
    let full_name: String
    let `private`: Bool
}
