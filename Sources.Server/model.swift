import PerfectSQLite
import Foundation
import PromiseKit

private let dbPath = "./db.sqlite"

class DB {
    let db: SQLite

    init() throws {
        db = try SQLite(dbPath)
    }

    deinit {
        db.close()
    }

    /// returns dictionary of topicIds to tokens for the provided repo-full-name
    func tokens(for repoId: Int) throws -> [String: [String]] {
        let sql = """
            SELECT id, topic
            FROM tokens
            INNER JOIN subscriptions ON subscriptions.user_id = tokens.user_id
            WHERE subscriptions.repo_id = :1
            """

        var results: [String: [String]] = [:]

        try db.forEachRow(statement: sql, doBindings: {
            try $0.bind(position: 1, repoId)
        }, handleRow: { statement, row in
            let token = statement.columnText(position: 0)
            let topic = statement.columnText(position: 1)

            // PerfectSQLite sucks and returns "" for the error condition
            if !token.isEmpty, !topic.isEmpty {
                results[topic, default: []].append(token)
            }
        })

        return results
    }

    func allTokens() throws -> [String: [String]] {
        let sql = """
            SELECT id, topic
            FROM tokens
            """

        var results: [String: [String]] = [:]

        try db.forEachRow(statement: sql, handleRow: { statement, row in
            let token = statement.columnText(position: 0)
            let topic = statement.columnText(position: 1)

            // PerfectSQLite sucks and returns "" for the error condition
            if !token.isEmpty, !topic.isEmpty {
                results[topic, default: []].append(token)
            }
        })

        return results
    }

    func add(token: String, topic: String, userId: Int) throws {
        let sql = """
            INSERT INTO tokens (id, topic, user_id)
            VALUES (:1, :2, :3)
            """
        try db.execute(statement: sql) { stmt in
            try stmt.bind(position: 1, token)
            try stmt.bind(position: 2, topic)
            try stmt.bind(position: 3, userId)
        }
    }

    func add(subscriptions repoIds: [Int], userId: Int) throws {
        let values = repoIds.enumerated().map { x, _ in
            "(:\(x * 2 + 1), :\(x * 2 + 2))"
        }.joined(separator: ",")
        let sql = """
            INSERT INTO subscriptions (repo_id, user_id)
            VALUES \(values);
            """
        try db.execute(statement: sql) { stmt in
            for (x, repoId) in repoIds.enumerated() {
                try stmt.bind(position: x * 2 + 1, repoId)
                try stmt.bind(position: x * 2 + 2, userId)
            }
        }
    }

    func delete(subcsription repoId: Int, userId: Int) throws {
        let sql = """
            DELETE FROM subscriptions
            WHERE repo_id = :1 and user_id = :2
            """
        try db.execute(statement: sql)
    }

    func subscriptions(forUserId userId: Int) throws -> [Int] {
        let sql = """
            SELECT repo_id
            FROM subscriptions
            WHERE user_id = :1
            """

        var results: [Int] = []

        try db.forEachRow(statement: sql, doBindings: {
            try $0.bind(position: 1, userId)
        }, handleRow: { statement, row in
            let repoId = statement.columnInt(position: 0)
            results.append(repoId)
        })

        return results
    }
}
