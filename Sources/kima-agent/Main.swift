import Foundation
import Logging
import KimaKit

@main
struct KimaAgent {
    static func main() async throws {
        var logger = Logger(label: "kima.agent")
        logger.logLevel = .info
        logger.info("kima guest agent starting...")

        let podman = PodmanClient()
        let handler = RPCHandler(podman: podman)

        // Try vsock first, fall back to TCP for development
        let listener: ServerListener
        do {
            listener = try VsockListener(port: 1024)
            logger.info("Listening on vsock port 1024")
        } catch {
            logger.warning("vsock listen failed (\(error)), falling back to TCP :10240")
            listener = try TCPListener(port: 10240)
            logger.info("Listening on TCP port 10240 (development mode)")
        }

        // Accept loop
        while true {
            do {
                let conn = try listener.accept()
                Task {
                    await handleConnection(conn, handler: handler, logger: logger)
                }
            } catch {
                logger.error("Accept error: \(error)")
            }
        }
    }
}

func handleConnection(_ conn: Connection, handler: RPCHandler, logger: Logger) async {
    defer { conn.close() }

    while let line = conn.readLine() {
        guard !line.isEmpty else { continue }

        guard let data = line.data(using: .utf8),
              let request = try? JSONDecoder().decode(JSONRPCRequest.self, from: data) else {
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
            conn.writeLine(respStr)
        }
    }
}
