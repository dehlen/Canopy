import PerfectCSQLite3
import Roots

typealias TokenSelect = (repoId: Int, ignoreUserId: Int, event: Event)

extension DB {

    func apnsTokens(for conf: TokenSelect) throws -> [APNSConfiguration: [String]] {

        //TODO probably would be better to do the event_mask check as initial separate query

        let sql = """
            SELECT id, topic, production, tokens.user_id, subscriptions.event_mask
            FROM tokens
            INNER JOIN subscriptions ON subscriptions.user_id = tokens.user_id
            WHERE subscriptions.repo_id = :1
            AND (subscriptions.event_mask & :2) == :2
            """

        var results: [APNSConfiguration: [String]] = [:]

        try db.forEachRow(statement: sql, doBindings: {
            try $0.bind(position: 1, conf.repoId)
            try $0.bind(position: 2, conf.event.optionValue)
        }, handleRow: { statement, row in
            let userId = statement.columnInt(position: 3)
            guard userId != conf.ignoreUserId else { return }

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

    func apnsTokens(forUserIds uids: [Int]) throws -> [APNSConfiguration: [String]] {
        let uidstrs = uids.map(String.init).joined(separator: ",")
        let sql = """
            SELECT id, topic, production
            FROM tokens
            WHERE user_id IN (\(uidstrs))
            """

        var results: [APNSConfiguration: [String]] = [:]

        try db.forEachRow(statement: sql) { statement, row in
            let token = statement.columnText(position: 0)
            let topic = statement.columnText(position: 1)
            let production = statement.columnInt(position: 2) != 0

            // PerfectSQLite sucks and returns "" for the error condition
            if !token.isEmpty, !topic.isEmpty {
                results[APNSConfiguration(topic: topic, isProduction: production), default: []].append(token)
            }
        }

        return results
    }

    struct Foo {
        var confs: [APNSConfiguration: [String]]
        let userId: Int
    }

    func tokens(for conf: TokenSelect) throws -> [String: Foo] {

        // we intend do a HEAD request for the repo with each oauth-token
        // and we’re assuming that 99% will return 200, thus we may as
        // well fetch the resulting device-tokens in the same query

        //TODO probably would be better to do the event_mask check as initial separate query

        let sql = """
            SELECT tokens.id, tokens.topic, tokens.production, auths.token, auths.salt, tokens.user_id, subscriptions.event_mask
            FROM tokens
            INNER JOIN auths ON auths.user_id = tokens.user_id
            INNER JOIN subscriptions ON subscriptions.user_id = tokens.user_id
            WHERE subscriptions.repo_id = :1
            AND (subscriptions.event_mask & \(conf.event.optionValue)) == \(conf.event.optionValue)
            """

        var results: [String: Foo] = [:]

        try db.forEachRow(statement: sql, doBindings: {
            try $0.bind(position: 1, conf.repoId)
        }, handleRow: { statement, row in
            let userId = statement.columnInt(position: 5)
            guard userId != conf.ignoreUserId else { return }

            let apnsDeviceToken = statement.columnText(position: 0)
            let topic = statement.columnText(position: 1)
            let production = statement.columnInt(position: 2) != 0
            let encryptedOAuthToken: [UInt8] = statement.columnIntBlob(position: 3)
            let encryptionSalt: [UInt8] = statement.columnIntBlob(position: 4)


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
            WHERE user_id = \(Int.mxcl)
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

#if false
    //FIXME TODO WOAH MEMORY CONSUMPTION, ideally needs to be a lazy sequence
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
#endif
}

extension Int {
    static var mxcl: Int {
        return 58962
    }
    static var promiseKit: Int {
        return 18440563
    }
}
