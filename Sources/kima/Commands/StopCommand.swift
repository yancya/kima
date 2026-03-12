import ArgumentParser
import KimaCore
import KimaKit

struct StopCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop a running container"
    )

    @Argument(help: "Container ID or name")
    var container: String

    func run() async throws {
        let client = DaemonClient()
        guard client.isRunning() else {
            print("Machine is not running. Start it with: kima machine start")
            throw ExitCode.failure
        }

        let params: [String: JSONValue] = ["container": .string(container)]
        let response = try await client.send(method: RPCMethod.containerStop, params: params)

        if let error = response.error {
            print("Error: \(error.message)")
            throw ExitCode.failure
        }
        print(container)
    }
}
