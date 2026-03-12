import Foundation
import Logging
@preconcurrency import KimaKit

/// CLI client that connects to the kima daemon via Unix domain socket
public final class DaemonClient: Sendable {
    private let socketPath: String
    private let logger = Logger(label: "kima.daemon-client")

    public init(socketPath: String? = nil) {
        self.socketPath = socketPath ?? KimaPaths.daemonSocketFile.path(percentEncoded: false)
    }

    /// Check if the daemon is running
    public func isRunning() -> Bool {
        FileManager.default.fileExists(atPath: socketPath)
    }

    /// Send a JSON-RPC request to the daemon and return the response
    public func send(method: String, params: [String: JSONValue]? = nil) async throws -> JSONRPCResponse {
        // Connect to Unix domain socket
        let socket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else {
            throw DaemonClientError.connectionFailed("Failed to create socket")
        }
        defer { close(socket) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            throw DaemonClientError.connectionFailed("Socket path too long")
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr)
            pathBytes.withUnsafeBufferPointer { buf in
                raw.copyMemory(from: buf.baseAddress!, byteCount: buf.count)
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Foundation.connect(socket, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw DaemonClientError.connectionFailed("Cannot connect to daemon at \(socketPath)")
        }

        // Send request
        let request = JSONRPCRequest(id: 1, method: method, params: params)
        var requestData = try JSONEncoder().encode(request)
        requestData.append(0x0A) // newline delimiter

        let writeResult = requestData.withUnsafeBytes { buffer in
            Foundation.write(socket, buffer.baseAddress!, buffer.count)
        }
        guard writeResult == requestData.count else {
            throw DaemonClientError.writeFailed
        }

        // Read response
        var responseData = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 65536)
        defer { buffer.deallocate() }

        while true {
            let bytesRead = read(socket, buffer, 65536)
            if bytesRead <= 0 { break }
            responseData.append(buffer, count: bytesRead)
            if responseData.contains(0x0A) { break }
        }

        if let newlineIndex = responseData.firstIndex(of: 0x0A) {
            responseData = responseData[..<newlineIndex]
        }

        return try JSONDecoder().decode(JSONRPCResponse.self, from: responseData)
    }
}

public enum DaemonClientError: Error, LocalizedError {
    case connectionFailed(String)
    case writeFailed
    case notRunning

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return msg
        case .writeFailed: return "Failed to write to daemon"
        case .notRunning: return "Daemon is not running. Start it with 'kima machine start'"
        }
    }
}
