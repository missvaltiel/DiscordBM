import CompressNIO
import Foundation
import Logging
import NIOCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// WebSocket message types for URLSession-based WebSocket
public enum URLSessionWSMessage: Sendable {
    case text(String)
    case binary(ByteBuffer)
}

/// Close frame information
public struct URLSessionWSCloseFrame: Sendable {
    public let closeCode: URLSessionWSCloseCode
    public let reason: String?

    public init(closeCode: URLSessionWSCloseCode, reason: String? = nil) {
        self.closeCode = closeCode
        self.reason = reason
    }
}

/// WebSocket close codes compatible with NIOWebSocket.WebSocketErrorCode
public enum URLSessionWSCloseCode: Sendable, Equatable {
    case normalClosure
    case goingAway
    case protocolError
    case unsupportedData
    case noStatusReceived
    case abnormalClosure
    case invalidFramePayloadData
    case policyViolation
    case messageTooBig
    case mandatoryExtensionMissing
    case internalServerError
    case tlsHandshakeFailure
    case unexpectedServerError
    case unknown(Int)

    init(from urlSessionCode: URLSessionWebSocketTask.CloseCode) {
        switch urlSessionCode {
        case .normalClosure: self = .normalClosure
        case .goingAway: self = .goingAway
        case .protocolError: self = .protocolError
        case .unsupportedData: self = .unsupportedData
        case .noStatusReceived: self = .noStatusReceived
        case .abnormalClosure: self = .abnormalClosure
        case .invalidFramePayloadData: self = .invalidFramePayloadData
        case .policyViolation: self = .policyViolation
        case .messageTooBig: self = .messageTooBig
        case .mandatoryExtensionMissing: self = .mandatoryExtensionMissing
        case .internalServerError: self = .internalServerError
        case .tlsHandshakeFailure: self = .tlsHandshakeFailure
        @unknown default: self = .unknown(urlSessionCode.rawValue)
        }
    }

    init(rawValue: Int) {
        switch rawValue {
        case 1000: self = .normalClosure
        case 1001: self = .goingAway
        case 1002: self = .protocolError
        case 1003: self = .unsupportedData
        case 1005: self = .noStatusReceived
        case 1006: self = .abnormalClosure
        case 1007: self = .invalidFramePayloadData
        case 1008: self = .policyViolation
        case 1009: self = .messageTooBig
        case 1010: self = .mandatoryExtensionMissing
        case 1011: self = .internalServerError
        case 1015: self = .tlsHandshakeFailure
        default: self = .unknown(rawValue)
        }
    }

    var urlSessionCode: URLSessionWebSocketTask.CloseCode {
        switch self {
        case .normalClosure: return .normalClosure
        case .goingAway: return .goingAway
        case .protocolError: return .protocolError
        case .unsupportedData: return .unsupportedData
        case .noStatusReceived: return .noStatusReceived
        case .abnormalClosure: return .abnormalClosure
        case .invalidFramePayloadData: return .invalidFramePayloadData
        case .policyViolation: return .policyViolation
        case .messageTooBig: return .messageTooBig
        case .mandatoryExtensionMissing: return .mandatoryExtensionMissing
        case .internalServerError: return .internalServerError
        case .tlsHandshakeFailure: return .tlsHandshakeFailure
        case .unexpectedServerError: return .internalServerError
        case .unknown(let code): return URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .abnormalClosure
        }
    }
}

/// Outbound writer for URLSession WebSocket
public actor URLSessionWSOutboundWriter {
    private let task: URLSessionWebSocketTask
    private let logger: Logger
    private var isClosed = false

    init(task: URLSessionWebSocketTask, logger: Logger) {
        self.task = task
        self.logger = logger
    }

    public func write(_ frame: URLSessionWSOutboundFrame) async throws {
        guard !isClosed else {
            throw URLSessionWSError.connectionClosed
        }

        let message: URLSessionWebSocketTask.Message
        switch frame {
        case .text(let string):
            message = .string(string)
        case .binary(let buffer):
            message = .data(Data(buffer: buffer))
        case .custom(let fin, let opcode, let data):
            // URLSession doesn't support custom frames directly
            // Map to appropriate message type based on opcode
            if opcode == .text {
                if let string = String(data: Data(buffer: data), encoding: .utf8) {
                    message = .string(string)
                } else {
                    message = .data(Data(buffer: data))
                }
            } else {
                message = .data(Data(buffer: data))
            }
        }

        try await task.send(message)
    }

    public func close(_ code: URLSessionWSCloseCode, reason: String?) async throws {
        guard !isClosed else { return }
        isClosed = true

        let reasonData = reason?.data(using: .utf8)
        task.cancel(with: code.urlSessionCode, reason: reasonData)
    }
}

/// Outbound frame types
public enum URLSessionWSOutboundFrame: Sendable {
    case text(String)
    case binary(ByteBuffer)
    case custom(fin: Bool, opcode: URLSessionWSOpcode, data: ByteBuffer)
}

/// WebSocket opcodes
public enum URLSessionWSOpcode: UInt8, Sendable {
    case continuation = 0
    case text = 1
    case binary = 2
    case close = 8
    case ping = 9
    case pong = 10

    init?(encodedWebSocketOpcode value: UInt8) {
        self.init(rawValue: value)
    }
}

/// WebSocket errors
public enum URLSessionWSError: Error, Sendable {
    case connectionClosed
    case invalidURL
    case connectionFailed(any Error)
    case decompressFailed(any Error)
}

/// Inbound message stream with zlib decompression support
public struct URLSessionWSInboundStream: AsyncSequence {
    public typealias Element = URLSessionWSMessage

    private let task: URLSessionWebSocketTask
    private let decompressor: ZlibDecompressor?
    private let logger: Logger

    init(task: URLSessionWebSocketTask, decompressor: ZlibDecompressor?, logger: Logger) {
        self.task = task
        self.decompressor = decompressor
        self.logger = logger
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(task: task, decompressor: decompressor, logger: logger)
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private let task: URLSessionWebSocketTask
        private let decompressor: ZlibDecompressor?
        private let logger: Logger

        init(task: URLSessionWebSocketTask, decompressor: ZlibDecompressor?, logger: Logger) {
            self.task = task
            self.decompressor = decompressor
            self.logger = logger
        }

        public mutating func next() async throws -> URLSessionWSMessage? {
            do {
                let message = try await task.receive()

                switch message {
                case .string(let text):
                    return .text(text)

                case .data(let data):
                    var buffer = ByteBuffer(data: data)

                    // If we have a decompressor and the data looks compressed, decompress it
                    if let decompressor = decompressor, !data.isEmpty {
                        do {
                            let decompressed = try decompress(buffer: &buffer, using: decompressor)
                            return .binary(decompressed)
                        } catch {
                            logger.warning(
                                "Decompression failed, returning raw data",
                                metadata: [
                                    "error": .string(String(describing: error))
                                ]
                            )
                            return .binary(ByteBuffer(data: data))
                        }
                    }

                    return .binary(buffer)

                @unknown default:
                    return nil
                }
            } catch {
                // Connection closed or error
                if (error as NSError).code == 57 {  // Socket not connected
                    return nil
                }
                throw error
            }
        }

        private func decompress(buffer: inout ByteBuffer, using decompressor: ZlibDecompressor) throws -> ByteBuffer {
            let compressedBytes = buffer.readableBytes
            var output = ByteBuffer()
            output.reserveCapacity(Swift.max(4096, compressedBytes * 8))

            while true {
                do {
                    try decompressor.inflate(from: &buffer, to: &output)
                    return output
                } catch let error as CompressNIOError where error == .bufferOverflow {
                    output.reserveCapacity(minimumWritableBytes: output.readableBytes)
                    continue
                }
            }
        }
    }
}

/// URLSession-based WebSocket client for Discord gateway
public final class URLSessionWSClient: @unchecked Sendable {

    /// Connect to a WebSocket URL
    public static func connect(
        url urlString: String,
        useCompression: Bool = true,
        logger: Logger
    ) async throws -> (
        inbound: URLSessionWSInboundStream,
        outbound: URLSessionWSOutboundWriter,
        task: URLSessionWebSocketTask,
        decompressor: ZlibDecompressor?
    ) {
        guard let url = URL(string: urlString) else {
            throw URLSessionWSError.invalidURL
        }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)

        // Create decompressor if compression is enabled
        let decompressor: ZlibDecompressor?
        if useCompression {
            decompressor = try ZlibDecompressor(algorithm: .zlib, windowSize: 15)
        } else {
            decompressor = nil
        }

        task.resume()

        let inbound = URLSessionWSInboundStream(task: task, decompressor: decompressor, logger: logger)
        let outbound = URLSessionWSOutboundWriter(task: task, logger: logger)

        return (inbound, outbound, task, decompressor)
    }
}

/// Extension to get close frame from task
extension URLSessionWebSocketTask {
    var currentCloseFrame: URLSessionWSCloseFrame? {
        guard let closeCode = self.closeCode as URLSessionWebSocketTask.CloseCode?,
            closeCode.rawValue != -1
        else {
            return nil
        }
        let reason = self.closeReason.flatMap { String(data: $0, encoding: .utf8) }
        return URLSessionWSCloseFrame(
            closeCode: URLSessionWSCloseCode(from: closeCode),
            reason: reason
        )
    }
}
