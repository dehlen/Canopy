import Foundation
import PerfectHTTP

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
}

// https://developer.github.com/v3/activity/events/types/

struct PingEvent: Codable, Notificatable {
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

struct CheckRunEvent: Codable, Notificatable {
    let action: String
    let check_run: CheckRun
    let repository: Repository

    struct CheckRun: Codable {
        let url: URL
        let status: String
    }

    var body: String {
        return "Check run \(check_run.status)"
    }
    var url: URL? {
        return check_run.url
    }

    var context: Context {
        return .repository(repository)
    }
}

struct CheckSuiteEvent: Codable, Notificatable {
    let action: String
    let check_suite: CheckSuite
    let repository: Repository

    struct CheckSuite: Codable {
        let url: URL
        let status: String
    }

    var body: String {
        return "Check suite \(check_suite.status)"
    }
    var url: URL? {
        return check_suite.url
    }

    var context: Context {
        return .repository(repository)
    }
}

// https://developer.github.com/v3/activity/events/types/#commitcommentevent
struct CommitComment: Codable, Notificatable {
    let action: String
    let comment: Comment
    let repository: Repository

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
struct CreateEvent: Codable, Notificatable {
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

struct DeleteEvent: Codable, Notificatable {
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

struct DeploymentEvent: Codable, Notificatable {
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

struct DeploymentStatusEvent: Codable, Notificatable {
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

struct ForkEvent: Codable, Notificatable {
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

struct GollumEvent: Codable, Notificatable {
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

struct IssueCommentEvent: Codable, Notificatable {
    let action: String
    let issue: Issue
    let comment: Comment
    let repository: Repository
    let sender: User

    var subtitle: String? {
        return "\(sender.login) \(action) a comment on #\(issue.number)"
    }
    var body: String {
        return comment.body
    }
    var url: URL? {
        return issue.html_url
    }

    var context: Context {
        return .repository(repository)
    }
}

struct IssuesEvent: Codable, Notificatable {
    let action: String
    let issue: Issue
    let repository: Repository
    let sender: User

    var body: String {
        return "\(sender.login) \(action) #\(issue.number)"
    }
    var url: URL? {
        return issue.html_url
    }

    var context: Context {
        return .repository(repository)
    }
}

struct LabelEvent: Codable, Notificatable {
    let action: String
    let label: Label
    let repository: Repository
    let sender: User

    struct Label: Codable {
        let name: String
        let url: URL
        let color: String
    }

    var body: String {
        return "\(sender.login) \(action) a label (\(label.name) (\(label.color))"
    }
    var url: URL? {
        return label.url
    }

    var context: Context {
        return .repository(repository)
    }
}

struct MemberEvent: Codable, Notificatable {
    let action: Action
    let member: User
    let repository: Repository
    let sender: User

    enum Action: String, Codable {
        case deleted, edited, added
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

struct MembershipEvent: Codable, Notificatable {
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

struct MilestoneEvent: Codable, Notificatable {
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

struct OrganizationEvent: Codable, Notificatable {  //TODO half-arsed
    let action: Action
    let organization: Organization
    let sender: User
    let membership: Membership

    struct Membership: Codable {
        let user: User
    }

    enum Action: String, Codable, CustomStringConvertible {
        case member_added, member_removed, member_invited

        var description: String {
            switch self {
            case .member_added:
                return "added"
            case .member_removed:
                return "removed"
            case .member_invited:
                return "invited"
            }
        }
    }

    var body: String {
        return "\(sender.login) \(action) \(membership.user.login)"
    }

    var url: URL {
        return membership.user.html_url
    }

    var context: Context {
        return .organization(organization, admin: sender)
    }
}

struct OrgBlockEvent: Codable, Notificatable {  //TODO half-arsed
    let action: String
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

struct PageBuildEvent: Codable, Notificatable {
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

struct ProjectCardEvent: Codable, Notificatable {
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

struct ProjectColumnEvent: Codable, Notificatable {
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

struct ProjectEvent: Codable, Notificatable {
    let action: String
    let sender: User
    let repository: Repository
    let project: Project

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
    var context: Context {
        return .repository(repository)
    }
}

struct PublicEvent: Codable, Notificatable {
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

struct PullRequestReviewCommentEvent: Codable, Notificatable {
    let action: String
    let comment: Comment
    let pull_request: PullRequest
    let repository: Repository
    let sender: User

    var subtitle: String? {
        return "\(sender.login) commented on PR review #\(pull_request.number)"
    }
    var body: String {
        return comment.body
    }
    var url: URL? {
        return pull_request.html_url
    }
    var context: Context {
        return .repository(repository)
    }
}

struct PushEvent: Codable, Notificatable {
    let repository: Repository
    let pusher: Pusher
    let compare: String // is actually URL, but GitHub are not URL-encoding the ^ character so URL.init fails
    let forced: Bool
    let distinct_size: Int?
    let commits: [Commit]
    let after: String
    let ref: String

    struct Commit: Codable {
        let message: String
    }

    struct Pusher: Codable {
        let name: String
    }

    var size: Int {
        return distinct_size ?? self.commits.count
    }

    var body: String {
        let force = forced ? "force‑" : ""
        if size <= 0 {
            return "\(pusher.name) \(force)pushed to \(ref)"
        } else {
            let commits = size == 1
                ? "1 commit"
                : "\(size) commits"
            return "\(pusher.name) \(force)pushed \(commits)"
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
struct PullRequestEvent: Codable, Notificatable {
    let action: Action
    let number: Int
    let pull_request: PullRequest
    let repository: Repository
    let sender: User

    enum Action: String, Codable {
        case assigned, unassigned, review_requested, review_request_removed, labeled, unlabeled, opened, edited, closed, reopened, synchronize
    }

    var body: String {
        let ticket = "\(repository.full_name)#\(number)"
        let title = "“\(pull_request.title)” (\(ticket))"
        switch action {
        case .closed:
            if let merged = pull_request.merged, merged {
                return "\(sender.login) merged \(title)"
            } else {
                return "\(sender.login) closed \(title)"
            }
        case .synchronize:
            return "\(sender.login) synchronized \(title)"
        case .review_requested:
            return "\(sender.login) requested review for \(title)"
        case .review_request_removed:
            return "\(sender.login) removed the review request for \(title)"
        default:
            return "\(sender.login) \(action) \(title)"
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
struct PullRequestReviewEvent: Codable, Notificatable {
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

    var body: String {
        let review_state = review.state.rawValue.replacingOccurrences(of: "_", with: " ")
        return "\(review.user.login) \(action) \(review_state) to \(repository.full_name)#\(pull_request.number)"
    }
    var url: URL? {
        return review.html_url
    }

    var context: Context {
        return .repository(repository)
    }
}

struct ReleaseEvent: Codable, Notificatable {
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

struct RepositoryEvent: Codable, Notificatable {
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
}

struct StatusEvent: Codable, Notificatable {
    let name: String
    let state: String
    let sender: User
    let description: String?
    let repository: Repository
    let target_url: URL?

    var body: String {
        return "The status of \(name) changed to \(state)"
    }
    var url: URL? {
        return target_url
    }

    var context: Context {
        return .repository(repository)
    }

    var shouldIgnore: Bool {
        return true
    }
}

// Actually: stars
struct WatchEvent: Codable, Notificatable {
    let action: String
    let sender: User
    let repository: Repository

    var mangledAction: String {
        if action == "started" {
            return "starred"
        } else {
            return action
        }
    }

    var body: String {
        return "\(sender.login) \(mangledAction) \(repository.full_name) resulting in \(repository.stargazers_count) stars"
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

// types

struct User: Codable {
    let id: Int
    let login: String
    let html_url: URL
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
}

struct Comment: Codable {
    let html_url: URL
    let body: String
    let user: User
}

struct PullRequest: Codable {
    let html_url: URL
    let state: String
    let title: String
    let body: String?
    let merged: Bool?
    let number: Int
}
