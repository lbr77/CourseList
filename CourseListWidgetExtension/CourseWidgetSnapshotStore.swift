import Foundation

enum CourseWidgetSnapshotStore {
    static func load(fileManager: FileManager = .default) -> CourseWidgetSnapshot? {
        do {
            let url = try snapshotURL(fileManager: fileManager)
            guard fileManager.fileExists(atPath: url.path) else {
                return nil
            }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(CourseWidgetSnapshot.self, from: data)
        } catch {
            return nil
        }
    }

    private static func snapshotURL(fileManager: FileManager) throws -> URL {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: CourseWidgetSharedConfig.appGroupIdentifier
        ) else {
            throw SnapshotError.missingContainer
        }

        return containerURL
            .appendingPathComponent(CourseWidgetSharedConfig.snapshotDirectoryName, isDirectory: true)
            .appendingPathComponent(CourseWidgetSharedConfig.snapshotFileName, isDirectory: false)
    }

    private enum SnapshotError: Error {
        case missingContainer
    }
}
