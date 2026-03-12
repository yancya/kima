import Foundation
import KimaKit

/// Dispatches JSON-RPC methods to podman operations
struct RPCHandler: Sendable {
    let podman: PodmanClient

    func handle(_ request: JSONRPCRequest) -> JSONRPCResponse {
        switch request.method {
        case RPCMethod.containerRun:
            return containerRun(request)
        case RPCMethod.containerPs:
            return containerPs(request)
        case RPCMethod.containerStop:
            return containerStop(request)
        case RPCMethod.containerRm:
            return containerRm(request)
        case RPCMethod.imagePull:
            return imagePull(request)
        case RPCMethod.imageList:
            return imageList(request)
        case RPCMethod.machineStatus:
            return JSONRPCResponse(id: request.id, result: .object(["status": .string("running")]))
        default:
            return JSONRPCResponse(
                id: request.id,
                error: JSONRPCError(code: -32601, message: "Method not found: \(request.method)")
            )
        }
    }

    // MARK: - Handlers

    private func containerRun(_ req: JSONRPCRequest) -> JSONRPCResponse {
        guard let image = req.stringParam("image") else {
            return JSONRPCResponse(id: req.id, error: JSONRPCError(code: -32602, message: "missing 'image' parameter"))
        }
        let ports = req.stringArrayParam("ports")
        let command = req.stringArrayParam("command")

        switch podman.run(image: image, ports: ports, command: command) {
        case .success(let id):
            return JSONRPCResponse(id: req.id, result: .object(["id": .string(id), "status": .string("running")]))
        case .failure(let error):
            return JSONRPCResponse(id: req.id, error: JSONRPCError(code: 1, message: error.localizedDescription))
        }
    }

    private func containerPs(_ req: JSONRPCRequest) -> JSONRPCResponse {
        let all = req.boolParam("all")
        switch podman.ps(all: all) {
        case .success(let containers):
            let arr: [JSONValue] = containers.map { c in
                .object([
                    "id": .string(c.id),
                    "image": .string(c.image),
                    "state": .string(c.state),
                    "ports": .array(c.ports.map { .string($0) }),
                    "names": .string(c.names),
                ])
            }
            return JSONRPCResponse(id: req.id, result: .array(arr))
        case .failure(let error):
            return JSONRPCResponse(id: req.id, error: JSONRPCError(code: 1, message: error.localizedDescription))
        }
    }

    private func containerStop(_ req: JSONRPCRequest) -> JSONRPCResponse {
        guard let container = req.stringParam("container") else {
            return JSONRPCResponse(id: req.id, error: JSONRPCError(code: -32602, message: "missing 'container' parameter"))
        }
        switch podman.stop(container: container) {
        case .success:
            return JSONRPCResponse(id: req.id, result: .object(["status": .string("stopped")]))
        case .failure(let error):
            return JSONRPCResponse(id: req.id, error: JSONRPCError(code: 1, message: error.localizedDescription))
        }
    }

    private func containerRm(_ req: JSONRPCRequest) -> JSONRPCResponse {
        guard let container = req.stringParam("container") else {
            return JSONRPCResponse(id: req.id, error: JSONRPCError(code: -32602, message: "missing 'container' parameter"))
        }
        switch podman.rm(container: container) {
        case .success:
            return JSONRPCResponse(id: req.id, result: .object(["status": .string("removed")]))
        case .failure(let error):
            return JSONRPCResponse(id: req.id, error: JSONRPCError(code: 1, message: error.localizedDescription))
        }
    }

    private func imagePull(_ req: JSONRPCRequest) -> JSONRPCResponse {
        guard let image = req.stringParam("image") else {
            return JSONRPCResponse(id: req.id, error: JSONRPCError(code: -32602, message: "missing 'image' parameter"))
        }
        switch podman.pull(image: image) {
        case .success:
            return JSONRPCResponse(id: req.id, result: .object(["status": .string("pulled")]))
        case .failure(let error):
            return JSONRPCResponse(id: req.id, error: JSONRPCError(code: 1, message: error.localizedDescription))
        }
    }

    private func imageList(_ req: JSONRPCRequest) -> JSONRPCResponse {
        switch podman.images() {
        case .success(let images):
            let arr: [JSONValue] = images.map { img in
                .object([
                    "id": .string(img.id),
                    "repository": .string(img.repository),
                    "tag": .string(img.tag),
                    "size": .string(img.size),
                ])
            }
            return JSONRPCResponse(id: req.id, result: .array(arr))
        case .failure(let error):
            return JSONRPCResponse(id: req.id, error: JSONRPCError(code: 1, message: error.localizedDescription))
        }
    }
}

// MARK: - JSONRPCRequest param helpers

extension JSONRPCRequest {
    func stringParam(_ key: String) -> String? {
        guard let params, case .string(let v) = params[key] else { return nil }
        return v
    }

    func stringArrayParam(_ key: String) -> [String] {
        guard let params, case .array(let arr) = params[key] else { return [] }
        return arr.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
    }

    func boolParam(_ key: String) -> Bool {
        guard let params, case .bool(let v) = params[key] else { return false }
        return v
    }
}
