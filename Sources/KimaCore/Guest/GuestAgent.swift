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
                logger.debug("Waiting for guest agent: \(error.localizedDescription)")
                try await Task.sleep(nanoseconds: delay)
                delay = min(delay * 2, 5_000_000_000) // max 5s
            }
        }
        throw GuestAgentError.timeout
    }

    /// Send a JSON-RPC request to the guest agent
    public func send(method: String, params: [String: JSONValue]? = nil) async throws -> JSONRPCResponse {
        let connection = try await socketDevice.connect(toPort: port)
        let fd = connection.fileDescriptor

        let request = JSONRPCRequest(id: 1, method: method, params: params)
        let requestData = try JSONEncoder().encode(request)

        // Write request followed by newline
        var dataToSend = requestData
        dataToSend.append(0x0A) // newline

        let written = dataToSend.withUnsafeBytes { buffer in
            write(fd, buffer.baseAddress!, buffer.count)
        }
        guard written == dataToSend.count else {
            close(fd)
            throw GuestAgentError.writeFailed
        }

        // Read response
        var responseData = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 65536)
        defer {
            buffer.deallocate()
            close(fd)
        }

        while true {
            let bytesRead = read(fd, buffer, 65536)
            if bytesRead <= 0 { break }
            responseData.append(buffer, count: bytesRead)
            // Check for newline delimiter
            if responseData.contains(0x0A) { break }
        }

        // Trim trailing newline
        if let newlineIndex = responseData.firstIndex(of: 0x0A) {
            responseData = responseData[..<newlineIndex]
        }

        return try JSONDecoder().decode(JSONRPCResponse.self, from: responseData)
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
