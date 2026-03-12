import ArgumentParser
import KimaCore
import KimaKit

struct ImagesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "images",
        abstract: "List container images"
    )

    func run() async throws {
        let client = DaemonClient()
        guard client.isRunning() else {
            print("Machine is not running. Start it with: kima machine start")
            throw ExitCode.failure
        }

        let response = try await client.send(method: RPCMethod.imageList)

        if let error = response.error {
            print("Error: \(error.message)")
            throw ExitCode.failure
        }

        if case .array(let images) = response.result {
            if images.isEmpty {
                print("No images found")
                return
            }
            print(String(format: "%-20s %-10s %-12s %s", "REPOSITORY", "TAG", "IMAGE ID", "SIZE"))
            for image in images {
                if case .object(let info) = image {
                    let repo = info["repository"].flatMap { if case .string(let s) = $0 { return s } else { return nil } } ?? ""
                    let tag = info["tag"].flatMap { if case .string(let s) = $0 { return s } else { return nil } } ?? ""
                    let id = info["id"].flatMap { if case .string(let s) = $0 { return s } else { return nil } } ?? ""
                    let size = info["size"].flatMap { if case .string(let s) = $0 { return s } else { return nil } } ?? ""
                    print(String(format: "%-20s %-10s %-12s %s", repo, tag, id, size))
                }
            }
        }
    }
}
