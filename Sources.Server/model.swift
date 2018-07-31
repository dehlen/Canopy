import PerfectSQLite
import CommonCrypto
import Foundation
import PromiseKit

private let dbPath = "../db.sqlite"

class DB {
    let db: SQLite

    init() throws {
        db = try SQLite(dbPath)
    }

    deinit {
        db.close()
    }

    enum E: Error {
        case tokenNotFound(user: Int)
    }

    func backup() throws {
        let fmtr = DateFormatter()
        fmtr.dateFormat = "YYYYMMdd-HHmmss"
        let filename = "../db.backup." + fmtr.string(from: Date()) + ".sqlite"

        let src = URL(fileURLWithPath: dbPath)
        let dst = URL(fileURLWithPath: filename)
        try FileManager.default.copyItem(at: src, to: dst)

        print("Backed up:", dst.path)
    }

    func apnsTokens(for repoId: Int) throws -> [APNSConfiguration: [String]] {
        let sql = """
            SELECT id, topic, production
            FROM tokens
            INNER JOIN subscriptions ON subscriptions.user_id = tokens.user_id
            WHERE subscriptions.repo_id = :1
            """

        var results: [APNSConfiguration: [String]] = [:]

        try db.forEachRow(statement: sql, doBindings: {
            try $0.bind(position: 1, repoId)
        }, handleRow: { statement, row in
            let token = statement.columnText(position: 0)
            let topic = statement.columnText(position: 1)
            let production = statement.columnInt(position: 2) != 0

            // PerfectSQLite sucks and returns "" for the error condition
            if !token.isEmpty, !topic.isEmpty {
                results[APNSConfiguration(topic: topic, isProduction: production), default: []].append(token)
            }
        })

        return results
    }

    func mxcl() throws -> [APNSConfiguration: [String]] {
        let sql = """
            SELECT id, topic, production
            FROM tokens
            WHERE user_id = 58962
            """

        var results: [APNSConfiguration: [String]] = [:]

        try db.forEachRow(statement: sql, handleRow: { statement, row in
            let token = statement.columnText(position: 0)
            let topic = statement.columnText(position: 1)
            let production = statement.columnInt(position: 2) != 0
            results[APNSConfiguration(topic: topic, isProduction: production), default: []].append(token)
        })

        return results
    }

    func allAPNsTokens() throws -> [APNSConfiguration: [String]] {
        let sql = """
            SELECT id, topic, production
            FROM tokens
            """

        var results: [APNSConfiguration: [String]] = [:]

        try db.forEachRow(statement: sql, handleRow: { statement, row in
            let token = statement.columnText(position: 0)
            let topic = statement.columnText(position: 1)
            let production = statement.columnInt(position: 2) != 0
            results[APNSConfiguration(topic: topic, isProduction: production), default: []].append(token)
        })

        return results
    }

    func add(apnsToken: String, topic: String, userId: Int, production: Bool) throws {
        let sql = """
            INSERT INTO tokens (id, topic, user_id, production)
            VALUES (:1, :2, :3, :4)
            """
        try db.execute(statement: sql) { stmt in
            try stmt.bind(position: 1, apnsToken)
            try stmt.bind(position: 2, topic)
            try stmt.bind(position: 3, userId)
            try stmt.bind(position: 4, production ? 1 : 0)
        }
    }

    func delete(token: String) throws {
        let sql = "DELETE from tokens WHERE id = :1"
        try db.execute(statement: sql) { stmt in
            try stmt.bind(position: 1, token)
        }
    }

    func add(oauthToken: String, userId: Int) throws {
        let (encryptedToken, encryptionSalt) = try encrypt(oauthToken)
        let sql = """
            INSERT INTO auth (token, user_id, salt)
            VALUES (:1, :2, :3)
            """
        try db.execute(statement: sql) {
            try $0.bind(position: 1, [UInt8](encryptedToken))
            try $0.bind(position: 2, userId)
            try $0.bind(position: 3, encryptionSalt)
        }
    }

    func oauthToken(user userId: Int) throws -> String {
        let sql = """
            SELECT FROM auth (token, salt)
            WHERE user_id = \(userId)
            """
        var token: Data?
        var salt: String?
        try db.forEachRow(statement: sql) { stmt, _ in
            var bytes: [UInt8] = stmt.columnIntBlob(position: 0)
            token = Data(bytes: &bytes, count: bytes.count)
            salt = stmt.columnText(position: 1)
        }
        if let token = token, let salt = salt {
            return try decrypt(token, salt: salt)
        } else {
            throw E.tokenNotFound(user: userId)
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
        try db.execute(statement: sql) { stmt in
            try stmt.bind(position: 1, repoId)
            try stmt.bind(position: 2, userId)
        }
    }

    func delete(repository repoId: Int) throws {
        let sql = """
            DELETE FROM subscriptions
            WHERE repo_id = :1
            """
        try db.execute(statement: sql) { stmt in
            try stmt.bind(position: 1, repoId)
        }
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

struct APNSConfiguration: Hashable {
    let topic: String
    let isProduction: Bool
}
