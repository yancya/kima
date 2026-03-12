import ArgumentParser
import KimaCore
import KimaKit

struct PullCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pull",
        abstract: "Pull a container image"
    )

    @Argument(help: "Image name")
    var image: String

    func run() async throws {
        let client = DaemonClient()
        guard client.isRunning() else {
            print("Machine is not running. Start it with: kima machine start")
            throw ExitCode.failure
        }

        let params: [String: JSONValue] = ["image": .string(image)]
        let response = try await client.send(method: RPCMethod.imagePull, params: params)

        if let error = response.error {
            print("Error: \(error.message)")
            throw ExitCode.failure
        }
        print("Pulled: \(image)")
    }
}
