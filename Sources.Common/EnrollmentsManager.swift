import Foundation
import PromiseKit
import Dispatch
#if os(iOS)
import UIKit
#endif

protocol EnrollmentsManagerDelegate: class {
    func enrollmentsManager(_: EnrollmentsManager, isUpdating: Bool)
    func enrollmentsManagerDidUpdate(_: EnrollmentsManager, expandTree: Bool)
    func enrollmentsManager(_: EnrollmentsManager, error: Error)
}

class EnrollmentsManager {
    private(set) var hooks: Set<Node> = []
    private(set) var repos = SortedSet<Repo>()
    private(set) var enrollments: Set<Int> = []

#if os(iOS)
    public init() {
        NotificationCenter.default.addObserver(self, selector: #selector(update), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
#endif

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

    weak var delegate: EnrollmentsManagerDelegate? {
        didSet {
            if let delegate = delegate, token != nil {
                delegate.enrollmentsManagerDidUpdate(self, expandTree: false)
                update()
            }
        }
    }

    /// github token
    var token: String? {
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

    var isFetching: Bool {
        return fetching
    }

    private func updateFetching() {
        delegate?.enrollmentsManager(self, isUpdating: fetching || !installing.isEmpty)
    }

    @objc func update() {
        dispatchPrecondition(condition: .onQueue(.main))

    #if os(iOS)
        if UIApplication.shared.applicationState == .background {
            // we will wait until we come back to the foregound
            // if we try we fail (could solve with bgtask, but why bother?)
            return
        }
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
                    !repoIds.contains($0)
                }.map {
                    api.request(path: "/repositories/\($0)")
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
                AppDelegate.shared.subscriptionManager.hasVerifiedReceipt = $0.1
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
            self.fetching = false
        }.done {
            self.hooks = $0
            self.delegate?.enrollmentsManagerDidUpdate(self, expandTree: false)
        }.catch {
            self.delegate?.enrollmentsManager(self, error: $0)
        }
    }

    //FIXME enroll() is not using this anymore
    private var installing: Set<Int> = [] {
        didSet {
            updateFetching()
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
                self.enrollments.formUnion(Set(enrollRepoIds).subtracting(failedRepoIds))
            case API.Enroll.Error.hookCreationFailed(let failedNodes):
                self.enrollments.formUnion(enrollRepoIds)
                self.hooks.formUnion(Set(hookTargets).subtracting(failedNodes))
            default:
                break
            }
            throw error
        }.done {
            if willEnroll {
                self.hooks.formUnion(hookTargets)
                self.enrollments.formUnion(enrollRepoIds)
            } else {
                self.enrollments.subtract(enrollRepoIds)
            }
        }.ensure {
            self.delegate?.enrollmentsManagerDidUpdate(self, expandTree: false)
        }
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

private func fetchEnrollments(token: String) -> Promise<(Set<Int>, Bool)> {
    var rq = URLRequest(.subscribe)
    rq.addValue(token, forHTTPHeaderField: "Authorization")
    return firstly {
        URLSession.shared.dataTask(.promise, with: rq).validate()
    }.map { data, rsp -> (Set<Int>, Bool) in
        let subs = Set(try JSONDecoder().decode([Int].self, from: data))
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
