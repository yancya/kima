#if canImport(Glibc)
import Glibc
private let sysClose = Glibc.close
#elseif canImport(Musl)
import Musl
private let sysClose = Musl.close
#elseif canImport(Darwin)
import Darwin
private let sysClose = Darwin.close
#endif

import Foundation

// MARK: - Protocols

protocol ServerListener: Sendable {
    func accept() throws -> Connection
}

protocol Connection: Sendable {
    func readLine() -> String?
    func writeLine(_ line: String)
    func close()
}

// MARK: - Vsock

#if os(Linux)
private let AF_VSOCK: Int32 = 40
private let VMADDR_CID_ANY: UInt32 = 0xFFFFFFFF

private struct sockaddr_vm {
    var svm_family: sa_family_t
    var svm_reserved1: UInt16
    var svm_port: UInt32
    var svm_cid: UInt32
    var svm_zero: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
}
#endif

final class VsockListener: ServerListener {
    private let fd: Int32

    init(port: UInt32) throws {
        #if os(Linux)
        let sock = socket(AF_VSOCK, Int32(SOCK_STREAM), 0)
        guard sock >= 0 else {
            throw NetworkError.socketFailed(errno)
        }

        var addr = sockaddr_vm(
            svm_family: sa_family_t(AF_VSOCK),
            svm_reserved1: 0,
            svm_port: port,
            svm_cid: VMADDR_CID_ANY
        )

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_vm>.size))
            }
        }
        guard bindResult == 0 else {
            sysClose(sock)
            throw NetworkError.bindFailed(errno)
        }

        guard listen(sock, 128) == 0 else {
            sysClose(sock)
            throw NetworkError.listenFailed(errno)
        }

        self.fd = sock
        #else
        throw NetworkError.unsupported
        #endif
    }

    func accept() throws -> Connection {
        let clientFd = Foundation.accept(fd, nil, nil)
        guard clientFd >= 0 else {
            throw NetworkError.acceptFailed(errno)
        }
        return SocketConnection(fd: clientFd)
    }
}

// MARK: - TCP (development fallback)

final class TCPListener: ServerListener {
    private let fd: Int32

    init(port: UInt16) throws {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else {
            throw NetworkError.socketFailed(errno)
        }

        var reuseAddr: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY.bigEndian

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            sysClose(sock)
            throw NetworkError.bindFailed(errno)
        }

        guard listen(sock, 128) == 0 else {
            sysClose(sock)
            throw NetworkError.listenFailed(errno)
        }

        self.fd = sock
    }

    func accept() throws -> Connection {
        let clientFd = Foundation.accept(fd, nil, nil)
        guard clientFd >= 0 else {
            throw NetworkError.acceptFailed(errno)
        }
        return SocketConnection(fd: clientFd)
    }
}

// MARK: - Socket Connection

final class SocketConnection: Connection, @unchecked Sendable {
    private let fd: Int32
    private var buffer = Data()

    init(fd: Int32) {
        self.fd = fd
    }

    func readLine() -> String? {
        let readBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { readBuf.deallocate() }

        while true {
            if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[buffer.startIndex..<newlineIndex]
                buffer = Data(buffer[(newlineIndex + 1)...])
                return String(data: lineData, encoding: .utf8)
            }

            let n = read(fd, readBuf, 4096)
            if n <= 0 { return nil }
            buffer.append(readBuf, count: n)
        }
    }

    func writeLine(_ line: String) {
        let data = Array((line + "\n").utf8)
        data.withUnsafeBufferPointer { buf in
            _ = write(fd, buf.baseAddress!, buf.count)
        }
    }

    func close() {
        sysClose(fd)
    }
}

// MARK: - Errors

enum NetworkError: Error, LocalizedError {
    case socketFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case acceptFailed(Int32)
    case unsupported

    var errorDescription: String? {
        switch self {
        case .socketFailed(let e): return "socket() failed: errno \(e)"
        case .bindFailed(let e): return "bind() failed: errno \(e)"
        case .listenFailed(let e): return "listen() failed: errno \(e)"
        case .acceptFailed(let e): return "accept() failed: errno \(e)"
        case .unsupported: return "Not supported on this platform"
        }
    }
}
