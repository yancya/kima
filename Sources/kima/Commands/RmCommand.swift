import ArgumentParser
import KimaCore
import KimaKit

struct RmCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rm",
        abstract: "Remove a container"
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
        let response = try await client.send(method: RPCMethod.containerRm, params: params)

        if let error = response.error {
            print("Error: \(error.message)")
            throw ExitCode.failure
        }
        print(container)
    }
}
