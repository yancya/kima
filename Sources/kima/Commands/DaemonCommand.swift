import ArgumentParser
import Foundation
import KimaCore
import Logging

/// Hidden subcommand that runs the VM daemon process
struct DaemonCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "_daemon",
        abstract: "Internal: run the VM daemon (do not call directly)",
        shouldDisplay: false
    )

    func run() async throws {
        var logger = Logger(label: "kima.daemon")
        logger.logLevel = .info

        logger.info("Daemon starting...")

        let lifecycle = VMLifecycle()
        guard await lifecycle.canBoot() else {
            logger.error("Cannot boot: kernel or rootfs not found. Run Scripts/build-vm-image.sh first.")
            throw ExitCode.failure
        }

        let config = try MachineConfig.load()

        // Write PID file
        let pidStr = "\(Foundation.ProcessInfo.processInfo.processIdentifier)"
        try pidStr.write(to: KimaPaths.daemonPidFile, atomically: true, encoding: .utf8)

        // Build config and start VM on MainActor
        try await MainActor.run {
            let vmConfig = try VMConfigurationBuilder.build(config: config)
            let vm = KimaVirtualMachine(configuration: vmConfig)
            // Store vm reference to keep it alive
            _daemonVM = vm
        }

        try await _daemonVM?.start()

        logger.info("VM started. Daemon running. Send SIGTERM to stop.")

        // Keep the daemon running indefinitely
        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in
            // Never resumes — daemon runs until the process is killed
        }
    }
}

// Global reference to keep VM alive during daemon lifetime
@MainActor
private var _daemonVM: KimaVirtualMachine?
