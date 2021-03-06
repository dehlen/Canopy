import PerfectCURL
import PerfectHTTP
import Foundation
import PromiseKit
import Roots

//TODO make app allow notify button after this 200 too
//TODO barf if we get the same receipt id for multiple users:
//  suggests that different github accounts have signed in to the same iCloud account
//  or maybe this should be fine? Eg. user has two github accounts on two different devices?

private enum E: Error, HTTPStatusCodable {
    case invalidAppleValidatorStatus(Int)
    case couldNotEncodeReceipt
    case noExpiryDate
    case expired
    case trySandboxVerifyReceipt

    var httpStatusCode: Int {
        switch self {
        case .noExpiryDate:
            return HTTPResponseStatus.paymentRequired.code
        case .invalidAppleValidatorStatus:
            return HTTPResponseStatus.badRequest.code
        case .couldNotEncodeReceipt:
            return HTTPResponseStatus.internalServerError.code
        case .expired:
            return HTTPResponseStatus.forbidden.code
        case .trySandboxVerifyReceipt:
            alert(message: "State machine error")
            return HTTPResponseStatus.internalServerError.code
        }
    }
}

//TODO local validation would be more robust
// but why do Apple recommend this then?

func receiptHandler(request rq: HTTPRequest) throws -> Promise<Void> {

    print()
    print("/receipt")

    guard let token = rq.header(.authorization) else {
        throw HTTPResponseError(status: .forbidden, description: "")
    }
    guard let receipt = rq.postBodyString else {
        throw HTTPResponseError(status: .badRequest, description: "Empty POST body")
    }
    let sku = rq.header(.custom(name: "X-Platform"))

    func persist() -> Promise<Int> {
        return firstly {
            GitHubAPI(oauthToken: token).me()
        }.map { me -> Int in
            var fn = String(me.id)
            if let sku = sku { fn += ".\(sku)" }
            let url = URL(fileURLWithPath: "../receipts").appendingPathComponent(fn)
            try receipt.write(to: url, atomically: true, encoding: .utf8)
            return me.id
        }
    }

    let userId = persist()
    return firstly {
        validateReceipt(userId: userId, sku: sku, receipt: receipt)
    }.recover { error in
        if case E.expired = error, let userId = userId.value {
            _ = try? DB().remove(receiptForUserId: userId)
        }
        throw error
    }
}

private extension URLRequest {
    init(receipt: String, isProduction: Bool) throws {
        let urlString = isProduction
            ? "https://buy.itunes.apple.com/verifyReceipt"
            : "https://sandbox.itunes.apple.com/verifyReceipt"

        let json = [
            "receipt-data": receipt,
            "password": "2367a7d022cb4e05a047a624891fa13f"
        ]

        self.init(url: URL(string: urlString)!)
        httpMethod = "POST"
        httpBody = try JSONSerialization.data(withJSONObject: json)
        setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
}

private struct Response1: Decodable {
    let status: Int
}

struct ReceiptInfo: Decodable {
    let status: Int
    let environment: String
//    let receipt: Receipt
    let latest_receipt_info: [LatestReceiptInfo]?
//    let latest_receipt: String
//    let pending_renewal_info: [PendingRenewalInfo]

//    struct Receipt: Decodable {
//        let receipt_type: String
//        let adam_id: Int
//        let app_item_id: Int
//        let bundle_id: String
//        let application_version: String
//        let download_id: Int
//        let version_external_identifier: Int
//        let receipt_creation_date_ms: Date
//        let request_date_ms: Date
//        let original_purchase_date_ms: Date
//        let original_application_version: String
//        let in_app: [InApp]
//
//        struct InApp: Decodable {
//            let quantity: String
//            let product_id: String
//            let transaction_id: String
//            let original_transaction_id: String
//            let purchase_date_ms: Date
//            let original_purchase_date_ms: Date
//            let expires_date_ms: Date
//            let web_order_line_item_id: String
//            let is_trial_period: String
//            let is_in_intro_offer_period: String
//        }
//    }
    struct LatestReceiptInfo: Decodable {
        let quantity: String
        let product_id: String
        let transaction_id: String
        let original_transaction_id: String
        let purchase_date_ms: Date
        let original_purchase_date_ms: Date
        let expires_date_ms: Date
        let web_order_line_item_id: String
        let is_trial_period: String
        let is_in_intro_offer_period: String
    }
//    struct PendingRenewalInfo: Decodable {
//        let expiration_intent: String?
//        let auto_renew_product_id: String
//        let original_transaction_id: String
//        let is_in_billing_retry_period: String?
//        let product_id: String
//        let auto_renew_status: String
//    }
}

private extension ReceiptInfo {
    func expiryDate() throws -> Date {
        guard let receipt = latest_receipt_info, let expires = receipt.map(\.expires_date_ms).max() else {
            throw E.noExpiryDate
        }
        return expires
    }
}

func validateReceipt(userId: Promise<Int>, sku: String?, receipt: String) -> Promise<Void> {
    return firstly {
        when(fulfilled: userId, verifyReceipt(sku: sku, receipt: receipt))
    }.map { userId, response in
        (userId, try response.expiryDate())
    }.done { userId, expiry in
        guard try DB().add(receiptForUserId: userId, expires: expiry) else {
            throw E.expired
        }
    }
}

private func verifyReceipt(sku: String?, receipt: String) -> Promise<ReceiptInfo> {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let dateString = try container.decode(String.self)
        guard let ms = TimeInterval(dateString) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected String containing Int")
        }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    func validate(_ data: Data) throws -> ReceiptInfo {
        let status = try decoder.decode(Response1.self, from: data).status
        switch status {
        case 0:
            return try decoder.decode(ReceiptInfo.self, from: data)
        case 21007:
            throw E.trySandboxVerifyReceipt
        case 21000, 21002, 21003, 21004, 21008:
            throw HTTPResponseError(status: .internalServerError, description: "\(status)")
        case 21005, 21100..<21200:
            throw HTTPResponseError(status: .badGateway, description: "Apple’s receipt validator is unavailable")
        case 21006, 21010:
            throw E.expired
        default:
            throw E.invalidAppleValidatorStatus(status)
        }
    }

    func go(prod: Bool) throws -> Promise<Data> {
        let password = sku == "iOS"
            ? "e863c3bf604e4de7867e95c86249ef25"
            : "2367a7d022cb4e05a047a624891fa13f"
        let url = prod
            ? "https://buy.itunes.apple.com/verifyReceipt"
            : "https://sandbox.itunes.apple.com/verifyReceipt"
        let json_ = [
            "receipt-data": receipt,
            "password": password
        ]
        let json = try JSONSerialization.data(withJSONObject: json_)
        let rsp = try CURLRequest(url, .failOnError, .addHeader(.contentType, "application/json"), .postData([UInt8](json))).perform()
        return .value(Data(rsp.bodyBytes))
    }

    return firstly {
        try go(prod: true)
    }.map {
        try validate($0)
    }.recover { error -> Promise<ReceiptInfo> in
        if case E.trySandboxVerifyReceipt = error {
            return try go(prod: false).map(validate)
        }
        throw error
    }
}
