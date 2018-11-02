
//func receiptStatusUpdateHandler(request rq: HTTPRequest) throws -> Promise<Void> {
//
//    struct Request: Decodable {
//        let environment: Environment
//        let notificationType: NotificationType
//        let password: String
//        let autoRenewStatus: Bool
//
//        enum Environment: String, Decodable {
//            case sandbox = "Sandbox"
//            case production = "PROD"
//        }
//
//        enum NotificationType {
//            case initialBuy
//            case cancel(Date, webOrderLineItemId: String)
//            case renewal(interactive: Bool, ReceiptInfo, ExpirationIntent)
//            case didChangeRenewalPreference
//        }
//
//        enum ExpirationIntent: Int {
//            case cancelled
//            case billingError
//            case customerRefusedPriceIncrease
//            case productUnavailable
//            case unknownError
//        }
//
//        enum CodingKeys: String, CodingKey {
//            case environment
//            case notification_type
//            case password
//            case original_transaction_id
//            case cancellation_date
//            case web_order_line_item_id
//            case latest_receipt
//            case latest_receipt_info
//            case latest_expired_receipt
//            case latest_expired_receipt_info
//            case auto_renew_status
//            case auto_renew_adam_id
//            case auto_renew_product_id
//            case expiration_intent
//        }
//
//        init(from decoder: Decoder) throws {
//            let container = try decoder.container(keyedBy: CodingKeys.self)
//            environment = try container.decode(Environment.self, forKey: .environment)
//
//            let type = try container.decode(String.self, forKey: .notification_type)
//            switch type {
//            case "INITIAL_BUY":
//                fatalError()
//            case "CANCEL":
//                let date = try container.decode(Date.self, forKey: .cancellation_date)
//            case "RENEWAL":
//                fatalError()
//            case "INTERACTIVE_RENEWAL":
//                fatalError()
//            case "DID_CHANGE_RENEWAL_PREF":
//                fatalError()
//            default:
//                throw DecodingError.dataCorruptedError(forKey: CodingKeys.notificationType, in: container, debugDescription: "Invalid type")
//            }
//        }
//    }

//    fatalError()
//}
