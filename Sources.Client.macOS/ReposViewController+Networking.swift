import PromiseKit
import AppKit

extension ReposViewController {

    @objc func fetch() {
        dispatchPrecondition(condition: .onQueue(.main))

        guard !fetching else {
            return
        }
        guard let token = creds?.token else {
            repos = []
            hooked = []
            subscribed = []
            outlineView.reloadData()
            performSegue(withIdentifier: "SignIn", sender: self)
            return
        }

        fetching = true
        repos = []
        subscribed = []

        let fetchRepos = GitHubAPI(oauthToken: token).task(path: "/user/repos") { data in
            DispatchQueue.global().async(.promise) {
                try JSONDecoder().decode([Repo].self, from: data)
            }.done {
                self.repos.append(contentsOf: $0)
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

        firstly {
            when(fulfilled: fetchRepos, fetchSubs(token: token))
        }.done {
            //TODO may have subs that github doesn't list due to token bug, need to show them!
            let (subs, hasReceipt) = $1
            self.subscribed = subs
            self.hasVerifiedReceipt = hasReceipt
            self.outlineView.reloadData()
            self.outlineView.expandItem(nil, expandChildren: true)
        }.then {
            fetchInstallations(for: self.nodes.compactMap(convert))
        }.map {
            Set($0.compactMap(unconvert))
        }.done {
            self.hooked = $0
        }.catch {
            alert($0)
        }.finally {
            self.fetching = false
        }
    }

    @IBAction private func installWebhook(sender: NSButton) {
        guard let token = creds?.token else {
            return alert(message: "No GitHub auth token", title: "Unexpected Error")
        }
        guard let selectedItem = selectedItem else {
            return
        }

        //TODO don't allow toggling during activity (NOTE need to store
        //  that we are installing-hooks for this node in case of switch-back-forth)
        //TODO UI feedback for activity

        func createHook(for node: Node) -> Promise<Node> {
            do {
                var rq = URLRequest(canopy: "hook")
                rq.httpMethod = "POST"
                rq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                rq.setValue(token, forHTTPHeaderField: "Authorization")
                rq.httpBody = try JSONEncoder().encode(node)
                return URLSession.shared.dataTask(.promise, with: rq).validate().map{ _ in node }
            } catch {
                return Promise(error: error)
            }
        }

        notifyButton.isEnabled = false
        installWebhookButton.isEnabled = false

        let types: [Node]
        switch selectedItem {
        case .organization(let login):
            types = [.organization(login)]
        case .repo(let repo):
            types = [Node(repo)]
        case .user(let login):
            types = rootedRepos[login]!.map(Node.init).filter{ hooked.contains($0) }
        }

        firstly {
            when(resolved: types.map(createHook))
        }.done { results in
            var allGood = true
            for result in results {
                switch result {
                case .fulfilled(let node):
                    self.hooked.insert(node)
                case .rejected(let error):
                    allGood = false
                    alert(error)
                    if selectedItem == self.selectedItem {
                        self.installWebhookButton.isEnabled = true
                    }
                }
            }
            if allGood, selectedItem == self.selectedItem {
                self.notifyButton.isEnabled = true
            }
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
                self.repos.append(repo)
                self.outlineView.reloadData()
            }
        }.catch {
            alert($0)
        }
    }
}

private func fetchSubs(token: String) -> Promise<(Set<Int>, Bool)> {
    var rq = URLRequest(canopy: "/subscribe")
    rq.addValue(token, forHTTPHeaderField: "Authorization")
    return firstly {
        URLSession.shared.dataTask(.promise, with: rq).validate()
    }.map { data, rsp -> (Set<Int>, Bool) in
        let subs = Set(try JSONDecoder().decode([Int].self, from: data))
        let verifiedReceipt = (rsp as? HTTPURLResponse)?.allHeaderFields["Upgrade"] as? String == "true"
        return (subs, verifiedReceipt)
    }
}


func fetchInstallations(for nodes: [Int]) -> Promise<Set<Int>> {
    //FIXME need to store ids in Node really, ids are stable, names are not
    var cc = URLComponents(canopy: "/hook")
    cc.queryItems = nodes.map{ URLQueryItem(name: "ids[]", value: String($0)) }
    let rq = URLRequest(url: cc.url!)
    return firstly {
        URLSession.shared.dataTask(.promise, with: rq).validate()
    }.map {
        try JSONDecoder().decode([Int].self, from: $0.data)
    }.map(Set.init)
}
