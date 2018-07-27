import Foundation
import PerfectHTTP

enum Context {
    case organization(id: Int)
    case repository(id: Int)
    case alert

    init(_ repo: Repository) {
        self = .repository(id: repo.id)
    }
}

protocol Notificatable {
    var title: String? { get }
    var body: String { get }
    var url: URL? { get }
    var context: Context { get }
    var threadingId: String? { get }
}

extension Notificatable {
    var url: URL? { return nil }

    var threadingId: String? {
        switch context {
        case .organization(id: let id):
            return "orgs/\(id)"
        case .repository(id: let id):
            return "repo/\(id)"
        case .alert:
            return nil
        }
    }
}

// https://developer.github.com/v3/activity/events

struct PingEvent: Codable, Notificatable {
    let hook: Hook
    let sender: User

    // which is set depends on Hook.type
    let organization: User?
    let repository: Repository?

    struct Hook: Codable {
        let type: String
    }

    var title: String? {
        switch context {
        case .repository:
            return repository?.full_name
        case .organization:
            return organization?.login
        case .alert:
            return nil
        }
    }

    var body: String {
        enum E: Error {
            case unexpected
        }

        do {
            switch hook.type.lowercased() {
            case "organization":
                guard let login = organization?.login else { throw E.unexpected }
                return "Webhook added to the \(login) organization"
            case "repository":
                guard let repo = repository?.full_name else { throw E.unexpected }
                return "Webhook added to \(repo)"
            default:
                throw E.unexpected
            }
        } catch {
            return "Received unexpected ping payload of type: \(hook.type)"
        }
    }

    var context: Context {
        if let org = organization {
            return .organization(id: org.id)
        } else {
            return .repository(id: repository!.id)
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

    var title: String? {
        return repository.full_name
    }
    var body: String {
        return "Check run \(check_run.status)"
    }
    var url: URL? {
        return check_run.url
    }

    var context: Context {
        return .repository(id: repository.id)
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

    var title: String? {
        return repository.full_name
    }
    var body: String {
        return "Check suite \(check_suite.status)"
    }
    var url: URL? {
        return check_suite.url
    }

    var context: Context {
        return .repository(id: repository.id)
    }
}

// https://developer.github.com/v3/activity/events/types/#commitcommentevent
struct CommitComment: Codable, Notificatable {
    let action: String
    let comment: Comment
    let repository: Repository

    var title: String? {
        return repository.full_name
    }
    var body: String {
        return "\(comment.user.login) commented on a commit"
    }
    var url: URL? {
        return comment.html_url
    }

    var context: Context {
        return .repository(id: repository.id)
    }
}

// https://developer.github.com/v3/activity/events/types/#createevent
struct CreateEvent: Codable, Notificatable {
    let repository: Repository
    let sender: User

    var title: String? {
        return repository.full_name
    }
    var body: String {
        return "\(sender.login) created a repository"
    }
    var url: URL? {
        return repository.html_url
    }

    var context: Context {
        return .repository(id: repository.id)
    }
}

struct DeleteEvent: Codable, Notificatable {
    let repository: Repository
    let sender: User

    var title: String? {
        return repository.full_name
    }
    var body: String {
        return "\(sender.login) deleted a repository"
    }
    var url: URL? {
        return repository.html_url  // but… will 404
    }

    var context: Context {
        return .repository(id: repository.id)
    }
}

struct DeploymentEvent: Codable, Notificatable {
    let repository: Repository
    let deployment: Deployment
    let sender: User

    var title: String? {
        return repository.full_name
    }
    var body: String {
        return "\(sender.login) deployed to \(deployment.environment)"
    }
    var url: URL? {
        return deployment.url
    }

    var context: Context {
        return .repository(id: repository.id)
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

    var title: String? {
        return repository.full_name
    }
    var body: String {
        return "\(sender.login) deployed to \(deployment.environment) with status: \(deployment_status.status)"
    }
    var url: URL? {
        return deployment_status.url
    }

    var context: Context {
        return .repository(id: repository.id)
    }
}

struct ForkEvent: Codable, Notificatable {
    let forkee: Repository
    let repository: Repository
    let sender: User

    var title: String? {
        return repository.full_name
    }
    var body: String {
        return "\(sender.login) forked \(repository.full_name)"
    }
    var url: URL? {
        return repository.html_url
    }

    var context: Context {
        return .repository(id: repository.id)
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

    var title: String? {
        return repository.full_name
    }
    var body: String {
        return "\(sender.login) triggered \(pages.count) wiki events"
    }
    var url: URL? {
        return pages.first?.html_url
    }

    var context: Context {
        return .repository(id: repository.id)
    }
}

struct IssueCommentEvent: Codable, Notificatable {
    let action: String
    let issue: Issue
    let comment: Comment
    let repository: Repository
    let sender: User

    var title: String? {
        return repository.full_name
    }
    var body: String {
        return "\(sender.login) \(action) a comment on #\(issue.number)"
    }
    var url: URL? {
        return issue.html_url
    }

    var context: Context {
        return .repository(id: repository.id)
    }
}

struct IssuesEvent: Codable, Notificatable {
    let action: String
    let issue: Issue
    let repository: Repository
    let sender: User

    var title: String? {
        return repository.full_name
    }
    var body: String {
        return "\(sender.login) \(action) #\(issue.number)"
    }
    var url: URL? {
        return issue.html_url
    }

    var context: Context {
        return .repository(id: repository.id)
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

    var title: String? {
        return repository.full_name
    }
    var body: String {
        return "\(sender.login) \(action) a label (\(label.name) (\(label.color))"
    }
    var url: URL? {
        return label.url
    }

    var context: Context {
        return .repository(id: repository.id)
    }
}

struct MemberEvent: Codable, Notificatable {
    let action: String
    let member: User
    let repository: Repository
    let sender: User

    var title: String? {
        return repository.full_name
    }
    var body: String {
        return "\(sender.login) \(action) membership for \(member.login)"
    }
    var url: URL? {
        return repository.contributors_url
    }

    var context: Context {
        return .repository(id: repository.id)
    }
}

struct MembershipEvent: Codable, Notificatable {
    let action: String
    let scope: String
    let user: User
    let sender: User
    let organization: User
    let team: Team

    struct Team: Codable {
        let name: String
        let url: URL
    }

    var title: String? {
        return "The \(organization.login) organization"
    }
    var body: String {
        return "\(sender.login) \(action) membership. Added to team: \(team.name)"
    }
    var url: URL? {
        return team.url
    }

    var context: Context {
        return .organization(id: organization.id)
    }
}

struct MilestoneEvent: Codable, Notificatable {
    let action: String
    let sender: User
    let repository: Repository
    let milestone: Milestone

    struct Milestone: Codable {
        let html_url: URL
        let title: String
        let description: String?
    }

    var title: String? {
        return repository.full_name
    }
    var body: String {
        return "\(sender.login) \(action) a milestone: \(milestone.title)"
    }
    var url: URL? {
        return milestone.html_url
    }

    var context: Context {
        return .repository(id: repository.id)
    }
}

struct OrganizationEvent: Codable, Notificatable {  //TODO half-arsed
    let action: String
    let organization: User
    let sender: User

    var title: String? {
        return "The \(organization.login) organization"
    }
    var body: String {
        return "\(sender.login) \(action) a member"
    }

    var context: Context {
        return .organization(id: organization.id)
    }
}

struct OrgBlockEvent: Codable, Notificatable {  //TODO half-arsed
    let action: String
    let blocked_user: User
    let organization: User
    let sender: User

    var title: String? {
        return "The \(organization.login) organization"
    }
    var body: String {
        return "\(sender.login) \(action) \(blocked_user.login)"
    }

    var context: Context {
        return .organization(id: organization.id)
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

    var title: String? {
        return repository.full_name
    }
    var body: String {
        return "GitHub Pages build complete: \(build.status)"
    }
    var url: URL? {
        return build.url
    }

    var context: Context {
        return .repository(id: repository.id)
    }
}

struct PushEvent: Codable, Notificatable {
    let repository: Repository
    let pusher: Pusher
    let commits: [Commit]
    let compare: URL
    let forced: Bool
    let head_commit: Commit

    struct Pusher: Codable {
        let name: String
    }
    struct Commit: Codable {
        let message: String
        let url: URL
    }

    var title: String? {
        return repository.full_name
    }
    var body: String {
        let force = forced ? "force‑" : ""
        let commits = self.commits.count == 1
            ? "1 commit"
            : "\(self.commits.count) commits"
        return "\(pusher.name) \(force)pushed \(commits)"
    }
    var url: URL? {
        return head_commit.url
    }

    var context: Context {
        return .repository(id: repository.id)
    }
}

// https://developer.github.com/v3/activity/events/types/#pullrequestevent
struct PullRequestEvent: Codable, Notificatable {
    let action: String
    let number: Int
    let pull_request: PullRequest
    let repository: Repository
    let sender: User

    var title: String? {
        return repository.full_name
    }

    var body: String {
        if action == "closed", pull_request.merged {
            return "\(sender.login) merged \(repository.full_name)#\(number)"
        } else {
            return "\(sender.login) \(action) \(repository.full_name)#\(number)"
        }
    }
    var url: URL? {
        return pull_request.html_url
    }

    var context: Context {
        return .repository(id: repository.id)
    }
}

// https://developer.github.com/v3/activity/events/types/#pullrequestreviewevent
struct PullRequestReviewEvent: Codable, Notificatable {
    let action: String
    let pull_request: PullRequest
    let review: Review
    let sender: User
    let repository: Repository

    struct Review: Codable {
        let user: User
        let state: String
        let html_url: URL
    }

    var title: String? {
        return repository.full_name
    }
    var body: String {
        return "\(review.user.login) \(action) to \(repository.full_name)#\(pull_request.number)"
    }
    var url: URL? {
        return review.html_url
    }

    var context: Context {
        return .repository(id: repository.id)
    }
}

struct StatusEvent: Codable, Notificatable {
    let name: String
    let state: String
    let sender: User
    let description: String?
    let repository: Repository
    let target_url: URL?

    var title: String? {
        return repository.full_name
    }
    var body: String {
        return "The status of \(name) changed to \(state)"
    }
    var url: URL? {
        return target_url
    }

    var context: Context {
        return .repository(id: repository.id)
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

    var title: String? {
        return repository.full_name
    }
    var body: String {
        return "\(sender.login) \(mangledAction) \(repository.full_name) resulting in \(repository.stargazers_count) stars"
    }
    var url: URL? {
        return repository.html_url
    }

    var context: Context {
        return .repository(id: repository.id)
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
    let merged: Bool
    let number: Int
}
