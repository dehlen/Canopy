public enum Event: String, CaseIterable, CustomStringConvertible {
    case ping
    case push
    case check_run
    case check_suite
    case commit_comment
    case create
    case delete
    case deployment
    case deployment_status
    case fork
    case gollum
    case issue_comment
    case issues
    case label
    case member
    case membership
    case milestone
    case organization
    case org_block
    case page_build
    case project_card
    case project_column
    case project
    case `public`
    case pull_request
    case pull_request_review
    case release
    case repository
    case repository_import
    case status
    case watch
    case pull_request_review_comment
    case team
    case team_add
    case repository_vulnerability_alert
    case marketplace_purchase

    public enum E: Error {
        case unimplemented(String)
        case ignoring
    }

    public var optionValue: Int {
        switch self {
        case .ping:
            return 1 << 0
        case .push:
            return 1 << 1
        case .check_run:
            return 1 << 2
        case .check_suite:
            return 1 << 3
        case .commit_comment:
            return 1 << 4
        case .create:
            return 1 << 5
        case .delete:
            return 1 << 6
        case .deployment:
            return 1 << 7
        case .deployment_status:
            return 1 << 8
        case .fork:
            return 1 << 9
        case .gollum:
            return 1 << 10
        case .issue_comment:
            return 1 << 11
        case .issues:
            return 1 << 12
        case .label:
            return 1 << 13
        case .member:
            return 1 << 14
        case .membership:
            return 1 << 15
        case .milestone:
            return 1 << 16
        case .organization:
            return 1 << 17
        case .org_block:
            return 1 << 18
        case .page_build:
            return 1 << 19
        case .project_card:
            return 1 << 20
        case .project_column:
            return 1 << 21
        case .project:
            return 1 << 22
        case .public:
            return 1 << 23
        case .pull_request:
            return 1 << 24
        case .pull_request_review:
            return 1 << 25
        case .release:
            return 1 << 26
        case .repository:
            return 1 << 27
        case .repository_import:
            return 1 << 28
        case .status:
            return 1 << 29
        case .watch:
            return 1 << 30
        case .pull_request_review_comment:
            return 1 << 31
        case .team:
            return 1 << 32
        case .team_add:
            return 1 << 33
        case .repository_vulnerability_alert:
            return 1 << 34
        case .marketplace_purchase:
            return 1 << 35
        }
    }

    public var description: String {
        switch self {
        case .org_block:
            return "Organization Block"
        case .watch:
            return "Star"
        case .gollum:
            return "Wiki"
        case .ping:
            return "Webhook Ping"
        default:
            return rawValue.decamelcased
        }
    }
}

public extension Sequence where Element == Event {
    var maskValue: Int {
        return reduce(0) { $0 + $1.optionValue }
    }
}

public extension Array where Element == Event {
    static var `default`: Set<Event> {
        var rv = Set(Event.allCases)
        rv.remove(.status)
        return rv
    }
}

private extension String {
    var decamelcased: String {
        return split(separator: "_").map(\.capitalized).joined(separator: " ")
    }
}

public extension Set where Element == Event {
    init(mask: Int) {
        self.init()
        for event in Event.allCases {
            if mask & event.optionValue == event.optionValue {
                insert(event)
            }
        }
    }
}

extension Set where Element == Enrollment {
    @inline(__always)
    func contains(_ repo: Repo) -> Bool {
        return contains(Enrollment(repoId: repo.id, eventMask: 0))
    }
}
