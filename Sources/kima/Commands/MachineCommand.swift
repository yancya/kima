import ArgumentParser
import Foundation
import KimaCore

struct MachineCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "machine",
        abstract: "Manage the kima virtual machine",
        subcommands: [
            Create.self,
            Start.self,
            Stop.self,
            Status.self,
            Upgrade.self,
        ]
    )

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create a new virtual machine"
        )

        @Option(name: .long, help: "Number of CPUs")
        var cpus: Int = 2

        @Option(name: .long, help: "Memory size in MB")
        var memory: Int = 2048

        @Option(name: .long, help: "Disk size in GB")
        var disk: Int = 64

        func run() async throws {
            let config = MachineConfig(cpus: cpus, memoryMB: memory, diskSizeGB: disk)
            let lifecycle = VMLifecycle()
            try await lifecycle.create(config: config)
            print("Machine created: cpus=\(cpus), memory=\(memory)MB, disk=\(disk)GB")
        }
    }

    struct Start: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Start the virtual machine"
        )

        func run() async throws {
            let lifecycle = VMLifecycle()
            let currentStatus = await lifecycle.status()

            guard currentStatus != "running" else {
                print("Machine is already running")
                return
            }

            guard currentStatus != "not_created" else {
                print("Machine not found. Create one with: kima machine create")
                throw ExitCode.failure
            }

            guard await lifecycle.canBoot() else {
                print("Cannot boot: kernel or rootfs not found.")
                print("Run Scripts/build-vm-image.sh to build the VM image first.")
                throw ExitCode.failure
            }

            print("Starting machine...")

            // Fork the daemon process
            let executablePath = ProcessInfo.processInfo.arguments[0]
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = ["_daemon"]
            process.standardOutput = nil
            process.standardError = nil
            try process.run()

            print("Machine starting (daemon PID: \(process.processIdentifier))")

            // Wait for daemon socket to appear (indicates agent is ready)
            let socketPath = KimaPaths.daemonSocketFile.path(percentEncoded: false)
            for _ in 0..<120 {
                if FileManager.default.fileExists(atPath: socketPath) {
                    print("Machine is ready")
                    return
                }
                // Check daemon is still alive
                guard process.isRunning else {
                    print("Error: daemon exited unexpectedly")
                    throw ExitCode.failure
                }
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
            print("Warning: daemon started but agent may not be ready yet")
        }
    }

    struct Stop: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Stop the virtual machine"
        )

        func run() async throws {
            let pidFile = KimaPaths.daemonPidFile
            guard FileManager.default.fileExists(atPath: pidFile.path(percentEncoded: false)) else {
                print("Machine is not running")
                return
            }

            let pidStr = try String(contentsOf: pidFile, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let pid = Int32(pidStr) else {
                print("Invalid PID file")
                throw ExitCode.failure
            }

            // Send SIGTERM to gracefully stop
            kill(pid, SIGTERM)
            print("Stopping machine (PID: \(pid))...")

            // Wait a bit and check
            try await Task.sleep(nanoseconds: 2_000_000_000)

            if kill(pid, 0) == 0 {
                print("Machine is still shutting down...")
            } else {
                // Clean up PID file
                try? FileManager.default.removeItem(at: pidFile)
                try? FileManager.default.removeItem(at: KimaPaths.daemonSocketFile)
                print("Machine stopped")
            }
        }
    }

    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show virtual machine status"
        )

        func run() async throws {
            let lifecycle = VMLifecycle()
            let currentStatus = await lifecycle.status()
            print("Machine status: \(currentStatus)")

            if currentStatus != "not_created" {
                if let config = try? MachineConfig.load() {
                    print("  CPUs:   \(config.cpus)")
                    print("  Memory: \(config.memoryMB) MB")
                    print("  Disk:   \(config.diskSizeGB) GB")
                }
            }
        }
    }

    struct Upgrade: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Upgrade the virtual machine kernel and rootfs"
        )

        func run() async throws {
            let lifecycle = VMLifecycle()
            let currentStatus = await lifecycle.status()

            if currentStatus == "running" {
                print("Stopping machine for upgrade...")
                // Stop via SIGTERM
                let pidFile = KimaPaths.daemonPidFile
                if let pidStr = try? String(contentsOf: pidFile, encoding: .utf8),
                   let pid = Int32(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    kill(pid, SIGTERM)
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                }
            }

            print("Run Scripts/build-vm-image.sh to build updated VM images.")
            print("Then restart with: kima machine start")
        }
    }
}
