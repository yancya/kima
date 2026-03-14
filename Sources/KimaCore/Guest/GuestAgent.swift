import Foundation
import Virtualization
import Logging
@preconcurrency import KimaKit

/// Connects to the guest agent via vsock and sends JSON-RPC requests
@MainActor
public final class GuestAgentClient: Sendable {
    private let socketDevice: VZVirtioSocketDevice
    private let port: UInt32 = 1024
    private let logger = Logger(label: "kima.guest-agent")

    public init(socketDevice: VZVirtioSocketDevice) {
        self.socketDevice = socketDevice
    }

    /// Wait for the guest agent to become available, retrying with backoff
    public func waitForAgent(timeout: TimeInterval = 60) async throws {
        let start = Date()
        var delay: UInt64 = 500_000_000 // 0.5s

        while Date().timeIntervalSince(start) < timeout {
            do {
                let conn = try await socketDevice.connect(toPort: port)
                close(conn.fileDescriptor)
                logger.info("Guest agent is ready")
                return
            } catch {
                logger.info("Waiting for guest agent: \(error.localizedDescription)")
                try await Task.sleep(nanoseconds: delay)
                delay = min(delay * 2, 5_000_000_000) // max 5s
            }
        }
        throw GuestAgentError.timeout
    }

    /// Send a JSON-RPC request to the guest agent
    public func send(method: String, params: [String: JSONValue]? = nil) async throws -> JSONRPCResponse {
        // Connect on MainActor (VZVirtioSocketDevice requires it)
        let connection = try await socketDevice.connect(toPort: port)
        let fd = connection.fileDescriptor

        let request = JSONRPCRequest(id: 1, method: method, params: params)
        let requestData = try JSONEncoder().encode(request)

        // Move blocking I/O to a background thread
        let log = logger
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                // Write request followed by newline
                var dataToSend = requestData
                dataToSend.append(0x0A)

                log.info("Writing \(dataToSend.count) bytes to fd \(fd)")
                let written = dataToSend.withUnsafeBytes { buffer in
                    Darwin.write(fd, buffer.baseAddress!, buffer.count)
                }
                log.info("Wrote \(written) bytes (expected \(dataToSend.count))")
                guard written == dataToSend.count else {
                    Darwin.close(fd)
                    continuation.resume(throwing: GuestAgentError.writeFailed)
                    return
                }

                // Read response
                log.info("Reading response from fd \(fd)...")
                var responseData = Data()
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 65536)
                defer {
                    buffer.deallocate()
                    Darwin.close(fd)
                }

                while true {
                    let bytesRead = Darwin.read(fd, buffer, 65536)
                    log.info("Read \(bytesRead) bytes")
                    if bytesRead <= 0 { break }
                    responseData.append(buffer, count: bytesRead)
                    if responseData.contains(0x0A) { break }
                }

                log.info("Response data: \(responseData.count) bytes")

                // Trim trailing newline
                if let newlineIndex = responseData.firstIndex(of: 0x0A) {
                    responseData = responseData[..<newlineIndex]
                }

                do {
                    let response = try JSONDecoder().decode(JSONRPCResponse.self, from: responseData)
                    continuation.resume(returning: response)
                } catch {
                    log.error("Decode error: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

public enum GuestAgentError: Error, LocalizedError {
    case timeout
    case writeFailed
    case connectionFailed

    public var errorDescription: String? {
        switch self {
        case .timeout: return "Timed out waiting for guest agent"
        case .writeFailed: return "Failed to write to guest agent"
        case .connectionFailed: return "Failed to connect to guest agent"
        }
    }
}
