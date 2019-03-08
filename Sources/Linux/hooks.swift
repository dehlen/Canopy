import PerfectHTTP
import Foundation
import Roots

enum Context {
    case organization(Organization, admin: User)
    case repository(Repository)
}

protocol Notificatable {
    var url: URL? { get }
    var body: String { get }
    var title: String? { get }
    var context: Context { get }
    var subtitle: String? { get }
    var collapseId: String? { get }
    var threadingId: String { get }
    var shouldIgnore: Bool { get }
    var senderUid: Int { get }
    var saveNamePrefix: String? { get }
}

protocol HasSender {
    var sender: User { get }
}
extension HasSender {
    var senderUid: Int {
        return sender.id
    }
}

extension Notificatable {
    var url: URL? { return nil }

    var title: String? {
        switch context {
        case .repository(let repo):
            return repo.full_name
        case .organization(let org, _):
            return "orgs/\(org.login)"
        }
    }

    var threadingId: String {
        switch context {
        case .organization(let org, _):
            return "orgs/\(org.id)"
        case .repository(let repo):
            return "repo/\(repo.id)"
        }
    }

    var shouldIgnore: Bool {
        return false
    }

    var collapseId: String? {
        return nil
    }

    var subtitle: String? {
        return nil
    }

    var saveNamePrefix: String? {
        if senderUid == 58962 {
            return "mxcl"
        } else {
            return nil
        }
    }
}

// https://developer.github.com/v3/activity/events/types/

struct PingEvent: Codable, Notificatable, HasSender {
    let hook: Hook
    let sender: User
    let context: Context

    init(from decoder: Decoder) throws {

        enum E: Error {
            case invalidPingHookType(String)
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        hook = try container.decode(Hook.self, forKey: .hook)
        sender = try container.decode(User.self, forKey: .sender)

        if hook.type == "Organization" {
            let org = try container.decode(Organization.self, forKey: .organization)
            context = .organization(org, admin: sender)
        } else if hook.type == "Repository" {
            let repo = try container.decode(Repository.self, forKey: .repository)
            context = .repository(repo)
        } else {
            throw E.invalidPingHookType(hook.type)
        }
    }

    func encode(to encoder: Encoder) throws {
        // required for Perfect (due to poor API design)
        fatalError()
    }

    enum CodingKeys: String, CodingKey {
        case organization
        case repository
        case hook
        case sender
    }

    struct Hook: Codable {
        let type: String
        let id: Int
    }

    var body: String {
        switch context {
        case .organization(let org, _):
            return "Webhook added to orgs/\(org.login)"
        case .repository(let repo):
            return "Webhook added to \(repo.full_name)"
        }
    }
}

struct CheckRunEvent: Codable, Notificatable, HasSender {
    let action: Action
    let check_run: CheckRun
    let repository: Repository
    let sender: User

    enum Action: String, Codable {
        case created, rerequested, completed, requested_action
    }

    struct CheckRun: Codable {
        let url: URL
        let status: Status

        enum Status: String, Codable, CustomStringConvertible {
            case queued, in_progress, completed

            var description: String {
                switch self {
                case .queued, .completed:
                    return rawValue
                case .in_progress:
                    return "in progress"
                }
            }
        }
    }

    var subtitle: String? {
        return "Check run \(check_run.status)"
    }

    var body: String {
        switch action {
        case .created, .completed:
            return "\(sender.login) \(action) the check"
        case .rerequested:
            return "\(sender.login) re‑requested the check"
        case .requested_action:
            return "\(sender.login) requested action"
        }
    }

    var url: URL? {
        return check_run.url
    }

    var context: Context {
        return .repository(repository)
    }
}

struct CheckSuiteEvent: Codable, Notificatable, HasSender {
    let action: Action
    let check_suite: CheckSuite
    let repository: Repository
    let sender: User

    enum Action: String, Codable {
        case completed, requested, rerequested
    }

    struct CheckSuite: Codable {
        let url: URL
        let status: Status

        enum Status: String, Codable, CustomStringConvertible {
            case requested, in_progress, completed

            var description: String {
                switch self {
                case .requested, .completed:
                    return rawValue
                case .in_progress:
                    return "in progress"
                }
            }
        }
    }

    var subtitle: String? {
        return "Check suite \(check_suite.status)"
    }

    var body: String {
        return "\(sender) \(action) the check"
    }

    var url: URL? {
        return check_suite.url
    }

    var context: Context {
        return .repository(repository)
    }
}

// https://developer.github.com/v3/activity/events/types/#commitcommentevent
struct CommitCommentEvent: Codable, Notificatable, HasSender {
    let action: String
    let comment: Comment
    let repository: Repository
    let sender: User

    var subtitle: String? {
        return "\(comment.user.login) commented on a commit"
    }
    var body: String {
        return comment.body
    }
    var url: URL? {
        return comment.html_url
    }
    var context: Context {
        return .repository(repository)
    }
}

// https://developer.github.com/v3/activity/events/types/#createevent
struct CreateEvent: Codable, Notificatable, HasSender {
    let repository: Repository
    let sender: User
    let ref_type: RefType
    let ref: String?

    enum RefType: String, Codable {
        case repository
        case branch
        case tag
    }

    var body: String {
        switch ref_type {
        case .branch:
            guard let ref = ref else { fallthrough }
            return "\(sender.login) created the “\(ref)” branch"
        case .tag:
            guard let ref = ref else { fallthrough }
            return "\(sender.login) tagged “\(ref)”"
        case .repository:
            return "\(sender.login) created a new \(ref_type)"
        }
    }

    var url: URL? {
        return repository.html_url
    }

    var context: Context {
        return .repository(repository)
    }
}

struct DeleteEvent: Codable, Notificatable, HasSender {
    let repository: Repository
    let sender: User
    let ref_type: RefType
    let ref: String

    enum RefType: String, Codable {
        case branch, tag
    }

    var body: String {
        return "\(sender.login) deleted the \(ref_type) “\(ref)”"
    }
    var url: URL? {
        return repository.html_url  // but… will 404
    }

    var context: Context {
        return .repository(repository)
    }
}

struct DeploymentEvent: Codable, Notificatable, HasSender {
    let repository: Repository
    let deployment: Deployment
    let sender: User

    var body: String {
        return "\(sender.login) deployed to \(deployment.environment)"
    }
    var url: URL? {
        return deployment.url
    }

    var context: Context {
        return .repository(repository)
    }
}

struct DeploymentStatusEvent: Codable, Notificatable, HasSender {
    let deployment_status: DeploymentStatus
    let deployment: Deployment
    let repository: Repository
    let sender: User

    struct DeploymentStatus: Codable {
        let url: URL
        let status: String?
        let description: String?
    }

    var body: String {
        var rv = "\(sender.login) deployed to \(deployment.environment)"
        if let status = deployment_status.status {
            rv += " with status: \(status)"
        }
        return rv
    }
    var url: URL? {
        return deployment_status.url
    }

    var context: Context {
        return .repository(repository)
    }
}

struct ForkEvent: Codable, Notificatable, HasSender {
    let forkee: Repository
    let repository: Repository
    let sender: User

    var body: String {
        return "\(sender.login) forked \(repository.full_name)"
    }
    var url: URL? {
        return forkee.html_url
    }

    var context: Context {
        return .repository(repository)
    }
}

struct GollumEvent: Codable, Notificatable, HasSender {
    let pages: [Page]
    let repository: Repository
    let sender: User

    struct Page: Codable {
        let page_name: String
        let title: String
        let summary: String?
        let action: String
        let html_url: URL
    }

    var body: String {
        return "\(sender.login) triggered \(pages.count) wiki events"
    }
    var url: URL? {
        return pages.first?.html_url
    }

    var context: Context {
        return .repository(repository)
    }
}

struct IssueCommentEvent: Codable, Notificatable, HasSender {
    let action: Action
    let issue: Issue
    let comment: Comment
    let repository: Repository
    let sender: User

    enum Action: String, Codable {
        case created, edited, deleted
    }

    var title: String {
        return "\(repository.full_name)#\(issue.number)"
    }

    var subtitle: String? {
        switch action {
        case .created:
            return "\(sender.login) commented"
        case .deleted, .edited:
            return "\(sender.login) \(action) a comment"
        }

    }

    var body: String {
        return comment.body
    }

    var url: URL? {
        return comment.html_url
    }

    var context: Context {
        return .repository(repository)
    }

    var saveNamePrefix: String? {
        if senderUid == 58962 {
            return "mxcl-\(action.rawValue)"
        } else {
            return nil
        }
    }

    var collapseId: String? {
        // collapse all creation/edits/deletes so the latest event is the only one the user sees
        return "\(repository.full_name)/issues/comment/\(comment.id)"
    }
}

struct IssuesEvent: Codable, Notificatable, HasSender {
    let action: Action
    let issue: Issue
    let repository: Repository
    let sender: User
    let changes: Changes?

    enum Action: String, Codable {
        case assigned, unassigned, labeled, unlabeled, opened, edited, milestoned, demilestoned, closed, reopened, transferred, deleted
    }

    struct Changes: Codable {
        let title: Change?
        //let body: Change?

        struct Change: Codable {
            let from: String
        }
    }

    var title: String? {
        return "\(repository.full_name)#\(issue.number)"
    }

    var body: String {
        if changes?.title == nil {
            return "\(action.rawValue.capitalized) by \(sender.login)"
        } else {
            return "Renamed to “\(issue.title)” by \(sender.login)"
        }
    }
    var url: URL? {
        return issue.html_url
    }

    var context: Context {
        return .repository(repository)
    }

    var saveNamePrefix: String? {
        if senderUid == 58962 {
            return "mxcl-\(action.rawValue)"
        } else {
            return nil
        }
    }
}

struct LabelEvent: Codable, Notificatable, HasSender {
    let action: Action
    let label: Label
    let repository: Repository
    let sender: User

    struct Label: Codable {
        let name: String
        let url: URL
    }

    enum Action: String, Codable {
        case created, edited, deleted
    }

    var subtitle: String? {
        return "Label \(action) by \(sender)"
    }

    var body: String {
        return label.name
    }

    var url: URL? {
        return label.url
    }

    var context: Context {
        return .repository(repository)
    }
}

struct MemberEvent: Codable, Notificatable, HasSender {
    let action: Action
    let member: User
    let repository: Repository
    let sender: User

    enum Action: String, Codable {
        case edited, added, removed, deleted // github say it is deleted, but it seems to be removed
    }

    var body: String {
        return "\(sender.login) \(action) membership for \(member.login)"
    }
    var url: URL? {
        return repository.contributors_url
    }

    var context: Context {
        return .repository(repository)
    }
}

struct MembershipEvent: Codable, Notificatable, HasSender {
    let action: Action
    let scope: Scope
    let sender: User
    let organization: Organization
    let team: Team
    let member: User

    enum Action: String, Codable {
        case added, removed
    }
    enum Scope: String, Codable {
        case team
        case organization
    }

    struct Team: Codable {
        let name: String
        let url: URL
    }

    var body: String {
        return "\(sender.login) \(action) \(member.login) to the \(team.name) team"
    }
    var url: URL? {
        return team.url
    }

    var context: Context {
        return .organization(organization, admin: sender)
    }
}

struct MilestoneEvent: Codable, Notificatable, HasSender {
    let action: Action
    let sender: User
    let repository: Repository
    let milestone: Milestone

    enum Action: String, Codable {
        case created, closed, opened, edited, deleted
    }

    struct Milestone: Codable {
        let html_url: URL
        let title: String
        let description: String?
    }

    var body: String {
        return "\(sender.login) \(action) a milestone: \(milestone.title)"
    }
    var url: URL? {
        return milestone.html_url
    }

    var context: Context {
        return .repository(repository)
    }
}

struct OrganizationEvent: Codable, Notificatable, HasSender {  //TODO half-arsed
    let action: Action
    let organization: Organization
    let sender: User

    enum Action: CustomStringConvertible {
        case added(User)
        case removed(User)
        case invited(role: String, User)

        var description: String {
            switch self {
            case .added:
                return "added"
            case .removed:
                return "removed"
            case .invited:
                return "invited"
            }
        }
    }

    var body: String {
        switch action {
        case .removed(let user), .added(let user):
            return "\(sender.login) \(action) \(user.login)"
        case .invited(let role, let user):
            return "\(sender.login) invited \(user.login) (\(role))"
        }
    }

    var url: URL {
        switch action {
        case .added(let user), .removed(let user), .invited(_, let user):
            return user.html_url
        }
    }

    enum CodingKeys: String, CodingKey {
        case action, sender, user, invitation, membership, organization
    }

    var context: Context {
        return .organization(organization, admin: sender)
    }

    init(from decoder: Decoder) throws {
        struct Membership: Codable {
            let user: User
        }
        struct Invitation: Codable {
            let role: String
            let login: String
            let inviter: User
        }
        enum RawAction: String, Codable {
            case member_added, member_removed, member_invited
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawAction = try container.decode(RawAction.self, forKey: .action)
        sender = try container.decode(User.self, forKey: .sender)
        organization = try container.decode(Organization.self, forKey: .organization)

        switch rawAction {
        case .member_added:
            let membership = try container.decode(Membership.self, forKey: .membership)
            action = .added(membership.user)
        case .member_removed:
            let membership = try container.decode(Membership.self, forKey: .membership)
            action = .removed(membership.user)
        case .member_invited:
            let foo = try container.decode(Invitation.self, forKey: .invitation)
            let bar = try container.decode(User.self, forKey: .user)
            action = .invited(role: foo.role, bar)
        }
    }

    func encode(to encoder: Encoder) throws {
        // required for Perfect (due to poor API design)
        fatalError()
    }
}

struct OrgBlockEvent: Codable, Notificatable, HasSender {  //TODO half-arsed
    let action: Action
    let blocked_user: User
    let organization: Organization
    let sender: User

    enum Action: String, Codable {
        case blocked, unblocked
    }

    var body: String {
        return "\(sender.login) \(action) \(blocked_user.login)"
    }

    var context: Context {
        return .organization(organization, admin: sender)
    }
}

struct PageBuildEvent: Codable, Notificatable, HasSender {
    let build: Build
    let repository: Repository
    let sender: User

    struct Build: Codable {
        let url: URL
        let status: String
        let error: Error?

        struct Error: Codable {
            let message: String?
        }
    }

    var body: String {
        return "GitHub Pages build complete: \(build.status)"
    }
    var url: URL? {
        return build.url
    }

    var context: Context {
        return .repository(repository)
    }
}

struct ProjectCardEvent: Codable, Notificatable, HasSender {
    let action: Action
    let project_card: ProjectCard
    let context: Context
    let sender: User

    enum Action: String, Codable {
        case created, edited, converted, moved, deleted
    }

    struct ProjectCard: Codable {
        let note: String?
    }

    enum CodingKeys: String, CodingKey {
        case action
        case project_card
        case repository
        case organization
        case sender
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(Action.self, forKey: .action)
        sender = try container.decode(User.self, forKey: .sender)
        project_card = try container.decode(ProjectCard.self, forKey: .project_card)

        enum E: Error {
            case missingContext
        }

        if container.contains(.repository) {
            context = .repository(try container.decode(Repository.self, forKey: .repository))
        } else if container.contains(.organization) {
            context = .organization(try container.decode(Organization.self, forKey: .organization), admin: sender)
        } else {
            throw E.missingContext
        }
    }

    func encode(to encoder: Encoder) throws {
        // required for Perfect (due to poor API design)
        fatalError()
    }

    var body: String {
        if let name = project_card.note {
            return "\(sender.login) \(action) the “\(name)” project card"
        } else {
            return "\(sender.login) \(action) a project card"
        }
    }

    var url: URL? {
        switch context {
        case .organization(let org, _):
            return URL(string: "https://github.com/orgs/\(org.login)/projects")
        case .repository(let repo):
            // https://github.com/orgs/codebasesaga/projects/1#card-10299301
            return repo.html_url.appendingPathComponent("projects")
        }
    }
}

struct ProjectColumnEvent: Codable, Notificatable, HasSender {
    let action: Action
    let project_column: ProjectColumn
    let sender: User
    let context: Context

    enum Action: String, Codable {
        case created, edited, moved, deleted
    }

    struct ProjectColumn: Codable {
        let name: String
    }

    enum CodingKeys: String, CodingKey {
        case action
        case project_column
        case repository
        case organization
        case sender
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(Action.self, forKey: .action)
        sender = try container.decode(User.self, forKey: .sender)
        project_column = try container.decode(ProjectColumn.self, forKey: .project_column)

        enum E: Error {
            case missingContext
        }

        if container.contains(.repository) {
            context = .repository(try container.decode(Repository.self, forKey: .repository))
        } else if container.contains(.organization) {
            context = .organization(try container.decode(Organization.self, forKey: .organization), admin: sender)
        } else {
            throw E.missingContext
        }
    }

    func encode(to encoder: Encoder) throws {
        // required for Perfect (due to poor API design)
        fatalError()
    }

    var body: String {
        return "\(sender.login) \(action) the “\(project_column.name)” project column"
    }

    var url: URL? {
        //FIXME payload doesn't contain project id :(
        // https://github.com/orgs/codebasesaga/projects/1#column-2827834
        switch context {
        case .organization(let org, _):
            return URL(string: "https://github.com/orgs/\(org.login)/projects")
        case .repository(let repo):
            return repo.html_url.appendingPathComponent("projects")
        }
    }
}

struct ProjectEvent: Codable, Notificatable, HasSender {
    let action: Action
    let sender: User
    let context: Context
    let project: Project

    enum CodingKeys: String, CodingKey {
        case action
        case sender
        case repository
        case organization
        case project
    }

    enum Action: String, Decodable {
        case created, edited, closed, reopened, deleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(Action.self, forKey: .action)
        sender = try container.decode(User.self, forKey: .sender)
        project = try container.decode(Project.self, forKey: .project)

        enum E: Error {
            case missingContext
        }

        if container.contains(.repository) {
            context = .repository(try container.decode(Repository.self, forKey: .repository))
        } else if container.contains(.organization) {
            context = .organization(try container.decode(Organization.self, forKey: .organization), admin: sender)
        } else {
            throw E.missingContext
        }
    }

    func encode(to encoder: Encoder) throws {
        // required for Perfect (due to poor API design)
        fatalError()
    }

    struct Project: Codable {
        let html_url: URL
        let name: String
    }

    var body: String {
        return "\(sender.login) \(action) the project \(project.name)"
    }
    var url: URL? {
        return project.html_url
    }
}

struct PublicEvent: Codable, Notificatable, HasSender {
    let repository: Repository
    let sender: User

    var body: String {
        return "\(repository.full_name) was open sourced by \(sender.login)"
    }
    var url: URL? {
        return repository.html_url
    }
    var context: Context {
        return .repository(repository)
    }
}

struct PullRequestReviewCommentEvent: Codable, Notificatable, HasSender {
    let action: Action
    let comment: Comment
    let pull_request: PullRequest
    let repository: Repository
    let sender: User

    enum Action: String, Codable {
        case created, edited, deleted
    }

    var title: String? {
        return "\(repository.full_name)#\(pull_request.number) Review"
    }
    var subtitle: String? {
        return "\(sender.login) \(action) a comment"
    }
    var body: String {
        return comment.body
    }
    var url: URL? {
        return comment.html_url
    }
    var context: Context {
        return .repository(repository)
    }
}

struct PushEvent: Codable, Notificatable, HasSender {
    let repository: Repository
    let pusher: Pusher
    let compare: String // is actually URL, but GitHub are not URL-encoding the ^ character so URL.init fails
    let forced: Bool
    let distinct_size: Int?
    let commits: [Commit]
    let after: String
    let ref: String
    let sender: User

    struct Commit: Codable {
        let message: String
    }

    struct Pusher: Codable {
        let name: String
    }

    var size: Int {
        return distinct_size ?? self.commits.count
    }

    var reff: String {
        if ref.hasPrefix("/refs/heads/") {
            return String(ref.dropFirst(12))
        } else {
            return ref
        }
    }

    var body: String {
        let force = forced ? "force‑" : ""
        if size <= 0 {
            return "\(pusher.name) \(force)pushed to \(reff)"
        } else {
            let commits = size == 1
                ? "1 commit"
                : "\(size) commits"
            return "\(commits) \(force)pushed to \(reff) by \(pusher.name)"
        }
    }

    var url: URL? {
        // THANKS GITHUB YOU JERKS
        return URL(string: compare.replacingOccurrences(of: "^", with: "%5E"))
    }

    var context: Context {
        return .repository(repository)
    }

    var shouldIgnore: Bool {
        // indicates the push events directly after the merge event
        // and it is uninteresting to the user
        return size == 0 && after == "0000000000000000000000000000000000000000"
    }
}

// https://developer.github.com/v3/activity/events/types/#pullrequestevent
struct PullRequestEvent: Codable, Notificatable, HasSender {
    let action: Action
    let number: Int
    let pull_request: PullRequest
    let repository: Repository
    let sender: User
    let labels: [String]?

    enum Action: String, Codable {
        case assigned, unassigned, review_requested, review_request_removed, labeled, unlabeled, opened, edited, closed, reopened, synchronize
    }

    var title: String? {
        return "\(repository.full_name)#\(number)"
    }

    var subtitle: String? {
        return pull_request.title
    }

    var body: String {
        switch action {
        case .closed:
            if let merged = pull_request.merged, merged {
                return "Merged by \(sender.login)"
            } else {
                return "Closed by \(sender.login)"
            }
        case .synchronize:
            return "Synchronized by \(sender.login)"
        case .review_requested:
            return "Review requested by \(sender.login)"
        case .review_request_removed:
            return "Review request removed by \(sender.login)"
        case .labeled:
            let labels = self.labels ?? []
            return "\(sender.login) labeled \(labels.joined(separator: ", "))"
        default:
            return "\(action.rawValue.capitalized) by \(sender.login)"
        }
    }

    var url: URL? {
        return pull_request.html_url
    }

    var context: Context {
        return .repository(repository)
    }

    var shouldIgnore: Bool {
        return action == .synchronize
    }
}

// https://developer.github.com/v3/activity/events/types/#pullrequestreviewevent
struct PullRequestReviewEvent: Codable, Notificatable, HasSender {
    let action: Action
    let pull_request: PullRequest
    let review: Review
    let sender: User
    let repository: Repository

    enum Action: String, Codable {
        case submitted, edited, dismissed
    }

    struct Review: Codable {
        let user: User
        let state: State
        let html_url: URL

        enum State: String, Codable {
            case pending, changes_requested, approved, dismissed, commented
        }
    }

    var title: String? {
        return "\(repository.full_name)#\(pull_request.number) Review"
    }

    var body: String {
        let review_state = review.state.rawValue.replacingOccurrences(of: "_", with: " ")
        if review_state == "commented" {
            switch action {
            case .submitted:
                return "\(review.user.login) added a comment"
            case .edited, .dismissed:
                return "Comment \(action) by \(review.user.login)"
            }
        } else {
            return "\(action.rawValue.capitalized) \(review_state) by \(review.user.login)"
        }
    }
    var url: URL? {
        return review.html_url
    }

    var context: Context {
        return .repository(repository)
    }
}

struct ReleaseEvent: Codable, Notificatable, HasSender {
    let release: Release
    let sender: User
    let repository: Repository

    var body: String {
        if let name = release.name?.chuzzled() ?? release.tag_name.chuzzled() {
            //                      ^^ GitHub serve "" if empty (LAME)
            return "\(sender.login) released \(name)"
        } else {
            return "\(sender.login) published a release"
        }
    }
    var url: URL? {
        return release.html_url
    }
    var context: Context {
        return .repository(repository)
    }

    struct Release: Codable {
        let html_url: URL
        let tag_name: String
        let name: String?
    }
}

struct RepositoryEvent: Codable, Notificatable, HasSender {
    let action: Action
    let repository: Repository
    let sender: User

    enum Action: String, Codable {
        case created, deleted
        case archived, unarchived, publicized, privatized  //orgs only
    }

    var body: String {
        return "\(sender.login) \(action) \(repository.full_name)"
    }

    var context: Context {
        return .repository(repository)
    }

    var url: URL? {
        return repository.html_url
    }
}

struct RepositoryImportEvent: Codable, Notificatable, HasSender {
    let status: Status
    let repository: Repository
    let sender: User

    enum Status: String, Codable {
        case success, failure, cancelled
    }

    var body: String {
        switch status {
        case .success:
            return "Repository imported successfully"
        case .failure:
            return "Repository import failed"
        case .cancelled:
            return "Repository import was cancelled"
        }
    }

    var context: Context {
        return .repository(repository)
    }

    var url: URL? {
        return repository.html_url
    }
}

struct RepositoryVulnerabilityEvent: Codable, Notificatable, HasSender {
    let action: Action
    let alert: Alert
    let sender: User
    let repository: Repository

    struct Alert: Codable {
        let affected_package_name: String  // typically `merge`
        let external_reference: URL
        let external_identifier: String

        let dismiss_reason: String? // if action is dismiss
        let dismisser: User?
    }

    enum Action: String, Codable {
        case create, dismiss, resolve
    }

    var subtitle: String? {
        return "Vulnerability alert"
    }

    var body: String {
        switch action {
        case .create:
            return alert.external_identifier
        case .dismiss:
            let user = alert.dismisser?.login ?? "unknown"
            let reason = alert.dismiss_reason ?? "unknown"
            return "Dismissed by \(user) because “\(reason)”"
        case .resolve:
            return "Resolved by \(sender.login)"
        }
    }

    var url: URL {
        return alert.external_reference
    }

    var context: Context {
        return .repository(repository)
    }

    var saveNamePrefix: String? {
        if repository.private {
            return nil
        } else if alert.affected_package_name != "merge" || action == .resolve {
            return "unimplemented-\(alert.affected_package_name)-"
        } else {
            return nil
        }
    }
}

struct StatusEvent: Codable, Notificatable, HasSender {
    let name: String
    let state: String
    let sender: User
    let description: String?
    let repository: Repository
    let target_url: String?  // not always a valid URL (thanks GitHub)

    var subtitle: String? {
        if description == nil {
            return nil
        } else {
            return state
        }
    }

    var body: String {
        return description ?? state.capitalized
    }

    var url: URL? {
        return target_url.flatMap(URL.init)
    }

    var context: Context {
        return .repository(repository)
    }
}

struct TeamEvent: Codable, Notificatable, HasSender {
    let action: Action
    let organization: Organization
    let sender: User
    let team: Team

    struct Team: Codable {
        let name: String
    }

    enum Action: String, Codable {
        case created, deleted, edited, added_to_repository, removed_from_repository
    }

    var context: Context {
        return .organization(organization, admin: sender)
    }

    var title: String? {
        switch action {
        case .created:
            return "/orgs/\(organization.login)"
        default:
            return "/orgs/\(organization.login)/\(team.name)"
        }
    }

    var body: String {
        switch action {
        case .created:
            return "\(sender.login) created a new team: \(team.name)"
        case .edited, .deleted:
            return "\(sender.login) \(action) this team"
        case .added_to_repository, .removed_from_repository:
            return "\(sender.login) altered the member repositories for this team"
        }
    }
}

struct TeamAddEvent: Codable, Notificatable, HasSender {
    let repository: Repository
    let organization: Organization
    let sender: User
    let team: Team

    struct Team: Codable {
        let name: String
    }

    var title: String {
        return repository.full_name
    }

    var body: String {
        return "\(sender.login) added this repository to the team: \(team.name)"
    }

    var context: Context {
        return .organization(organization, admin: sender)
    }
}

// Actually: stars
struct WatchEvent: Codable, Notificatable, HasSender {
    let action: Action
    let sender: User
    let repository: Repository

    enum Action: String, Codable {
        case started
    }

    var subtitle: String? {
        return "\(repository.stargazers_count) stars"
    }

    var body: String {
        return "\(sender.login) starred \(repository.full_name)"
    }
    var url: URL? {
        return repository.html_url
    }

    var context: Context {
        return .repository(repository)
    }

    var collapseId: String? {
        return repository.full_name + "/stars"
    }
}

//struct MarketplacePurchaseEvent: Notificatable, HasSender {
//    let action: Action
//    let sender: User
//    let marketplace_purchase: MarketplacePurchase
//
//    enum Action: String, Codable {
//        case purchased, cancelled, pending_change, pending_change_cancelled, changed
//    }
//
//    struct MarketplacePurchase {
//        let account: Account
//        let plan: Plan
//
//        struct Plan {
//            let name: String
//        }
//        struct Account {
//            let type: Type_
//            let login: String
//
//            enum Type_: String, Codable {
//                case organization = "Organization"
//                case user = "User"
//            }
//        }
//    }
//
//    var body: String {
//        switch action {
//
//        }
//    }
//
//    var shouldIgnore: Bool {
//        // not sure how this can happen since there are no user-webhooks
//        return marketplace_purchase.account.type == .user
//    }
//
//    var context: Context {
//        switch marketplace_purchase.account.type {
//        case .organization:
//            return .organization(marketplace_purchase.account.login, admin: sender)
//        case .user:
//            fatalError()
//        }
//    }
//}


// types

struct User: Codable, CustomStringConvertible {
    let id: Int
    let login: String
    let html_url: URL

    var description: String {
        return login
    }
}

struct Organization: Codable {
    let id: Int
    let login: String
}

struct Repository: Codable {
    let id: Int
    let full_name: String
    let `private`: Bool
    let html_url: URL
    let contributors_url: URL
    let name: String
    let owner: User
    let stargazers_count: Int //TODO only really needed in one place
}

struct Deployment: Codable {
    let url: URL  // is api URL and not “html_url”
    let description: String?
    let environment: String
}

struct Installation: Codable {
    let html_url: URL
    let app_id: Int
}

struct Issue: Codable {
    let html_url: URL
    let number: Int
    let title: String
}

struct Comment: Codable {
    let html_url: URL
    let body: String
    let user: User
    let id: Int
}

struct PullRequest: Codable {
    let html_url: URL
    let state: String
    let title: String
    let body: String?
    let merged: Bool?
    let number: Int
}

extension Event {
    func decode(from data: Data) throws -> Notificatable {
        let decoder = JSONDecoder()
        switch self {
        case .ping:
            return try decoder.decode(PingEvent.self, from: data)
        case .push:
            return try decoder.decode(PushEvent.self, from: data)
        case .check_run:
            return try decoder.decode(CheckRunEvent.self, from: data)
        case .check_suite:
            return try decoder.decode(CheckSuiteEvent.self, from: data)
        case .commit_comment:
            return try decoder.decode(CommitCommentEvent.self, from: data)
        case .create:
            return try decoder.decode(CreateEvent.self, from: data)
        case .delete:
            return try decoder.decode(DeleteEvent.self, from: data)
        case .deployment:
            return try decoder.decode(DeploymentEvent.self, from: data)
        case .deployment_status:
            return try decoder.decode(DeploymentStatusEvent.self, from: data)
        case .fork:
            return try decoder.decode(ForkEvent.self, from: data)
        case .gollum:
            return try decoder.decode(GollumEvent.self, from: data)
        case .issue_comment:
            return try decoder.decode(IssueCommentEvent.self, from: data)
        case .issues:
            return try decoder.decode(IssuesEvent.self, from: data)
        case .label:
            return try decoder.decode(LabelEvent.self, from: data)
        case .member:
            return try decoder.decode(MemberEvent.self, from: data)
        case .membership:
            return try decoder.decode(MembershipEvent.self, from: data)
        case .milestone:
            return try decoder.decode(MilestoneEvent.self, from: data)
        case .organization:
            return try decoder.decode(OrganizationEvent.self, from: data)
        case .org_block:
            return try decoder.decode(OrgBlockEvent.self, from: data)
        case .page_build:
            return try decoder.decode(PageBuildEvent.self, from: data)
        case .project_card:
            return try decoder.decode(ProjectCardEvent.self, from: data)
        case .project_column:
            return try decoder.decode(ProjectColumnEvent.self, from: data)
        case .project:
            return try decoder.decode(ProjectEvent.self, from: data)
        case .public:
            return try decoder.decode(PublicEvent.self, from: data)
        case .pull_request:
            return try decoder.decode(PullRequestEvent.self, from: data)
        case .pull_request_review:
            return try decoder.decode(PullRequestReviewEvent.self, from: data)
        case .release:
            return try decoder.decode(ReleaseEvent.self, from: data)
        case .repository:
            return try decoder.decode(RepositoryEvent.self, from: data)
        case .repository_import:
            return try decoder.decode(RepositoryImportEvent.self, from: data)
        case .status:
            return try decoder.decode(StatusEvent.self, from: data)
        case .watch:
            return try decoder.decode(WatchEvent.self, from: data)
        case .pull_request_review_comment:
            return try decoder.decode(PullRequestReviewCommentEvent.self, from: data)
        case .team:
            return try decoder.decode(TeamEvent.self, from: data)
        case .team_add:
            return try decoder.decode(TeamAddEvent.self, from: data)
        case .repository_vulnerability_alert:
            return try decoder.decode(RepositoryVulnerabilityEvent.self, from: data)
        case .marketplace_purchase:
            throw E.unimplemented(rawValue)
        }
    }
}
