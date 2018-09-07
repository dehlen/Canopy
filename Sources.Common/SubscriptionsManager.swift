import Foundation
import PromiseKit
import Dispatch

protocol SubscriptionsManagerDelegate: class {
    func subscriptionsManagerDidReset()
    func subscriptionsManager(_: SubscriptionsManager, isUpdating: Bool)
    func subscriptionsManager(_: SubscriptionsManager, append: [Repo])
    func subscriptionsManager(_: SubscriptionsManager, subscriptions: Set<Int>, hasReceipt: Bool)
    func subscriptionsManager(_: SubscriptionsManager, append: Set<Int>)
    func subscriptionsManager(_: SubscriptionsManager, error: Error)
}

class SubscriptionsManager {
    weak var delegate: SubscriptionsManagerDelegate? {
        didSet {
            if let delegate = delegate, token != nil {
                delegate.subscriptionsManagerDidReset()
                update()
            }
        }
    }

    /// github token
    var token: String? {
        didSet {
            guard token != oldValue, let delegate = delegate else { return }
            delegate.subscriptionsManagerDidReset()
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
        delegate?.subscriptionsManager(self, isUpdating: fetching || !installing.isEmpty)
    }

    enum E: Error {
        case noToken
    }

    func update() {
        dispatchPrecondition(condition: .onQueue(.main))

        guard !fetching else { return }

        guard let token = token else {
            delegate?.subscriptionsManager(self, error: E.noToken)
            return
        }

        let api = GitHubAPI(oauthToken: token)

        func repos() -> Promise<[Repo]> {
            var cum: [Repo] = []

            let fetchRepos = api.task(path: "/user/repos") { data in
                DispatchQueue.global().async(.promise) {
                    try JSONDecoder().decode([Repo].self, from: data)
                }.done { [weak self] in
                    guard let `self` = self else { return }
                    self.delegate?.subscriptionsManager(self, append: $0)
                    cum.append(contentsOf: $0)
                }
            }

            func stragglers(repos: [Repo], subs: Set<Int>) -> Promise<[Repo]> {
                let repoIds = Set(repos.map(\.id))
                return when(fulfilled: subs.filter { sub in
                    !repoIds.contains(sub)
                }.map {
                    api.request(path: "/repositories/\($0)")
                }.map {
                    URLSession.shared.dataTask(.promise, with: $0).validate()
                }).mapValues {
                    try JSONDecoder().decode(Repo.self, from: $0.data)
                }
            }

            return firstly {
                when(fulfilled: fetchRepos, fetchSubs(token: token)).map{ $1 }
            }.get {
                self.delegate?.subscriptionsManager(self, subscriptions: $0, hasReceipt: $1)
            }.then {
                stragglers(repos: cum, subs: $0.0)
            }.done {
                self.delegate?.subscriptionsManager(self, append: $0)
                cum.append(contentsOf: $0)
            }.map { _ in
                cum
            }
        }

        fetching = true

        firstly {
            repos()
        }.then {
            fetchInstallations(for: $0)
        }.done {
            self.delegate?.subscriptionsManager(self, append: $0)
        }.catch {
            self.delegate?.subscriptionsManager(self, error: $0)
        }.finally {
            self.fetching = false
        }
    }

    private var installing: Set<Int> = [] {
        didSet {
            updateFetching()
        }
    }

    func installWebhook(repo: Repo) {
        let node = repo.isPartOfOrganization
            ? Node.organization(repo.owner.login)
            : .init(repo)

        let id = repo.isPartOfOrganization
            ? repo.owner.id
            : repo.id

        guard !installing.contains(id) else {
            return
        }
        guard let token = token else {
            delegate?.subscriptionsManager(self, error: E.noToken)
            return
        }

        func createHook(for node: Node) throws -> Promise<Void> {
            var rq = URLRequest(.hook)
            rq.httpMethod = "POST"
            rq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            rq.setValue(token, forHTTPHeaderField: "Authorization")
            rq.httpBody = try JSONEncoder().encode(node)
            return URLSession.shared.dataTask(.promise, with: rq).validate().asVoid()
        }

        installing.insert(id)

        firstly {
            try createHook(for: node)
        }.done { _ in
            self.delegate?.subscriptionsManager(self, append: [id])
        }.catch {
            self.delegate?.subscriptionsManager(self, error: $0)
        }.finally {
            self.installing.remove(id)
        }
    }
}

private func fetchSubs(token: String) -> Promise<(Set<Int>, Bool)> {
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

private func fetchInstallations(for repos: [Repo]) -> Promise<Set<Int>> {
    let ids = Set(repos.map { repo in
        repo.isPartOfOrganization
            ? repo.owner.id
            : repo.id
    })

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
