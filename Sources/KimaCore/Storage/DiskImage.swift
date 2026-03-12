import Foundation

public enum DiskImage: Sendable {
    /// Create a sparse raw disk image file using ftruncate
    /// - Parameters:
    ///   - url: File URL for the disk image
    ///   - sizeGB: Size in gigabytes
    public static func create(at url: URL, sizeGB: Int) throws {
        let fileManager = FileManager.default
        let path = url.path(percentEncoded: false)

        // Don't overwrite existing image
        guard !fileManager.fileExists(atPath: path) else {
            throw DiskImageError.alreadyExists(path)
        }

        // Ensure parent directory exists
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Create sparse file with ftruncate
        let fd = open(path, O_CREAT | O_WRONLY, 0o644)
        guard fd >= 0 else {
            throw DiskImageError.createFailed(path, errno)
        }
        defer { close(fd) }

        let sizeBytes = Int64(sizeGB) * 1024 * 1024 * 1024
        guard ftruncate(fd, off_t(sizeBytes)) == 0 else {
            // Clean up the file on failure
            unlink(path)
            throw DiskImageError.truncateFailed(path, errno)
        }
    }

    /// Check if a disk image exists and return its size
    public static func info(at url: URL) throws -> DiskImageInfo {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        let logicalSize = attrs[.size] as? UInt64 ?? 0
        return DiskImageInfo(
            path: url.path(percentEncoded: false),
            logicalSizeBytes: logicalSize
        )
    }
}

public struct DiskImageInfo: Sendable {
    public let path: String
    public let logicalSizeBytes: UInt64

    public var logicalSizeGB: Double {
        Double(logicalSizeBytes) / (1024 * 1024 * 1024)
    }
}

public enum DiskImageError: Error, LocalizedError {
    case alreadyExists(String)
    case createFailed(String, Int32)
    case truncateFailed(String, Int32)

    public var errorDescription: String? {
        switch self {
        case .alreadyExists(let path):
            return "Disk image already exists at \(path)"
        case .createFailed(let path, let code):
            return "Failed to create disk image at \(path): errno \(code)"
        case .truncateFailed(let path, let code):
            return "Failed to set disk image size at \(path): errno \(code)"
        }
    }
}
