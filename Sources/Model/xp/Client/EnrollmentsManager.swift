import Foundation
import PromiseKit
import Dispatch
import Vendor
#if os(iOS)
import UIKit
#endif
import xp

public protocol EnrollmentsManagerDelegate: class {
    func enrollmentsManager(_: EnrollmentsManager, isUpdating: Bool)
    func enrollmentsManagerDidUpdate(_: EnrollmentsManager, expandTree: Bool)
    func enrollmentsManager(_: EnrollmentsManager, error: Error)
}

public class EnrollmentsManager {
    public private(set) var hooks: Set<Node> = []
    public private(set) var repos = SortedSet<Repo>()
    public private(set) var enrollments: Set<Enrollment> = []

    public init() {
        #if os(iOS)
        NotificationCenter.default.addObserver(self, selector: #selector(update), name: UIApplication.didBecomeActiveNotification, object: nil)
        #endif
    }

    public weak var delegate: EnrollmentsManagerDelegate? {
        didSet {
            if let delegate = delegate, token != nil {
                delegate.enrollmentsManagerDidUpdate(self, expandTree: false)
                update()
            }
        }
    }

    /// github token
    public var token: String? {
        didSet {
            guard token != oldValue, let delegate = delegate, token != nil else { return }
            delegate.enrollmentsManagerDidUpdate(self, expandTree: false)
            update()
        }
    }

    private var fetching = false {
        didSet {
            updateFetching()
        }
    }

    //FIXME enroll() is not using this anymore
    private var installing: Set<Int> = [] {
        didSet {
            updateFetching()
        }
    }

    private func updateFetching() {
        delegate?.enrollmentsManager(self, isUpdating: fetching || !installing.isEmpty)
    }

    private var alter: Promise<Enrollment>?
}

public extension EnrollmentsManager {
    enum Error: Swift.Error {
        case paymentRequired
        case noToken
        case invalidRepoName(String)
    }

    var rootedRepos: [String: [Repo]] {
        return Dictionary(grouping: repos, by: { $0.owner.login })
    }

    var rootedReposKeys: [String] {
        return rootedRepos.keys.map{ ($0, $0.lowercased()) }.sorted{ $0.1 < $1.1 }.map{ $0.0 }
    }

    var nodes: Set<Node> {
        return Set(repos.map { repo in
            if repo.isPartOfOrganization {
                return .organization(repo.owner.login)
            } else {
                return .init(repo)
            }
        })
    }

    var isFetching: Bool {
        return fetching
    }

    enum Status {
        case active
        case alert(Alert)
        case inactive

        public enum Alert {
            /// repo is enrolled *but* there is no active subscription
            /// prompt user to subscribe to restore functionality
            case paymentRequired
            /// no hook and user has no clearance to create it
            case cannotCreateHook
            /** User is enrolled, hook is not installed and user CAN install it.
              strictly this should be impossible since we don't check if the
              hook is actually installed server-side, we just remember that we
              installed it. */
            case hookNotInstalled
        }
    }

    func isHooked(_ repo: Repo) -> Bool {
        if repo.isPartOfOrganization {
            return hooks.contains(.organization(repo.owner.login))
        } else {
            return hooks.contains(.init(repo))
        }
    }

    func status(for repo: Repo, hasReceipt: Bool) -> Status {
        if fetching, enrollments.isEmpty || hooks.isEmpty {
            return .inactive // we will notify delegate again when fetching is complete
        }
        if !isHooked(repo) {
            if !repo.permissions.admin {
                return .alert(.cannotCreateHook)
            } else if enrollments.contains(repo) {
                return .alert(.hookNotInstalled)
            } else {
                // no problems will occur if user tries to enroll
                return .inactive
            }
        } else if !hasReceipt, repo.private, enrollments.contains(repo) {
            return .alert(.paymentRequired)
        } else {
            return enrollments.contains(repo) ? .active : .inactive
        }
    }

    @objc func update() {
        dispatchPrecondition(condition: .onQueue(.main))

    #if os(iOS)
        var shouldNotifyError = true
        var task: UIBackgroundTaskIdentifier!
        task = UIApplication.shared.beginBackgroundTask(expirationHandler: {
            dispatchPrecondition(condition: .onQueue(.main))
            shouldNotifyError = false
            UIApplication.shared.endBackgroundTask(task)
        })
    #else
        ProcessInfo.processInfo.disableSuddenTermination()
        ProcessInfo.processInfo.disableAutomaticTermination("Networking…")
        let shouldNotifyError = true
    #endif

        guard !fetching else { return }

        guard let token = token else {
            delegate?.enrollmentsManager(self, error: Error.noToken)
            return
        }

        let api = GitHubAPI(oauthToken: token)

        func repos() -> Promise<Void> {
            let fetchRepos = api.task(path: "/user/repos") { data in
                DispatchQueue.global().async(.promise) {
                    try JSONDecoder().decode([Repo].self, from: data)
                }.done {
                    self.repos.formUnion($0)
                    self.delegate?.enrollmentsManagerDidUpdate(self, expandTree: false)
                }
            }

            func stragglers() -> Guarantee<[Repo]> {

                //TODO we ignore errors as it is hard to propogate them.
                // A typical error here is a 404 due to a repo being deleted
                // if it is deleted we don’t get it from `fetchRepos()` above
                // yet we get it from debris because user is enrolled so we
                // try to fetch it here in `stragglers()` where it 404s

                let repoIds = Set(self.repos.map(\.id))
                return when(resolved: self.enrollments.filter {
                    !repoIds.contains($0.repoId)
                }.map {
                    api.request(path: "/repositories/\($0.repoId)")
                }.map {
                    URLSession.shared.dataTask(.promise, with: $0).validate()
                }).map {
                    $0.compactMap {
                        guard case .fulfilled(let rsp) = $0 else { return nil }
                        return try? JSONDecoder().decode(Repo.self, from: rsp.data)
                    }
                }
            }

            return firstly {
                when(fulfilled: fetchRepos, fetchEnrollments(token: token)).map{ $1 }
            }.done {
                assert(SubscriptionManager.shared != nil)
                SubscriptionManager.shared?.hasVerifiedReceipt = $0.1
                self.enrollments = $0.0
                self.delegate?.enrollmentsManagerDidUpdate(self, expandTree: true)
            }.then {
                stragglers()
            }.done {
                self.repos.formUnion($0)
                self.delegate?.enrollmentsManagerDidUpdate(self, expandTree: true)
            }
        }

        fetching = true

        firstly {
            repos()
        }.then {
            fetchInstallations(for: self.repos)
        }.ensure {
          #if os(iOS)
            UIApplication.shared.endBackgroundTask(task)
          #else
            ProcessInfo.processInfo.enableSuddenTermination()
            ProcessInfo.processInfo.enableAutomaticTermination("Networking…")
          #endif
        }.done {
            self.hooks = $0
            self.delegate?.enrollmentsManagerDidUpdate(self, expandTree: false)
        }.catch {
            if shouldNotifyError {
                self.delegate?.enrollmentsManager(self, error: $0)
            }
        }.finally {
            self.fetching = false
        }
    }

    enum Item: Equatable {
        case organization(String)
        case repository(Repo)
        case user(String)
    }

    func enroll(_ node: Item, toggleDirection willEnroll: Bool) throws -> Promise<Void> {
        guard let token = token else {
            throw Error.noToken
        }

        let hookTargets: [Node]
        let enrollRepoIds: [Int]
        switch node {
        case .organization(let login):
            let repos = rootedRepos[login]!
            hookTargets = [.organization(login)]
            enrollRepoIds = repos.map(\.id)
        case .repository(let repo):
            if repo.isPartOfOrganization {
                hookTargets = [.organization(repo.owner.login)]
            } else {
                hookTargets = [.init(repo)]
            }
            enrollRepoIds = [repo.id]
        case .user(let login):
            let repos = rootedRepos[login]!
            hookTargets = repos.map(Node.init)
            enrollRepoIds = repos.map(\.id)
        }

        let body = willEnroll
            ? try JSONEncoder().encode(API.Enroll(createHooks: hookTargets, enrollRepoIds: enrollRepoIds))
            : try JSONEncoder().encode(API.Unenroll(repoIds: enrollRepoIds))

        let httpMethod = willEnroll ? "POST" : "DELETE"

        var rq = URLRequest(.enroll)
        rq.httpMethod = httpMethod
        rq.httpBody = body
        rq.addValue("application/json", forHTTPHeaderField: "Content-Type")
        rq.addValue(token, forHTTPHeaderField: "Authorization")

        return firstly {
            URLSession.shared.dataTask(.promise, with: rq).httpValidate().asVoid()
        }.recover(on: .main) { error -> Void in
            switch error {
            case API.Enroll.Error.noClearance(let failedRepoIds):
                let newRepoIds = Set(enrollRepoIds).subtracting(failedRepoIds)
                let newEnrollments = newRepoIds.map(Enrollment.init)
                self.enrollments.formUnion(newEnrollments)
            case API.Enroll.Error.hookCreationFailed(let failedNodes):
                self.enrollments.formUnion(enrollRepoIds.map(Enrollment.init))
                self.hooks.formUnion(Set(hookTargets).subtracting(failedNodes))
            default:
                break
            }
            throw error
        }.done {
            if willEnroll {
                self.hooks.formUnion(hookTargets)
                self.enrollments.formUnion(enrollRepoIds.map(Enrollment.init))
            } else {
                self.enrollments.subtract(enrollRepoIds.map(Enrollment.init))
            }
        }.ensure {
            self.delegate?.enrollmentsManagerDidUpdate(self, expandTree: false)
        }
    }

    func alter(enrollment: Enrollment, events: Set<Event>) throws -> Promise<Enrollment> {
        dispatchPrecondition(condition: .onQueue(.main))

        guard let token = token else {
            throw Error.noToken
        }

        let rv = Enrollment(repoId: enrollment.repoId, events: events)

        var rq = URLRequest(.enroll)
        rq.addValue(token, forHTTPHeaderField: "Authorization")
        rq.httpMethod = "PUT"
        rq.httpBody = try JSONEncoder().encode(rv)
        rq.addValue("application/json", forHTTPHeaderField: "Content-Type")

        alter = firstly {
            alter?.asVoid() ?? Promise()
        }.then {
            URLSession.shared.dataTask(.promise, with: rq).httpValidate()
        }.map { _ in
            rv
        }.get {
            self.enrollments.remove(enrollment)
            self.enrollments.insert($0)  // insert _does_not_ replace
        }

        return alter!
    }

    func add(repoFullName full_name: String) -> Promise<Repo> {
        guard full_name.contains("/"), let token = creds?.token else {
            return Promise(error: Error.invalidRepoName(full_name))
        }

        //TODO ust refresh hook information, maybe it's been days and the user knows the data is stale!
        func fetchInstallation(for repo: Repo) -> Promise<Node?> {
            return firstly {
                fetchInstallations(for: [repo])
            }.map {
                $0.first
            }
        }

        let rq = GitHubAPI(oauthToken: token).request(path: "/repos/\(full_name)")

        return firstly {
            URLSession.shared.dataTask(.promise, with: rq).validate()
        }.map {
            try JSONDecoder().decode(Repo.self, from: $0.data)
        }.then { repo in
            fetchInstallation(for: repo).done {
                if let repo = $0 {
                    self.hooks.insert(repo)
                }
                self.repos.insert(repo)
            }.map {
                repo
            }
        }.get { _ in
            self.delegate?.enrollmentsManagerDidUpdate(self, expandTree: true)
        }
    }
}

private func fetchEnrollments(token: String) -> Promise<(Set<Enrollment>, Bool)> {
    var rq = URLRequest(.enroll)
    rq.addValue(token, forHTTPHeaderField: "Authorization")
    return firstly {
        URLSession.shared.dataTask(.promise, with: rq).validate()
    }.map { data, rsp -> (Set<Enrollment>, Bool) in
        let subs = Set(try JSONDecoder().decode([Enrollment].self, from: data))
        let verifiedReceipt = (rsp as? HTTPURLResponse)?.allHeaderFields["Upgrade"] as? String == "true"
        return (subs, verifiedReceipt)
    }
}

private func fetchInstallations<T: Sequence>(for repos: T) -> Promise<Set<Node>> where T.Element == Repo {
    let ids = repos.map {
        $0.isPartOfOrganization
            ? $0.owner.id
            : $0.id
    }

    func unconvert(_ id: Int) -> Node? {
        for repo in repos {
            if repo.id == id {
                return .init(repo)
            } else if repo.owner.id == id {
                return .organization(repo.owner.login)
            }
        }
        return nil
    }

    //FIXME need to store ids in Node really, ids are stable, names are not
    var cc = URLComponents(.hook)
    cc.queryItems = ids.map{ URLQueryItem(name: "ids[]", value: String($0)) }
    let rq = URLRequest(url: cc.url!)
    return firstly {
        URLSession.shared.dataTask(.promise, with: rq).validate()
    }.map {
        try JSONDecoder().decode([Int].self, from: $0.data)
    }.compactMapValues(unconvert).map(Set.init)
}

private extension Enrollment {
    init(repoId: Int) {
        self.init(repoId: repoId, events: [Event].default)
    }
}
