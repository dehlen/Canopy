import PerfectSQLite
import Foundation

private let dbPath = "../db.sqlite"

private enum CryptoError: Error {
    case couldNotDecrypt(forUserId: Int)
}

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

    struct Foo {
        var confs: [APNSConfiguration: [String]]
        let userId: Int
    }

    func tokens(forRepoId repoId: Int) throws -> [String: Foo] {

        // we intend do a HEAD request for the repo with each oauth-token
        // and we’re assuming that 99% will return 200, thus we may as
        // well fetch the resulting device-tokens in the same query

        let sql = """
            SELECT tokens.id, tokens.topic, tokens.production, auths.token, auths.salt, tokens.user_id
            FROM tokens
            INNER JOIN auths ON auths.user_id = tokens.user_id
            INNER JOIN subscriptions ON subscriptions.user_id = tokens.user_id
            WHERE subscriptions.repo_id = :1
            """

        var results: [String: Foo] = [:]

        try db.forEachRow(statement: sql, doBindings: {
            try $0.bind(position: 1, repoId)
        }, handleRow: { statement, row in
            let apnsDeviceToken = statement.columnText(position: 0)
            let topic = statement.columnText(position: 1)
            let production = statement.columnInt(position: 2) != 0
            let encryptedOAuthToken: [UInt8] = statement.columnIntBlob(position: 3)
            let encryptionSalt: [UInt8] = statement.columnIntBlob(position: 4)
            let userId = statement.columnInt(position: 5)

            guard let oauthToken = decrypt(encryptedOAuthToken, salt: encryptionSalt) else {
                return alert(message: "Failed decrypting token for a user. We don’t know which")
            }

            // PerfectSQLite sucks and returns "" for the error condition
            if !apnsDeviceToken.isEmpty, !topic.isEmpty, !encryptedOAuthToken.isEmpty, !encryptionSalt.isEmpty {
                let conf = APNSConfiguration(topic: topic, isProduction: production)
                results[oauthToken, default: Foo(confs: [:], userId: userId)].confs[conf, default: []].append(apnsDeviceToken)
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
            REPLACE INTO tokens (id, topic, user_id, production)
            VALUES (:1, :2, :3, :4)
            """
        try db.execute(statement: sql) { stmt in
            try stmt.bind(position: 1, apnsToken)
            try stmt.bind(position: 2, topic)
            try stmt.bind(position: 3, userId)
            try stmt.bind(position: 4, production ? 1 : 0)
        }
    }

    func delete(apnsDeviceToken: String) throws {
        let sql = "DELETE from tokens WHERE id = :1"
        try db.execute(statement: sql) { stmt in
            try stmt.bind(position: 1, apnsDeviceToken)
        }
    }

    func add(oauthToken: String, userId: Int) throws {

        // we could easily have multiple tokens per user-id
        // since they could be using many devices. Or… perhaps
        // github vends the same tokens per oauth-app?

        guard let (encryptedToken, encryptionSalt) = encrypt(oauthToken) else {
            throw CryptoError.couldNotDecrypt(forUserId: userId)
        }
        let sql = """
            REPLACE INTO auths (token, user_id, salt)
            VALUES (:1, :2, :3)
            """
        try db.execute(statement: sql) {
            try $0.bind(position: 1, [UInt8](encryptedToken))
            try $0.bind(position: 2, userId)
            try $0.bind(position: 3, encryptionSalt)
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

    func delete(subscription repoId: Int, userId: Int) throws {
        let sql = """
            DELETE FROM subscriptions
            WHERE repo_id = :1 and user_id = :2
            """
        try db.execute(statement: sql) { stmt in
            try stmt.bind(position: 1, repoId)
            try stmt.bind(position: 2, userId)
        }
    }

    func delete(subscriptions repoIds: [Int], userId: Int) throws {
        try db.doWithTransaction {
            //TODO inefficient
            for id in repoIds {
                try delete(subscription: id, userId: userId)
            }
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

    func add(receiptForUserId userId: Int, expires: Date) throws {
        let sql = """
            REPLACE INTO receipts (user_id, expires)
            VALUES (:1, :2)
            """
        try db.execute(statement: sql) {
            try $0.bind(position: 1, userId)
            try $0.bind(position: 2, Formatter.iso8601.string(from: expires))
        }
    }

    func isReceiptValid(forUserId userId: Int) throws -> Bool {
        if userId == 58962 { return true }  //mxcl

        let sql = """
            SELECT expires
            FROM receipts
            WHERE user_id = \(userId)
            """
        var dateString: String?
        try db.forEachRow(statement: sql) { statement, row in
            dateString = statement.columnText(position: 0)
        }
        if let dateString = dateString, let expiryDate = Formatter.iso8601.date(from: dateString), Date() < expiryDate {
            return true
        } else {
            return false
        }
    }

    func remove(receiptForUserId userId: Int) throws {
        try db.execute(statement: """
            DELETE FROM receipts
            WHERE userId = \(userId)
            """)
    }
}

struct APNSConfiguration: Hashable {
    let topic: String
    let isProduction: Bool
}

private extension Formatter {
    static var iso8601: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return formatter
    }
}
