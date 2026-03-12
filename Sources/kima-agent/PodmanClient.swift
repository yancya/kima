import Foundation
import KimaKit

/// Wraps podman CLI commands
struct PodmanClient: Sendable {
    func run(image: String, ports: [String], command: [String]) -> Result<String, PodmanError> {
        var args = ["run", "-d"]
        for p in ports {
            args += ["-p", p]
        }
        args.append(image)
        args += command

        return exec(args).map { output in
            output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func ps(all: Bool) -> Result<[ContainerInfo], PodmanError> {
        var args = ["ps", "--format", "json"]
        if all { args.append("-a") }

        return exec(args).flatMap { output in
            guard let data = output.data(using: .utf8) else {
                return .failure(.parseFailed("Invalid UTF-8"))
            }
            do {
                let raw = try JSONDecoder().decode([PodmanContainer].self, from: data)
                let containers = raw.map { c in
                    ContainerInfo(
                        id: String(c.Id.prefix(12)),
                        image: c.Image,
                        command: "",
                        state: c.State,
                        ports: c.Ports?.map { p in "\(p.host_port):\(p.container_port)/\(p.protocol)" } ?? [],
                        names: c.Names?.first ?? ""
                    )
                }
                return .success(containers)
            } catch {
                return .failure(.parseFailed(error.localizedDescription))
            }
        }
    }

    func stop(container: String) -> Result<Void, PodmanError> {
        exec(["stop", container]).map { _ in }
    }

    func rm(container: String) -> Result<Void, PodmanError> {
        exec(["rm", container]).map { _ in }
    }

    func pull(image: String) -> Result<Void, PodmanError> {
        exec(["pull", image]).map { _ in }
    }

    func images() -> Result<[ImageInfo], PodmanError> {
        exec(["images", "--format", "json"]).flatMap { output in
            guard let data = output.data(using: .utf8) else {
                return .failure(.parseFailed("Invalid UTF-8"))
            }
            do {
                let raw = try JSONDecoder().decode([PodmanImage].self, from: data)
                let images = raw.map { img in
                    let (repo, tag) = parseRepoTag(img.RepoTags?.first)
                    return ImageInfo(
                        id: String(img.Id.prefix(12)),
                        repository: repo,
                        tag: tag,
                        size: formatBytes(img.Size)
                    )
                }
                return .success(images)
            } catch {
                return .failure(.parseFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Private

    private func exec(_ args: [String]) -> Result<String, PodmanError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/podman")
        process.arguments = args

        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .failure(.execFailed("podman \(args.joined(separator: " ")): \(error.localizedDescription)"))
        }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return .failure(.execFailed("podman \(args.joined(separator: " ")): \(stderr.isEmpty ? output : stderr)"))
        }

        return .success(output)
    }
}

// MARK: - podman JSON types

private struct PodmanContainer: Decodable {
    let Id: String
    let Image: String
    let State: String
    let Ports: [PodmanPort]?
    let Names: [String]?
}

private struct PodmanPort: Decodable {
    let host_port: UInt16
    let container_port: UInt16
    let `protocol`: String
}

private struct PodmanImage: Decodable {
    let Id: String
    let RepoTags: [String]?
    let Size: Int64
}

// MARK: - Helpers

private func parseRepoTag(_ repoTag: String?) -> (String, String) {
    guard let repoTag else { return ("<none>", "<none>") }
    let parts = repoTag.split(separator: ":", maxSplits: 1)
    let repo = String(parts[0])
    let tag = parts.count > 1 ? String(parts[1]) : "<none>"
    return (repo, tag)
}

private func formatBytes(_ bytes: Int64) -> String {
    let gb: Int64 = 1024 * 1024 * 1024
    let mb: Int64 = 1024 * 1024
    let kb: Int64 = 1024
    switch bytes {
    case gb...: return String(format: "%.1fGB", Double(bytes) / Double(gb))
    case mb...: return String(format: "%.1fMB", Double(bytes) / Double(mb))
    case kb...: return String(format: "%.1fKB", Double(bytes) / Double(kb))
    default: return "\(bytes)B"
    }
}

enum PodmanError: Error, LocalizedError {
    case execFailed(String)
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .execFailed(let msg): return msg
        case .parseFailed(let msg): return "Failed to parse podman output: \(msg)"
        }
    }
}
