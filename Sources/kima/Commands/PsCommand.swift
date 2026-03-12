import ArgumentParser
import KimaCore
import KimaKit

struct PsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ps",
        abstract: "List containers"
    )

    @Flag(name: .shortAndLong, help: "Show all containers (including stopped)")
    var all: Bool = false

    func run() async throws {
        let client = DaemonClient()
        guard client.isRunning() else {
            print("Machine is not running. Start it with: kima machine start")
            throw ExitCode.failure
        }

        let params: [String: JSONValue] = ["all": .bool(all)]
        let response = try await client.send(method: RPCMethod.containerPs, params: params)

        if let error = response.error {
            print("Error: \(error.message)")
            throw ExitCode.failure
        }

        if case .array(let containers) = response.result {
            if containers.isEmpty {
                print("No containers found")
                return
            }
            print(String(format: "%-12s %-20s %-10s %-20s %s", "CONTAINER ID", "IMAGE", "STATE", "PORTS", "NAMES"))
            for container in containers {
                if case .object(let info) = container {
                    let id = info["id"].flatMap { if case .string(let s) = $0 { return s } else { return nil } } ?? ""
                    let image = info["image"].flatMap { if case .string(let s) = $0 { return s } else { return nil } } ?? ""
                    let state = info["state"].flatMap { if case .string(let s) = $0 { return s } else { return nil } } ?? ""
                    let names = info["names"].flatMap { if case .string(let s) = $0 { return s } else { return nil } } ?? ""
                    let ports: String
                    if case .array(let p) = info["ports"] {
                        ports = p.compactMap { if case .string(let s) = $0 { return s } else { return nil } }.joined(separator: ", ")
                    } else {
                        ports = ""
                    }
                    print(String(format: "%-12s %-20s %-10s %-20s %s", id, image, state, ports, names))
                }
            }
        }
    }
}
