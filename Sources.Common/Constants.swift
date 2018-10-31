import struct Foundation.URLComponents
import struct Foundation.CharacterSet
import struct Foundation.URL

public extension URLComponents {
    init(_ canopy: URL.Canopy) {
        self.init()
        scheme = "https"
        host = "canopy.codebasesaga.com"
        path = canopy.path
    }
}

public extension URL {
    enum Canopy {
        case redirect
        case token
        case grapnel
        case hook
        case subscribe
        case receipt
        case enroll
        case refreshReceipts

        public var path: String {
            switch self {
            case .redirect:
                return "/oauth"
            case .token:
                return "/token"
            case .grapnel:
                return "/github"
            case .hook:
                return "/hook"
            case .subscribe:
                return "/subscribe"
            case .receipt:
                return "/receipt"
            case .enroll:
                return "/enroll"
            case .refreshReceipts:
                return "/receipt/refresh"
            }
        }
    }

    init(_ canopy: Canopy) {
        self = URLComponents(canopy).url!
    }
}

public let clientId = "00f34fed06ffad73fe17"
