import Foundation
import PerfectHTTP

enum Context {
    case organization(User)
    case repository(Repository)
}

protocol Notificatable {
    var title: String? { get }
    var body: String { get }
    var url: URL? { get }
    var context: Context { get }
    var threadingId: String { get }
}

extension Notificatable {
    var url: URL? { return nil }

    var title: String? {
        switch context {
        case .repository(let repo):
            return repo.full_name
        case .organization(let org):
            return "The \(org.login) organization"
        }
    }

    var threadingId: String {
        switch context {
        case .organization(let org):
            return "orgs/\(org.login)"  // github reserve this prefix
        case .repository(let repo):
            return "repo/\(repo.id)"
        }
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
        if hook.type == "Organization" {
            let org = try container.decode(User.self, forKey: .organization)
            context = .organization(org)
        } else if hook.type == "Repository" {
            let repo = try container.decode(Repository.self, forKey: .repository)
            context = .repository(repo)
        } else {
            throw E.invalidPingHookType(hook.type)
        }
        sender = try container.decode(User.self, forKey: .sender)
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
        case .organization(let org):
            return "Webhook added to the \(org.login) organization"
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

    var body: String {
        return "\(comment.user.login) commented on a commit"
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
            return "\(sender.login) branched “\(ref)"
        case .tag:
            guard let ref = ref else { fallthrough }
            return "\(sender.login) tagged “\(ref)"
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
        let status: String
        let description: String?
    }

    var body: String {
        return "\(sender.login) deployed to \(deployment.environment) with status: \(deployment_status.status)"
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

    var body: String {
        return "\(sender.login) \(action) a comment on #\(issue.number)"
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
    let organization: User
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
        return "\(sender.login) \(action) membership. Added to team: \(team.name)"
    }
    var url: URL? {
        return team.url
    }

    var context: Context {
        return .organization(organization)
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
    let organization: User
    let sender: User
    let membership: Membership

    struct Membership: Codable {
        let user: User
    }

    enum Action: String, Codable {
        case member_added, member_removed, member_invited
    }

    var body: String {
        return "\(sender.login) \(action) a member"
    }

    var context: Context {
        return .organization(organization)
    }
}

struct OrgBlockEvent: Codable, Notificatable {  //TODO half-arsed
    let action: String
    let blocked_user: User
    let organization: User
    let sender: User

    enum Action: String, Codable {
        case blocked, unblocked
    }

    var body: String {
        return "\(sender.login) \(action) \(blocked_user.login)"
    }

    var context: Context {
        return .organization(organization)
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
    let action: String
    let project_card: ProjectCard
    let repository: Repository
    let sender: User

    var body: String {
        return "\(sender.login) \(action) the “\(project_card.note)” project card"
    }
    var url: URL? {
        // https://github.com/orgs/codebasesaga/projects/1#card-10299301
        return repository.html_url.appendingPathComponent("projects")
    }
    var context: Context {
        return .repository(repository)
    }

    struct ProjectCard: Codable {
        let note: String
    }
}

struct ProjectColumnEvent: Codable, Notificatable {
    let action: String
    let project_column: ProjectColumn
    let repository: Repository
    let sender: User

    var body: String {
        return "\(sender.login) \(action) the “\(project_column.name)” project column"
    }
    var url: URL? {
        // https://github.com/orgs/codebasesaga/projects/1#column-2827834
        return repository.html_url.appendingPathComponent("projects")
    }
    var context: Context {
        return .repository(repository)
    }

    struct ProjectColumn: Codable {
        let name: String
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

    var body: String {
        return "\(sender.login) commented on PR review #\(pull_request.number)"
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
    let compare: URL
    let forced: Bool
    let distinct_size: Int?
    let commits: [Commit]

    struct Commit: Codable {
        let message: String
    }

    struct Pusher: Codable {
        let name: String
    }

    var body: String {
        let size = distinct_size ?? self.commits.count
        let force = forced ? "force‑" : ""
        let commits = size == 1
            ? "1 commit"
            : "\(size) commits"
        return "\(pusher.name) \(force)pushed \(commits)"
    }
    var url: URL? {
        return compare
    }

    var context: Context {
        return .repository(repository)
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
        if action == .closed, let merged = pull_request.merged, merged {
            return "\(sender.login) merged \(repository.full_name)#\(number)"
        } else if action == .synchronize {
            return "\(sender.login) synchronized \(repository.full_name)#\(number)"
        } else {
            return "\(sender.login) \(action) \(repository.full_name)#\(number)"
        }
    }
    var url: URL? {
        return pull_request.html_url
    }

    var context: Context {
        return .repository(repository)
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
        let state: String
        let html_url: URL
    }

    var body: String {
        return "\(review.user.login) \(action) to \(repository.full_name)#\(pull_request.number)"
    }
    var url: URL? {
        return review.html_url
    }

    var context: Context {
        return .repository(repository)
    }
}

struct ReleaseEvent: Codable, Notificatable {
    let action: String
    let release: Release
    let sender: User
    let repository: Repository

    var body: String {
        return "\(sender.login) released \(release.name ?? release.tag_name)"
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
}

// types

struct User: Codable {
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
    let body: String
    let merged: Bool?
    let number: Int
}
