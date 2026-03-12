import ArgumentParser
import KimaCore
import KimaKit

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run a container"
    )

    @Option(name: .shortAndLong, help: "Port mapping (HOST:CONTAINER)")
    var publish: [String] = []

    @Argument(help: "Container image")
    var image: String

    @Argument(parsing: .captureForPassthrough, help: "Command to run")
    var command: [String] = []

    func run() async throws {
        let client = DaemonClient()
        guard client.isRunning() else {
            print("Machine is not running. Start it with: kima machine start")
            throw ExitCode.failure
        }

        var params: [String: JSONValue] = ["image": .string(image)]
        if !publish.isEmpty {
            params["ports"] = .array(publish.map { .string($0) })
        }
        if !command.isEmpty {
            params["command"] = .array(command.map { .string($0) })
        }

        let response = try await client.send(method: RPCMethod.containerRun, params: params)
        if let error = response.error {
            print("Error: \(error.message)")
            throw ExitCode.failure
        }
        if case .object(let result) = response.result,
           case .string(let id) = result["id"] {
            print(id)
        }
    }
}
