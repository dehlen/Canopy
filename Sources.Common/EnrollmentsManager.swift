import Foundation
import PromiseKit
import Dispatch
#if os(iOS)
import UIKit
#endif

protocol EnrollmentsManagerDelegate: class {
    func enrollmentsManager(_: EnrollmentsManager, isUpdating: Bool)
    func enrollmentsManagerDidUpdate(_: EnrollmentsManager)
    func enrollmentsManager(_: EnrollmentsManager, error: Error)
}

class EnrollmentsManager {
    private(set) var hooks: Set<Int> = []
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
                delegate.enrollmentsManagerDidUpdate(self)
                update()
            }
        }
    }

    /// github token
    var token: String? {
        didSet {
            guard token != oldValue, let delegate = delegate, token != nil else { return }
            delegate.enrollmentsManagerDidUpdate(self)
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
                #if targetEnvironment(simulator)
                    let newRepos = $0.filter { $0.full_name != "lucidhq/fulcrum-pulse" }
                    self.repos.formUnion(newRepos)
                #else
                    self.repos.formUnion($0)
                #endif
                    self.delegate?.enrollmentsManagerDidUpdate(self)
                }
            }

            func stragglers() -> Promise<[Repo]> {
                let repoIds = Set(self.repos.map(\.id))
                return when(fulfilled: self.enrollments.filter {
                    !repoIds.contains($0)
                }.map {
                    api.request(path: "/repositories/\($0)")
                }.map {
                    URLSession.shared.dataTask(.promise, with: $0).validate()
                }).mapValues {
                    try JSONDecoder().decode(Repo.self, from: $0.data)
                }
            }

            return firstly {
                when(fulfilled: fetchRepos, fetchEnrollments(token: token)).map{ $1 }
            }.done {
                AppDelegate.shared.subscriptionManager.hasVerifiedReceipt = $0.1
                self.enrollments = $0.0
                self.delegate?.enrollmentsManagerDidUpdate(self)
            }.then {
                stragglers()
            }.done {
                self.repos.formUnion($0)
                self.delegate?.enrollmentsManagerDidUpdate(self)
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
            self.delegate?.enrollmentsManagerDidUpdate(self)
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

    func enroll(repo: Repo) throws -> Promise<Void> {
        guard let token = token else {
            throw Error.noToken
        }

        let willEnroll = !enrollments.contains(repo.id)

        if willEnroll, repo.private, !AppDelegate.shared.subscriptionManager.hasVerifiedReceipt {
            throw Error.paymentRequired
        }

        let hookTarget = !repo.isPartOfOrganization ? Node(repo) : .organization(repo.owner.login)
        let hookId = !repo.isPartOfOrganization ? repo.id : repo.owner.id

        var rq = URLRequest(.enroll)
        rq.httpMethod = willEnroll ? "POST" : "DELETE"
        rq.httpBody = willEnroll
            ? try JSONEncoder().encode(API.Enroll(createHooks: [hookTarget], enrollRepoIds: [repo.id]))
            : try JSONEncoder().encode(API.Unenroll(repoIds: [repo.id]))
        rq.addValue("application/json", forHTTPHeaderField: "Content-Type")
        rq.addValue(token, forHTTPHeaderField: "Authorization")

        return firstly {
            URLSession.shared.dataTask(.promise, with: rq).httpValidate().map{ _ in willEnroll }
        }.recover { error -> Promise<Bool> in
            switch error {
            case API.Enroll.Error.noClearance/*(let failedRepoIds)*/:
                break
            case API.Enroll.Error.hookCreationFailed/*(let failedNodes)*/:
                self.enrollments.insert(repo.id)
            default:
                break
            }
            throw error
        }.done { enrolled in
            if enrolled {
                self.hooks.insert(hookId)
                self.enrollments.insert(repo.id)
            } else {
                self.enrollments.remove(repo.id)
            }
            self.delegate?.enrollmentsManagerDidUpdate(self)
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

private func fetchInstallations(for repos: SortedSet<Repo>) -> Promise<Set<Int>> {
    let ids = repos.map {
        $0.isPartOfOrganization
            ? $0.owner.id
            : $0.id
    }

    //FIXME need to store ids in Node really, ids are stable, names are not
    var cc = URLComponents(.hook)
    cc.queryItems = ids.map{ URLQueryItem(name: "ids[]", value: String($0)) }
    let rq = URLRequest(url: cc.url!)
    return firstly {
        URLSession.shared.dataTask(.promise, with: rq).validate()
    }.map {
        try JSONDecoder().decode([Int].self, from: $0.data)
    }.map(Set.init)
}
