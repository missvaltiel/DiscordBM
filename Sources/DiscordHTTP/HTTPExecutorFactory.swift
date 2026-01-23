import Foundation

/// Factory for creating platform-appropriate HTTP executors
public enum HTTPExecutorFactory {
    /// Creates the default HTTP executor (URLSession-based, works on all platforms)
    public static func createDefault() -> any HTTPExecutor {
        return URLSessionHTTPExecutor.shared
    }

    /// Creates a URLSession-based executor with custom configuration
    public static func createURLSession(
        configuration: URLSessionConfiguration = .default
    ) -> URLSessionHTTPExecutor {
        return URLSessionHTTPExecutor(configuration: configuration)
    }
}
