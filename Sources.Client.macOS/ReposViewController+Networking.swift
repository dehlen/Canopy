import PromiseKit
import AppKit

extension ReposViewController {
    @objc func fetch() {
        dispatchPrecondition(condition: .onQueue(.main))

        guard !fetching else {
            return
        }
        guard let token = creds?.token else {
            repos = .init()
            hooked = []
            subscribed = []
            outlineView.reloadData()
            performSegue(withIdentifier: "SignIn", sender: self)
            return
        }

        fetching = true
        repos = .init()
        subscribed = []

        let api = GitHubAPI(oauthToken: token)

        let fetchRepos = api.task(path: "/user/repos") { data in
            DispatchQueue.global().async(.promise) {
                try JSONDecoder().decode([Repo].self, from: data)
            }.done {
                self.repos.insert(contentsOf: $0)
                self.outlineView.reloadData()
            }
        }

        func convert(_ node: Node) -> Int? {
            switch node {
            case .organization(let login):
                for repo in repos where repo.owner.login == login {
                    return repo.owner.id
                }
            case .repository(let login, let name):
                for repo in repos where repo.owner.login == login && repo.name == name {
                    return repo.id
                }
            }
            return nil
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

        func stragglers() -> Promise<[Repo]> {
            let repoIds = Set(repos.map(\.id))
            let stragglers = subscribed.filter { sub in
                !repoIds.contains(sub)
            }.map {
                api.request(path: "/repositories/\($0)")
            }.map {
                URLSession.shared.dataTask(.promise, with: $0).validate()
            }
            print(#function, stragglers)
            return when(fulfilled: stragglers).mapValues {
                try JSONDecoder().decode(Repo.self, from: $0.data)
            }
        }

        firstly {
            when(fulfilled: fetchRepos, fetchSubs(token: token))
        }.done {
            self.subscribed = $1
            self.outlineView.reloadData()
            self.outlineView.expandItem(nil, expandChildren: true)
        }.then {
            stragglers()
        }.done {
            self.repos.insert(contentsOf: $0)
            self.outlineView.reloadData()
        }.then {
            fetchInstallations(for: self.nodes.compactMap(convert))
        }.map {
            Set($0.compactMap(unconvert))
        }.done {
            self.hooked = $0
            self.outlineView.reloadData()
        }.catch {
            alert($0)
        }.finally {
            self.fetching = false
        }
    }

    func add(repoFullName full_name: String) {
        guard full_name.contains("/"), let token = creds?.token else {
            return
        }

        //TODO ust refresh hook information, maybe it's been days and the user knows the data is stale!
        func fetchInstallation(for repo: Repo) -> Promise<Node?> {
            var node: Node {
                if repo.isPartOfOrganization {
                    return .organization(repo.owner.login)
                } else {
                    return .repository(repo.owner.login, repo.name)
                }
            }
            var id: Int {
                switch node {
                case .organization:
                    return repo.owner.id
                case .repository:
                    return repo.id
                }
            }
            return firstly {
                fetchInstallations(for: [id])
            }.map {
                $0.isEmpty ? nil : node
            }
        }

        let rq = GitHubAPI(oauthToken: token).request(path: "/repos/\(full_name)")
        firstly {
            URLSession.shared.dataTask(.promise, with: rq).validate()
        }.map {
            try JSONDecoder().decode(Repo.self, from: $0.data)
        }.then { repo in
            fetchInstallation(for: repo).done {
                if let node = $0 {
                    self.hooked.insert(node)
                }
                self.repos.insert(repo)
                self.outlineView.reloadData()
            }
        }.catch {
            alert($0)
        }
    }

    @IBAction private func toggle(sender: NSButton) {

        //TODO don't allow toggling during activity (NOTE need to store
        //  that we are installing-hooks for this node in case of switch-back-forth)
        //TODO UI feedback for activity

        //TODO make new endpoint that installs webhook SECOND so user is pinged after subbing
        // change ping text to subscription verified or GitHub sent confirmation payload or something

        // probably therefore make Node decodable
        // error therefore will be complicated ?

        guard let selectedItem = selectedItem else {
            return
        }
        let subscribe = sender.state == .on
        let restoreState = state(for: selectedItem).nsControlStateValue

        if subscribe, !hasVerifiedReceipt, requiresReceipt(item: selectedItem) {
            sender.state = restoreState
            paymentPrompt()
        } else if let token = creds?.token {
            let ids: [Int]
            switch selectedItem {
            case .organization(let login), .user(let login):
                ids = rootedRepos[login]!.map(\.id)
            case .repo(let repo):
                ids = [repo.id]
            }

            var work: Promise<Void> {
                var rq = URLRequest(.enroll)
                rq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                rq.setValue(token, forHTTPHeaderField: "Authorization")

                if subscribe {
                    rq.httpMethod = "POST"

                    let nodes: [Node]
                    switch selectedItem {
                    case .organization(let login):
                        nodes = [.organization(login)]
                    case .repo(let repo):
                        //NOTE really should handle this serverside, but whatever, we control
                        // everything and abuse is super unlikely
                        if repo.isPartOfOrganization {
                            nodes = [.organization(repo.owner.login)]
                        } else {
                            nodes = [.init(repo)]
                        }
                    case .user(let login):
                        nodes = rootedRepos[login]!.map(Node.init)
                    }

                    return DispatchQueue.global().async(.promise) {
                        rq.httpBody = try JSONEncoder().encode(API.Enroll(createHooks: nodes, enrollRepoIds: ids))
                    }.then {
                        URLSession.shared.dataTask(.promise, with: rq).httpValidate()
                    }.done { _ in
                        self.subscribed.formUnion(ids)
                        self.hooked.formUnion(nodes)
                    }.recover { error in
                        switch error {
                        case API.Enroll.Error.noClearance(let failedRepoIds):
                            self.subscribed.formUnion(Set(ids).subtracting(failedRepoIds))
                        case API.Enroll.Error.hookCreationFailed(let failedNodes):
                            self.subscribed.formUnion(ids)
                            self.hooked.formUnion(Set(nodes).subtracting(failedNodes))
                        default:
                            break
                        }
                        throw error
                    }
                } else {
                    rq.httpMethod = "DELETE"

                    return DispatchQueue.global().async(.promise) {
                        rq.httpBody = try JSONEncoder().encode(API.Unenroll(repoIds: ids))
                    }.then {
                        URLSession.shared.dataTask(.promise, with: rq).validate()
                    }.done { _ in
                        self.subscribed.subtract(ids)
                    }
                }
            }

            sender.isEnabled = false

            work.catch {
                if selectedItem == self.selectedItem {
                    sender.state = restoreState
                }
                alert($0)
            }.finally {
                if selectedItem == self.selectedItem {
                    sender.isEnabled = true
                    sender.allowsMixedState = false  // will be either on or off at this point
                }
                // some items maybe succeeded and some failed, so always do these, even if error
                self.outlineView.reloadData()
                self.outlineViewSelectionDidChange(Notification(name: .NSAppleEventManagerWillProcessFirstEvent))
            }

        } else {
            sender.state = restoreState
            alert(message: "No GitHub auth token", title: "Unexpected Error")
        }
    }
}

private func fetchSubs(token: String) -> Promise<Set<Int>> {
    var rq = URLRequest(.subscribe)
    rq.addValue(token, forHTTPHeaderField: "Authorization")
    return firstly {
        URLSession.shared.dataTask(.promise, with: rq).validate()
    }.map {
        Set(try JSONDecoder().decode([Int].self, from: $0.data))
    }
}

func fetchInstallations(for nodes: [Int]) -> Promise<Set<Int>> {
    //FIXME need to store ids in Node really, ids are stable, names are not
    var cc = URLComponents(.hook)
    cc.queryItems = nodes.map{ URLQueryItem(name: "ids[]", value: String($0)) }
    let rq = URLRequest(url: cc.url!)
    return firstly {
        URLSession.shared.dataTask(.promise, with: rq).validate()
    }.map {
        try JSONDecoder().decode([Int].self, from: $0.data)
    }.map(Set.init)
}
