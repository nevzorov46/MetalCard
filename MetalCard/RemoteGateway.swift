import Foundation

/// What the client needs from whatever is on the other end: the local actor in
/// `PaymentGateway`, or the Go service in `server/`.
protocol ChargeGateway: Sendable {
    func authorize(_ request: ChargeRequest, last4: String) async throws -> Receipt
}

extension PaymentGateway: ChargeGateway {}

/// Talks to `gatewayd` over HTTP. The idempotency key rides in a header, where the
/// gateway expects it; a dropped connection comes back as `.network`, which is the
/// one error the client is allowed to retry.
struct RemoteGateway: ChargeGateway {
    var baseURL: URL
    var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    func authorize(_ request: ChargeRequest, last4: String) async throws -> Receipt {
        var http = URLRequest(url: baseURL.appending(path: "v1/charges"))
        http.httpMethod = "POST"
        http.setValue(request.idempotencyKey.value, forHTTPHeaderField: "Idempotency-Key")
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.httpBody = try JSONEncoder().encode(Body(request, last4: last4))

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: http)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // A closed connection and a timeout are the same thing to the caller:
            // no answer came back, and the charge may or may not have happened.
            throw PaymentError.network
        }

        guard let http = response as? HTTPURLResponse else { throw PaymentError.network }
        let replayed = http.value(forHTTPHeaderField: "Idempotent-Replayed") == "true"

        switch http.statusCode {
        case 200:
            let charge = try JSONDecoder.gateway.decode(Charge.self, from: data)
            return charge.receipt(merchant: request.merchant, wasReplay: replayed)
        case 402:
            let charge = try JSONDecoder.gateway.decode(Charge.self, from: data)
            throw PaymentError.declined(charge.reason ?? "Declined")
        case 409:
            throw PaymentError.duplicate
        case 422:
            throw PaymentError.declined("This key was used with a different request")
        default:
            throw PaymentError.network
        }
    }

    // MARK: Wire format

    private struct Body: Encodable {
        let amount: Amount
        let merchant: String
        let last4: String

        init(_ request: ChargeRequest, last4: String) {
            amount = Amount(minor_units: request.amount.minorUnits,
                            currency: request.amount.currency.rawValue)
            merchant = request.merchant.name
            self.last4 = last4
        }
        struct Amount: Encodable {
            let minor_units: Int
            let currency: String
        }
    }

    private struct Charge: Decodable {
        let id: String
        let amount: Amount
        let last4: String
        let status: String
        let reason: String?
        let completed_at: Date

        struct Amount: Decodable {
            let minor_units: Int
            let currency: String
        }

        func receipt(merchant: Merchant, wasReplay: Bool) -> Receipt {
            Receipt(id: id,
                    amount: Money(minorUnits: amount.minor_units,
                                  currency: Currency(rawValue: amount.currency) ?? .sgd),
                    merchant: merchant,
                    last4: last4,
                    completedAt: completed_at,
                    wasReplay: wasReplay)
        }
    }
}

private extension JSONDecoder {
    static let gateway: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let parser = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            if let date = try? parser.parse(text) { return date }
            return try Date.ISO8601FormatStyle().parse(text)
        }
        return decoder
    }()
}
