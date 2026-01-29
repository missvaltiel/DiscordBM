import DiscordCore
import DiscordModels
import Foundation

extension MultipartEncodable {
    /// Encodes the multipart payload into a Data blob and the boundary string.
    /// Returns `nil` if there are no files to be encoded.
    @usableFromInline
    func encodeMultipart() throws -> (data: Data, boundary: String)? {
        guard let files = self.files, !files.isEmpty else { return nil }

        let boundary = MultipartConfiguration.boundary
        var data = Data()

        // 1. Handle the JSON payload
        // Discord usually wants the JSON in a field called "payload_json"
        if Self.rawEncodable {
            // Rare case: Some endpoints want the fields flat in the multipart form
            // This is harder to do manually without a reflection-based encoder,
            // but for now, we'll assume standard Discord behavior.
            throw MultipartError.rawEncodableNotSupportedYet
        } else {
            let jsonEncoder = DiscordGlobalConfiguration.encoder
            let jsonData = try jsonEncoder.encode(self)

            data.appendLine("--\(boundary)")
            data.appendLine("Content-Disposition: form-data; name=\"payload_json\"")
            data.appendLine("Content-Type: application/json")
            data.appendLine()
            data.append(jsonData)
            data.appendLine()
        }

        // 2. Handle Files
        for (index, file) in files.enumerated() {
            data.appendLine("--\(boundary)")
            data.appendLine("Content-Disposition: form-data; name=\"files[\(index)]\"; filename=\"\(file.filename)\"")
            data.appendLine("Content-Type: \(file.type ?? "application/octet-stream")")
            data.appendLine()
            data.append(file.data)
            data.appendLine()
        }

        // 3. Close the body
        data.appendLine("--\(boundary)--")

        return (data, boundary)
    }
}

@usableFromInline
enum MultipartConfiguration {
    @usableFromInline
    static let boundary: String = {
        let random1 = (0..<5).map { _ in Int.random(in: 0..<10) }.map { "\($0)" }.joined()
        let random2 = (0..<5).map { _ in Int.random(in: 0..<10) }.map { "\($0)" }.joined()
        return random1 + "discordbm" + random2
    }()
}

/// Simple error for unsupported edge cases
enum MultipartError: Error {
    case rawEncodableNotSupportedYet
}

/// Helper to make the manual builder readable
extension Data {
    fileprivate mutating func appendLine(_ string: String = "") {
        if let data = (string + "\r\n").data(using: .utf8) {
            self.append(data)
        }
    }
}

// Original code when using MultipartKit
// private let allocator = ByteBufferAllocator()

// extension MultipartEncodable {
//     /// Encodes the multipart payload into a buffer.
//     /// Returns `nil` if there are no multipart data to be encoded,
//     /// in which case this should be sent as JSON.
//     /// Throws encoding errors.
//     @usableFromInline
//     func encodeMultipart() throws -> ByteBuffer? {
//         guard let files = self.files, !files.isEmpty else { return nil }

//         var buffer = allocator.buffer(capacity: 1_024)

//         if Self.rawEncodable {
//             try FormDataEncoder().encode(
//                 self,
//                 boundary: MultipartConfiguration.boundary,
//                 into: &buffer
//             )
//         } else {
//             let payload = MultipartEncodingContainer(
//                 payload_json: try .init(from: self),
//                 files: files
//             )
//             try FormDataEncoder().encode(
//                 payload,
//                 boundary: MultipartConfiguration.boundary,
//                 into: &buffer
//             )
//         }

//         return buffer
//     }
// }

// @usableFromInline
// enum MultipartConfiguration {
//     @usableFromInline
//     static let boundary: String = {
//         let random1 = (0..<5).map { _ in Int.random(in: 0..<10) }.map { "\($0)" }.joined()
//         let random2 = (0..<5).map { _ in Int.random(in: 0..<10) }.map { "\($0)" }.joined()
//         return random1 + "discordbm" + random2
//     }()
// }

// struct MultipartEncodingContainer: Encodable {

//     struct JSON: Encodable, MultipartPartConvertible {
//         let buffer: ByteBuffer

//         var multipart: MultipartPart? {
//             MultipartPart(
//                 headers: ["Content-Type": "application/json"],
//                 body: buffer
//             )
//         }

//         init?(multipart: MultipartPart) {
//             self.buffer = multipart.body
//         }

//         init<E: Encodable>(from encodable: E) throws {
//             let data = try DiscordGlobalConfiguration.encoder.encode(encodable)
//             self.buffer = .init(data: data)
//         }

//         func encode(to encoder: any Encoder) throws {
//             let data = Data(buffer: buffer, byteTransferStrategy: .noCopy)
//             var container = encoder.singleValueContainer()
//             try container.encode(data)
//         }
//     }

//     var payload_json: JSON
//     var files: [RawFile]
// }
