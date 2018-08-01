import PerfectNotifications

extension APNSConfiguration {
    private var configurationName: String {
        return isProduction
            ? NotificationPusher.productionConfigurationName
            : NotificationPusher.sandboxConfigurationName
    }

    func send(_ notificationItems: [APNSNotificationItem], to tokens: [String]) {
        let pusher = NotificationPusher(apnsTopic: topic)
        pusher.expiration = .relative(30)

        print("sent to:", tokens.count, "tokens to production:", isProduction, "(\(topic))")

        pusher.pushAPNS(configurationName: configurationName, deviceTokens: tokens, notificationItems: notificationItems) { responses in
            for (index, response) in responses.enumerated() {
                do {
                    let token = tokens[index]
                    switch response.status {
                    case .ok:    //200
                        continue
                    case .badRequest:  //400
                        if response.jsonObjectBody["reason"] as? String == "BadDeviceToken" {
                            fallthrough
                        }
                    case .gone:        //410
                        print("Deleting token due to \(response.status)")
                        try DB().delete(apnsDeviceToken: tokens[index])
                    default:
                        print("APNs:", response, token)
                    }
                } catch {
                    print(#function, error)
                }
            }
        }
    }
}

func alert(message: String, function: StaticString = #function) {
    print(function, message)

    guard let confs = try? DB().mxcl() else {
        return
    }
    for (conf, tokens) in confs {
        conf.send([.alertBody(message)], to: tokens)
    }
}
