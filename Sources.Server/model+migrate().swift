import PerfectSQLite
import Foundation

#if false
extension DB {
    private func create() throws {
        try db.execute(statement: """
            CREATE TABLE tokens (
                id STRING PRIMARY KEY,
                topic STRING NOT NULL,
                user_id INTEGER NOT NULL,
                production INTEGER NOT NULL
            )
            """)
        try db.execute(statement: """
            CREATE TABLE subscriptions (
                repo_id INTEGER NOT NULL,
                user_id INTEGER NOT NULL,
                UNIQUE(repo_id, user_id)
            )
            """)
//        try db.execute(statement: """
//            CREATE TABLE auths (
//                user_id INTEGER PRIMARY KEY,
//                token BLOB NOT NULL,
//                salt BLOB UNIQUE NOT NULL
//            )
//            """)
//        try db.execute(statement: """
//            CREATE TABLE receipts (
//                user_id INTEGER PRIMARY KEY,
//                expires STRING NOT NULL
//            )
//            """)
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
        try db.forEachRow(statement: "SELECT id, topic, user_id, production FROM tokens") { stmt, _ in
            tokens.append(.init(id: stmt.columnText(position: 0), topic: stmt.columnText(position: 1), user_id: stmt.columnInt(position: 2), production: stmt.columnInt(position: 3) != 0))
        }
        var subscriptions: [Subscription] = []
        try db.forEachRow(statement: "SELECT repo_id, user_id FROM subscriptions") { stmt, _ in
            subscriptions.append(.init(repo_id: stmt.columnInt(position: 0), user_id: stmt.columnInt(position: 1)))
        }

        try dropAllTables()
        try create()

        for token in tokens {
            try add(apnsToken: token.id, topic: token.topic, userId: token.user_id, production: token.production)
        }
        for sub in subscriptions {
            try add(subscriptions: [sub.repo_id], userId: sub.user_id)
        }
    }
}
#endif
