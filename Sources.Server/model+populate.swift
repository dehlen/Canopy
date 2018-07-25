import PerfectSQLite

extension DB {
    private func create() throws {
        try db.execute(statement: """
            CREATE TABLE IF NOT EXISTS tokens (
                id STRING PRIMARY KEY NOT NULL,
                topic STRING NOT NULL,
                user_id INTEGER NOT NULL
            )
            """)
        try db.execute(statement: """
            CREATE TABLE IF NOT EXISTS subscriptions (
                repo_id INTEGER NOT NULL,
                user_id INTEGER NOT NULL,
                UNIQUE(repo_id, user_id)
            )
            """)
    }

    func populate() throws {
        try db.execute(statement: "DROP TABLE tokens")
        try create()

        let foo = UserDefaults.standard.object(forKey: "tokensDict") as? [String: [String: [String]]] ?? [:]
        for (userId, tokens) in foo {
            let userId = Int(userId)!
            for (topic, tokens) in tokens {
                for token in tokens {
                    do {
                        try add(token: token, topic: topic, userId: userId)
                    } catch PerfectSQLite.SQLiteError.Error(let code, let msg) {
                        guard code == 19 else { throw PerfectSQLite.SQLiteError.Error(code: code, msg: msg) }
                    }
                }
            }
            do {
                let subs = UserDefaults.standard.subs(for: userId)
                try add(subscriptions: subs, userId: userId)
            } catch PerfectSQLite.SQLiteError.Error(let code, let msg) {
                guard code == 19 else { throw PerfectSQLite.SQLiteError.Error(code: code, msg: msg) }
            }
        }
    }

}

import class Foundation.UserDefaults

private let subsKey = "subs"

private extension UserDefaults {

    func addSub(userId: Int, repoId: Int) {
        let uid = String(userId)
        var subs = object(forKey: subsKey) as? [String: [Int]] ?? [:]
        var ids = Set(subs[uid, default: []])
        ids.insert(repoId)
        subs[uid] = Array(ids)
        set(subs, forKey: subsKey)
    }

    func deleteSub(userId: Int, repoId: Int) {
        var subs = object(forKey: subsKey) as? [String: [Int]] ?? [:]
        let key = String(userId)
        guard var repos = subs[key] else { return }
        while let index = repos.firstIndex(of: repoId) {
            repos.remove(at: index)
        }
        subs[key] = repos
        set(subs, forKey: subsKey)
    }

    func addToken(_ deviceToken: String, forUserId uid: Int, forTopic topic: String) {
        let uid = String(uid)
        var dict = object(forKey: "tokensDict") as? [String: [String: [String]]] ?? [:]
        //   ^^user   ^^topic  ^^tokens
        var tokens = Set(dict[uid, default: [:]][topic, default: []])
        tokens.insert(deviceToken)
        dict[uid, default: [:]][topic] = Array(tokens)
        set(dict, forKey: "tokensDict")
    }

    /// returns dictionary of topic to tokens
    func tokens(forUserId uid: Int) -> [String: [String]] {
        let dict = object(forKey: "tokensDict") as? [String: [String: [String]]] ?? [:]
        //   ^^user   ^^topic  ^^tokens
        return dict[String(uid)] ?? [:]
    }

    func subs(for userId: Int) -> [Int] {
        let subs = object(forKey: subsKey) as? [String: [Int]] ?? [:]
        return subs[String(userId)] ?? []
    }

    /// returns dictionary of topic to tokens
    func tokens(for context: Context) -> [String: [String]] {
        let subs = object(forKey: subsKey) as? [String: [Int]] ?? [:]

        switch context {
        case .organization, .alert:
            let dict = object(forKey: "tokensDict") as? [String: [String: [String]]] ?? [:]
            let s = dict.values.flatMap{ $0 }
            let foo = Dictionary(s){ $0 + $1 }
            return foo
        case .repository(let id):
            let dicts = subs.compactMap { (userId, repoIds) in
                return repoIds.contains(id) ? Int(userId) : nil
                }.map {
                    tokens(forUserId: $0)
            }
            let s = dicts.flatMap{ $0 }
            return Dictionary(s) { $0 + $1 }
        }
    }
}
