import PerfectSQLite
import PromiseKit

private let dbPath = "./db.sqlite"

enum DB {
    static func create() throws {
        let db = try SQLite(dbPath)
        defer {
            db.close() // This makes sure we close our connection.
        }

        try db.execute(statement: """
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY NOT NULL
            )
            """)
        try db.execute(statement: """
            CREATE TABLE IF NOT EXISTS tokens (
                id STRING PRIMARY KEY NOT NULL,
                topic STRING NOT NULL,
                user_id INTEGER NOT NULL
            )
            """)
        try db.execute(statement: """
            CREATE TABLE IF NOT EXISTS subscriptions (
                id INTEGER PRIMARY KEY NOT NULL AUTOINCREMENT,
                repo STRING NOT NULL,
                user_id INTEGER NOT NULL
            )
            """)
    }

    /// returns dictionary of topicIds to tokens for the provided repo-full-name
    static func tokens(for repo: String) throws -> [String: String] {
        let db = try SQLite(dbPath)
        defer {
            db.close() // This makes sure we close our connection.
        }

        let sql = """
            SELECT id, topic
            FROM topics
            INNER JOIN users ON users.id = topics.user_id
            INNER JOIN subscriptions ON subscriptions.user_id = topics.user_id
            INNER JOIN subscriptions ON subscriptions.repo = :1
            """

        var results: [String: String] = [:]

        try db.forEachRow(statement: sql, doBindings: {
            try $0.bind(position: 1, repo)
        }, handleRow: { statement, row in
            let token = statement.columnText(position: 0)
            let topic = statement.columnText(position: 1)

            // PerfectSQLite sucks and returns "" for the error condition
            if !token.isEmpty, !topic.isEmpty {
                results[topic] = token
            }
        })

        return results
    }
}
