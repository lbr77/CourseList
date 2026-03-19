import Foundation

enum CourseWidgetSnapshotStoreError: LocalizedError {
    case missingContainer(groupIdentifier: String)

    var errorDescription: String? {
        switch self {
        case .missingContainer(let groupIdentifier):
            return "Unable to access app group container: \(groupIdentifier)"
        }
    }
}

enum CourseWidgetSnapshotStore {
    static func save(_ snapshot: CourseWidgetSnapshot, fileManager: FileManager = .default) throws {
        let fileURL = try snapshotFileURL(fileManager: fileManager)
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    static func load(fileManager: FileManager = .default) throws -> CourseWidgetSnapshot? {
        let fileURL = try snapshotFileURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        return try decoder.decode(CourseWidgetSnapshot.self, from: data)
    }

    static func snapshotFileURL(fileManager: FileManager = .default) throws -> URL {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: CourseWidgetSharedConfig.appGroupIdentifier
        ) else {
            throw CourseWidgetSnapshotStoreError.missingContainer(
                groupIdentifier: CourseWidgetSharedConfig.appGroupIdentifier
            )
        }

        return containerURL
            .appendingPathComponent(CourseWidgetSharedConfig.snapshotDirectoryName, isDirectory: true)
            .appendingPathComponent(CourseWidgetSharedConfig.snapshotFileName, isDirectory: false)
    }
}
