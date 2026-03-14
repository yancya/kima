import Foundation
import Logging
import KimaKit

@main
struct KimaAgent {
    static func main() async throws {
        var logger = Logger(label: "kima.agent")
        logger.logLevel = .info
        debugLog("kima guest agent starting...")

        let podman = PodmanClient()
        let handler = RPCHandler(podman: podman)

        // Try vsock first, fall back to TCP for development
        let listener: ServerListener
        do {
            listener = try VsockListener(port: 1024)
            debugLog("Listening on vsock port 1024")
        } catch {
            debugLog("vsock listen failed: \(error), falling back to TCP :10240")
            listener = try TCPListener(port: 10240)
            debugLog("Listening on TCP port 10240")
        }

        // Accept loop — run blocking accept on a dedicated thread
        // to avoid starving the Swift cooperative thread pool
        debugLog("Entering accept loop")
        let log = logger
        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in
            let capturedListener = listener
            let capturedHandler = handler
            DispatchQueue.global().async {
                while true {
                    do {
                        let conn = try capturedListener.accept()
                        debugLog("Accepted connection")
                        Task {
                            await handleConnection(conn, handler: capturedHandler, logger: log)
                        }
                    } catch {
                        debugLog("Accept error: \(error)")
                    }
                }
            }
        }
    }
}

/// Write debug message to kernel log (visible in host console.log via dmesg)
func debugLog(_ msg: String) {
    // Try /dev/hvc0, /dev/console, and /dev/kmsg
    for dev in ["/dev/hvc0", "/dev/console", "/dev/kmsg"] {
        let fd = open(dev, O_WRONLY | O_NONBLOCK)
        if fd >= 0 {
            let line = "[kima-agent] \(msg)\n"
            _ = line.withCString { ptr in
                write(fd, ptr, strlen(ptr))
            }
            close(fd)
            return
        }
    }
    // Fallback: stderr
    var line = "[kima-agent] \(msg)\n"
    line.withUTF8 { buf in
        _ = write(STDERR_FILENO, buf.baseAddress!, buf.count)
    }
}

func handleConnection(_ conn: Connection, handler: RPCHandler, logger: Logger) async {
    defer { conn.close() }
    debugLog("New connection accepted")

    while let line = conn.readLine() {
        guard !line.isEmpty else { continue }
        debugLog("Received: \(line)")

        guard let data = line.data(using: .utf8),
              let request = try? JSONDecoder().decode(JSONRPCRequest.self, from: data) else {
            debugLog("Parse error")
            let errorResp = JSONRPCResponse(
                id: 0,
                error: JSONRPCError(code: -32700, message: "Parse error")
            )
            if let respData = try? JSONEncoder().encode(errorResp) {
                conn.writeLine(String(data: respData, encoding: .utf8)!)
            }
            continue
        }

        let response = handler.handle(request)
        if let respData = try? JSONEncoder().encode(response),
           let respStr = String(data: respData, encoding: .utf8) {
            debugLog("Sending: \(respStr)")
            conn.writeLine(respStr)
            debugLog("Sent response")
        }
    }
    debugLog("Connection closed")
}
