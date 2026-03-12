import Foundation
import Virtualization
import Logging

/// Forwards TCP connections from host port to guest via vsock
@MainActor
public final class PortForwarder: Sendable {
    private let socketDevice: VZVirtioSocketDevice
    private let logger = Logger(label: "kima.port-forward")

    public init(socketDevice: VZVirtioSocketDevice) {
        self.socketDevice = socketDevice
    }

    /// Start forwarding from hostPort to guest vsock port
    /// The guest agent handles routing to the container port
    public func forward(hostPort: UInt16, guestVsockPort: UInt32) throws {
        let serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            throw PortForwardError.bindFailed("Failed to create socket")
        }

        var reuseAddr: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = hostPort.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverSocket, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(serverSocket)
            throw PortForwardError.bindFailed("Failed to bind to port \(hostPort)")
        }

        guard listen(serverSocket, 128) == 0 else {
            close(serverSocket)
            throw PortForwardError.bindFailed("Failed to listen on port \(hostPort)")
        }

        logger.info("Port forwarding: localhost:\(hostPort) -> vsock:\(guestVsockPort)")

        // TODO: Accept loop with bidirectional relay via vsock fileDescriptor
    }
}

public enum PortForwardError: Error, LocalizedError {
    case bindFailed(String)

    public var errorDescription: String? {
        switch self {
        case .bindFailed(let msg): return msg
        }
    }
}
