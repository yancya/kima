import Foundation
import Virtualization
import Logging
@preconcurrency import KimaKit

/// Unix domain socket server that runs in the daemon process.
/// Forwards JSON-RPC requests from CLI clients to the guest agent via vsock.
@MainActor
public final class DaemonServer {
    private let socketPath: String
    private let agentClient: GuestAgentClient
    private let logger = Logger(label: "kima.daemon-server")
    private var serverFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?

    public init(socketPath: String? = nil, agentClient: GuestAgentClient) {
        self.socketPath = socketPath ?? KimaPaths.daemonSocketFile.path(percentEncoded: false)
        self.agentClient = agentClient
    }

    /// Start listening on Unix domain socket
    public func start() throws {
        // Remove stale socket file
        unlink(socketPath)

        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            throw DaemonServerError.socketFailed
        }

        // Set non-blocking
        let flags = fcntl(serverFD, F_GETFL)
        _ = fcntl(serverFD, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(serverFD)
            throw DaemonServerError.pathTooLong
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr)
            pathBytes.withUnsafeBufferPointer { buf in
                raw.copyMemory(from: buf.baseAddress!, byteCount: buf.count)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(serverFD)
            throw DaemonServerError.bindFailed
        }

        guard listen(serverFD, 5) == 0 else {
            Darwin.close(serverFD)
            throw DaemonServerError.listenFailed
        }

        logger.info("Daemon server listening on \(socketPath)")

        // Use DispatchSource for non-blocking accept
        let source = DispatchSource.makeReadSource(fileDescriptor: serverFD, queue: .main)
        let fd = serverFD
        let agent = agentClient
        let log = logger
        source.setEventHandler {
            while true {
                let clientFD = accept(fd, nil, nil)
                if clientFD < 0 { break }
                Task { @MainActor in
                    await Self.handleClient(clientFD: clientFD, agentClient: agent, logger: log)
                }
            }
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        source.resume()
        acceptSource = source
    }

    /// Stop the server
    public func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        serverFD = -1
        unlink(socketPath)
        logger.info("Daemon server stopped")
    }

    /// Handle a single CLI client connection
    private static func handleClient(
        clientFD: Int32,
        agentClient: GuestAgentClient,
        logger: Logger
    ) async {
        defer { Darwin.close(clientFD) }

        // Read request
        var requestData = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 65536)
        defer { buffer.deallocate() }

        while true {
            let bytesRead = read(clientFD, buffer, 65536)
            if bytesRead <= 0 { return }
            requestData.append(buffer, count: bytesRead)
            if requestData.contains(0x0A) { break }
        }

        if let newlineIndex = requestData.firstIndex(of: 0x0A) {
            requestData = requestData[..<newlineIndex]
        }

        // Parse JSON-RPC request
        guard let request = try? JSONDecoder().decode(JSONRPCRequest.self, from: requestData) else {
            logger.error("Failed to parse client request")
            return
        }

        logger.info("Forwarding request: \(request.method)")

        // Forward to guest agent via vsock
        do {
            let response = try await agentClient.send(method: request.method, params: request.params)
            var responseData = try JSONEncoder().encode(response)
            responseData.append(0x0A)
            responseData.withUnsafeBytes { buf in
                _ = write(clientFD, buf.baseAddress!, buf.count)
            }
        } catch {
            logger.error("Agent request failed: \(error.localizedDescription)")
            let errorResponse = JSONRPCResponse(
                id: request.id,
                result: nil,
                error: JSONRPCError(code: -32000, message: "Agent error: \(error.localizedDescription)")
            )
            if var responseData = try? JSONEncoder().encode(errorResponse) {
                responseData.append(0x0A)
                responseData.withUnsafeBytes { buf in
                    _ = write(clientFD, buf.baseAddress!, buf.count)
                }
            }
        }
    }
}

public enum DaemonServerError: Error, LocalizedError {
    case socketFailed
    case bindFailed
    case listenFailed
    case pathTooLong

    public var errorDescription: String? {
        switch self {
        case .socketFailed: return "Failed to create server socket"
        case .bindFailed: return "Failed to bind server socket"
        case .listenFailed: return "Failed to listen on server socket"
        case .pathTooLong: return "Socket path too long"
        }
    }
}
