import Foundation
import Logging

/// Orchestrates VM create/start/stop/status operations
public actor VMLifecycle {
    private let logger = Logger(label: "kima.lifecycle")

    public init() {}

    /// Create a new machine with the given configuration
    public func create(config: MachineConfig) throws {
        // Ensure directories exist
        try KimaPaths.ensureMachineDirectoryExists()

        // Create disk image
        try DiskImage.create(at: KimaPaths.diskImageFile, sizeGB: config.diskSizeGB)

        // Save config
        try config.save()

        logger.info("Machine created: cpus=\(config.cpus), memory=\(config.memoryMB)MB, disk=\(config.diskSizeGB)GB")
    }

    /// Get the current machine status
    public func status() -> String {
        let configExists = FileManager.default.fileExists(atPath: KimaPaths.machineConfigFile.path(percentEncoded: false))
        if !configExists {
            return "not_created"
        }

        let pidFile = KimaPaths.daemonPidFile
        if FileManager.default.fileExists(atPath: pidFile.path(percentEncoded: false)),
           let pidStr = try? String(contentsOf: pidFile, encoding: .utf8),
           let pid = Int32(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
            // Check if process is running
            if kill(pid, 0) == 0 {
                return "running"
            }
        }

        return "stopped"
    }

    /// Check if kernel and rootfs are available for boot
    public func canBoot() -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: KimaPaths.kernelFile.path(percentEncoded: false))
            && fm.fileExists(atPath: KimaPaths.rootfsFile.path(percentEncoded: false))
    }
}
