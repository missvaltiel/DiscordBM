import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Response from HTTP executor - platform agnostic
public struct HTTPExecutorResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data?

    public init(statusCode: Int, headers: [String: String], body: Data?) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

/// Protocol for executing HTTP requests - allows swapping between URLSession and AsyncHTTPClient
public protocol HTTPExecutor: Sendable {
    func execute(
        url: String,
        method: String,
        headers: [String: String],
        body: Data?,
        timeoutSeconds: Double
    ) async throws -> HTTPExecutorResponse
}

/// URLSession-based HTTP executor for cross-platform support
public final class URLSessionHTTPExecutor: HTTPExecutor, @unchecked Sendable {
    public static let shared = URLSessionHTTPExecutor()

    private let session: URLSession

    public init(configuration: URLSessionConfiguration = .default) {
        self.session = URLSession(configuration: configuration)
    }

    public func execute(
        url: String,
        method: String,
        headers: [String: String],
        body: Data?,
        timeoutSeconds: Double
    ) async throws -> HTTPExecutorResponse {
        guard let requestURL = URL(string: url) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.timeoutInterval = timeoutSeconds

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let body = body {
            request.httpBody = body
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        // Convert headers to [String: String]
        var responseHeaders: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            if let keyString = key as? String, let valueString = value as? String {
                responseHeaders[keyString] = valueString
            }
        }

        return HTTPExecutorResponse(
            statusCode: httpResponse.statusCode,
            headers: responseHeaders,
            body: data
        )
    }
}
