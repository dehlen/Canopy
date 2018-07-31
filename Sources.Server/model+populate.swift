import PerfectSQLite
import Foundation

extension DB {
    func create() throws {
        try db.execute(statement: """
            CREATE TABLE IF NOT EXISTS auths (
                user_id INTEGER UNIQUE NOT NULL,
                token BLOB NOT NULL,
                salt STRING UNIQUE NOT NULL
            )
            """)
    }
}

#if false
extension DB {
    private func create() throws {
        try db.execute(statement: """
            CREATE TABLE IF NOT EXISTS tokens (
                id STRING PRIMARY KEY NOT NULL,
                topic STRING NOT NULL,
                user_id INTEGER NOT NULL,
                production INTEGER NOT NULL
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

    private func dropAllTables() throws {
        try db.execute(statement: "DROP TABLE tokens")
        try db.execute(statement: "DROP TABLE subscriptions")
    }

    func migrate() throws {
        try backup()

        struct Token {
            let id: String
            let topic: String
            let user_id: Int
            let production: Bool
        }
        struct Subscription {
            let repo_id: Int
            let user_id: Int
        }

        var tokens: [Token] = []
        try db.forEachRow(statement: "SELECT id, topic, user_id FROM tokens") { stmt, _ in
            tokens.append(.init(id: stmt.columnText(position: 0), topic: stmt.columnText(position: 1), user_id: stmt.columnInt(position: 2), production: stmt.columnInt(position: 3) != 0))
        }
        var subscriptions: [Subscription] = []
        try db.forEachRow(statement: "SELECT repo_id, user_id FROM subscriptions") { stmt, _ in
            subscriptions.append(.init(repo_id: stmt.columnInt(position: 0), user_id: stmt.columnInt(position: 1)))
        }

        try dropAllTables()
        try create()

        for token in tokens {
            try add(token: token.id, topic: token.topic, userId: token.user_id, production: token.production)
        }
        for sub in subscriptions {
            try add(subscriptions: [sub.repo_id], userId: sub.user_id)
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
#endif
