import PerfectHTTP
import Foundation
import PromiseKit
import Roots

//TODO supplement subscribe response to include if private is ok
//TODO make app allow notify button after this 200 too
//TODO barf if we get the same receipt id for multiple users:
//  suggests that different github accounts have signed in to the same iCloud account
//  or maybe this should be fine? Eg. user has two github accounts on two different devices?

private enum E: Error {
    case invalidAppleValidatorStatus(Int)
    case couldNotEncodeReceipt
    case noExpiryDate
    case expired
}

//TODO local validation would be more robust
// but why do Apple recommend this then?

func receiptHandler(request rq: HTTPRequest, _ response: HTTPResponse) {
    do {
        guard let token = rq.header(.authorization) else {
            return response.completed(status: .forbidden)
        }

        let receipt = try rq.decode(Receipt.self)

        func persist() -> Promise<Int> {
            return firstly {
                GitHubAPI(oauthToken: token).me()
            }.map { me -> Int in
                guard let data = Data(base64Encoded: receipt.base64) else {
                    throw E.couldNotEncodeReceipt
                }
                let url = URL(fileURLWithPath: "../receipts").appendingPathComponent(String(me.id))
                try data.write(to: url)
                return me.id
            }
        }

        func validate() -> Promise<Response> {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)
                guard let ms = TimeInterval(dateString) else {
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected String containing Int")
                }
                return Date(timeIntervalSince1970: ms / 1000)
            }
            return firstly {
                URLSession.shared.dataTask(.promise, with: try URLRequest(receipt)).validate()
            }.map {
                try decoder.decode(Response.self, from: $0.data)
            }
        }

        firstly {
            when(fulfilled: persist(), validate())
        }.map { userId, response in
            (userId, try handle(response: response, forUserId: userId))
        }.done { userId, expiry in
            try DB().add(receiptForUserId: userId, expires: expiry)
            response.completed()
        }.catch { error in
            response.appendBody(string: error.legibleDescription)
            response.completed(status: .badRequest)
        }

    } catch {
        response.appendBody(string: error.legibleDescription)
        response.completed(status: .badRequest)
    }
}

private extension URLRequest {
    init(_ receipt: Receipt) throws {
        let urlString: String
        if receipt.isProduction {
            urlString = "https://buy.itunes.apple.com/verifyReceipt"
        } else {
            urlString = "https://sandbox.itunes.apple.com/verifyReceipt"
        }

        let json = [
            "receipt-data": receipt.base64,
            "password": "2367a7d022cb4e05a047a624891fa13f"
        ]

        self.init(url: URL(string: urlString)!)
        httpMethod = "POST"
        httpBody = try JSONSerialization.data(withJSONObject: json)
        setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
}

private struct Response: Decodable {
    let status: Int
    let environment: String
    let receipt: Receipt
    let latest_receipt_info: [LatestReceiptInfo]
    let latest_receipt: String
    let pending_renewal_info: [PendingRenewalInfo]

    struct Receipt: Decodable {
        let receipt_type: String
        let adam_id: Int
        let app_item_id: Int
        let bundle_id: String
        let application_version: String
        let download_id: Int
        let version_external_identifier: Int
        let receipt_creation_date_ms: Date
        let request_date_ms: Date
        let original_purchase_date_ms: Date
        let original_application_version: String
        let in_app: [InApp]

        struct InApp: Decodable {
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

    }
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
    struct PendingRenewalInfo: Decodable {
        let expiration_intent: String?
        let auto_renew_product_id: String
        let original_transaction_id: String
        let is_in_billing_retry_period: String?
        let product_id: String
        let auto_renew_status: String
    }
}

/// - Returns: expiration date
private func handle(response: Response, forUserId userId: Int) throws -> Date {
    switch response.status {
    case 0:
        guard let expires = response.latest_receipt_info.map(\.expires_date_ms).max() else {
            throw E.noExpiryDate
        }
        return expires
    case 21000, 21002, 21003, 21004, 21008, 21007:
        throw HTTPResponseError(status: .internalServerError, description: "\(response.status)")
    case 21005, 21100..<21200:
        throw HTTPResponseError(status: .badGateway, description: "Apple’s receipt validator is unavailable")
    case 21006, 21010:
        try DB().remove(receiptForUserId: userId)
        throw E.expired
    default:
        throw E.invalidAppleValidatorStatus(response.status)
    }
}
