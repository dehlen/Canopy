import Foundation
import PerfectHTTP

// https://developer.github.com/v3/activity/events/types/#membershipevent

protocol Notificatable {
    var title: String? { get }
    var body: String? { get }
    var url: URL? { get }
}

extension Notificatable {
    var body: String? { return nil }
    var url: URL? { return nil }
}

struct PingEvent: Decodable, Notificatable {
    let hook: Hook
    let sender: User

    // which is set depends on Hook.type
    let organization: User?
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

struct CheckRunEvent: Decodable, Notificatable {
    let action: String
    let check_run: CheckRun
    let repository: Repository

    struct CheckRun: Decodable {
        let url: URL
        let status: String
    }

    var title: String? {
        return "Check run \(check_run.status)"
    }
    var body: String? {
        return repository.full_name
    }
    var url: URL? {
        return check_run.url
    }
}

struct CheckSuiteEvent: Decodable, Notificatable {
    let action: String
    let check_suite: CheckSuite
    let repository: Repository

    struct CheckSuite: Decodable {
        let url: URL
        let status: String
    }

    var title: String? {
        return "Check suite \(check_suite.status)"
    }
    var body: String? {
        return repository.full_name
    }
    var url: URL? {
        return check_suite.url
    }
}

struct CommitComment: Decodable, Notificatable {
    let action: String
    let comment: Comment
    let repository: Repository

    var title: String? {
        return "\(comment.user.login) commented on commit"
    }
    var body: String? {
        return repository.full_name
    }
    var url: URL? {
        return comment.url
    }
}

struct CreateEvent: Decodable, Notificatable {
    let repository: Repository
    let sender: User

    var title: String? {
        return "\(sender.login) created a repository"
    }
    var body: String? {
        return repository.full_name
    }
    var url: URL? {
        return repository.html_url
    }
}

struct DeleteEvent: Decodable, Notificatable {
    let repository: Repository
    let sender: User

    var title: String? {
        return "\(sender.login) deleted a repository"
    }
    var body: String? {
        return repository.full_name
    }
    var url: URL? {
        return repository.html_url  // but… will 404
    }
}

struct DeploymentEvent: Decodable, Notificatable {
    let repository: Repository
    let deployment: Deployment
    let sender: User

    var title: String? {
        return "\(sender.login) deployed to \(deployment.environment)"
    }
    var body: String? {
        return [deployment.description, repository.full_name].compactMap{ $0 }.joined(separator: ", ")
    }
    var url: URL? {
        return deployment.url
    }
}

struct DeploymentStatusEvent: Decodable, Notificatable {
    let deployment_status: DeploymentStatus
    let deployment: Deployment
    let repository: Repository
    let sender: User

    struct DeploymentStatus: Decodable {
        let url: URL
        let status: String
        let description: String?
    }

    var title: String? {
        return "\(sender.login) deployed to \(deployment.environment)"
    }
    var body: String? {
        return deployment_status.status
    }
    var url: URL? {
        return deployment_status.url
    }
}

struct ForkEvent: Decodable, Notificatable {
    let forkee: Repository
    let repository: Repository
    let sender: User

    var title: String? {
        return "\(sender.login) forked \(forkee.full_name)"
    }
    var body: String? {
        return repository.full_name
    }
    var url: URL? {
        return repository.html_url
    }
}

struct GollumEvent: Decodable, Notificatable {
    let pages: [Page]
    let repository: Repository
    let sender: User

    struct Page: Decodable {
        let page_name: String
        let title: String
        let summary: String?
        let action: String
        let html_url: URL
    }

    var title: String? {
        return "\(sender.login) wiki’d"
    }
    var body: String? {
        return "\(pages.count) wiki events"
    }
    var url: URL? {
        return pages.first?.html_url
    }
}

struct InstallationEvent: Decodable, Notificatable {
    let action: String
    let installation: Installation
    let repositories: [Repository]
    let sender: User

    var title: String? {
        return "\(sender.login) \(action) a GitHub app \(installation.app_id)"
    }
    var body: String? {
        return "\(repositories.count) repos affected"
    }
    var url: URL? {
        return installation.html_url
    }
}

struct InstallationRepositoriesEvent: Decodable, Notificatable {
    let action: String
    let installation: Installation
    let sender: User

    var title: String? {
        return "\(sender.login) \(action) a GitHub app \(installation.app_id)"
    }
    var body: String? {
        return "That’s all we got" //FIXME
    }
    var url: URL? {
        return installation.html_url
    }
}

struct IssueCommentEvent: Decodable, Notificatable {
    let action: String
    let issue: Issue
    let comment: Comment
    let repository: Repository
    let sender: User

    var title: String? {
        return "\(sender.login) \(action) a comment"
    }
    var body: String? {
        return "\(repository.full_name)#\(issue.number)"
    }
    var url: URL? {
        return issue.url
    }
}

struct IssuesEvent: Decodable, Notificatable {
    let action: String
    let issue: Issue
    let repository: Repository
    let sender: User

    var title: String? {
        return "\(sender.login) \(action) #\(issue.number)"
    }
    var body: String? {
        return repository.full_name
    }
    var url: URL? {
        return issue.url
    }
}

struct LabelEvent: Decodable, Notificatable {
    let action: String
    let label: Label
    let repository: Repository
    let sender: User

    struct Label: Decodable {
        let name: String
        let url: URL
        let color: String
    }

    var title: String? {
        return "\(sender.login) \(action) a label"
    }
    var body: String? {
        return "\(label.name) (\(label.color))"
    }
    var url: URL? {
        return label.url
    }
}

struct MemberEvent: Decodable, Notificatable {
    let action: String
    let member: User
    //let changes: Changes
    let repository: Repository
    let sender: User

//    struct Changes: Decodable {
//        let permission: Permission
//        struct Permission: Decodable {
//            let from: String?
//        }
//    }

    var title: String? {
        return "\(sender.login) \(action) membership for \(member.login)"
    }
    var body: String? {
        return repository.full_name
    }
    var url: URL? {
        return repository.contributors_url
    }
}

struct MembershipEvent: Decodable, Notificatable {
    let action: String
    let scope: String
    let user: User
    let sender: User
    let organization: User
    let team: Team

    struct Team: Decodable {
        let name: String
        let url: URL
    }

    var title: String? {
        return "\(sender.login) \(action) membership for \(organization.login)"
    }
    var body: String? {
        return "Added to team: \(team.name)"
    }
    var url: URL? {
        return team.url
    }
}

struct MilestoneEvent: Decodable, Notificatable {
    let action: String
    let sender: User
    let repository: Repository
    let milestone: Milestone

    struct Milestone: Decodable {
        let html_url: URL
        let title: String
        let description: String?
    }

    var title: String? {
        return "\(sender.login) \(action) a milestone: \(milestone.title)"
    }
    var body: String? {
        return repository.full_name
    }
    var url: URL? {
        return milestone.html_url
    }
}

struct OrganizationEvent: Decodable, Notificatable {  //TODO half-arsed
    let action: String
    let organization: User
    let sender: User

    var title: String? {
        return "\(sender.login) \(action) a member"
    }
    var body: String? {
        return "To: " + organization.login
    }
}

struct OrgBlockEvent: Decodable, Notificatable {  //TODO half-arsed
    let action: String
    let blocked_user: User
    let organization: User
    let sender: User

    var title: String? {
        return "\(sender.login) \(action) \(blocked_user.login)"
    }
    var body: String? {
        return "Org: " + organization.login
    }
}

struct PageBuildEvent: Decodable, Notificatable {
    let build: Build
    let repository: Repository
    let sender: User

    struct Build: Decodable {
        let url: URL
        let status: String
        let error: Error?

        struct Error: Decodable {
            let message: String?
        }
    }

    var title: String? {
        return "GitHub Pages build complete: \(build.status)"
    }
    var body: String? {
        return repository.full_name
    }
    var url: URL? {
        return build.url
    }
}

struct PushEvent: Decodable, Notificatable {
    let repository: Repository
    let pusher: Pusher
    let commits: [Commit]
    let compare: URL
    let forced: Bool
    let head_commit: Commit

    struct Pusher: Decodable {
        let name: String
    }
    struct Commit: Decodable {
        let message: String
        let url: URL
    }

    var title: String? {
        let force = forced ? "force‑" : ""
        return "\(pusher.name) \(force)pushed to \(repository.full_name)"
    }
    var body: String? {
        if commits.count == 1 {
            return "Contains 1 commit"
        } else {
            return "Contains \(commits.count) commits"
        }
    }
    var url: URL? {
        return head_commit.url
    }
}

// Actually: stars
struct WatchEvent: Decodable, Notificatable {
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
        return "\(sender.login) \(mangledAction) \(repository.full_name)"
    }
    var body: String? {
        return repository.full_name
    }
    var url: URL? {
        return repository.html_url
    }
}

// types

struct User: Decodable {
    let login: String
}

struct Repository: Decodable {
    let full_name: String
    let `private`: Bool
    let html_url: URL
    let contributors_url: URL
}

struct Deployment: Decodable {
    let url: URL
    let description: String?
    let environment: String
}

struct Installation: Decodable {
    let html_url: URL
    let app_id: Int
}

struct Issue: Decodable {
    let url: URL
    let number: Int
}

struct Comment: Decodable {
    let url: URL
    let body: String
    let user: User
}
