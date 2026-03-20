import Foundation
import SQLite3
import WCDBSwift

final class DatabaseManager {
    private let queue = DispatchQueue(label: "CourseList.DatabaseManager")
    private let database: Database
    let path: String

    init(fileManager: FileManager = .default) throws {
        guard let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw AppError.database(L10n.tr("Unable to locate app document directory."))
        }
        let sqliteDirectory = documentDirectory.appendingPathComponent("SQLite", isDirectory: true)
        try fileManager.createDirectory(at: sqliteDirectory, withIntermediateDirectories: true)
        path = sqliteDirectory.appendingPathComponent(appDatabaseName).path
        try Self.bootstrapSchemaIfNeeded(at: path)
        database = Database(at: path)
    }

    func read<T>(_ block: @escaping (Database) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try block(self.database))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func write<T>(_ block: @escaping (Database) throws -> T) async throws -> T {
        try await read(block)
    }

    private static func bootstrapSchemaIfNeeded(at path: String) throws {
        var pointer: OpaquePointer?
        guard sqlite3_open(path, &pointer) == SQLITE_OK, let pointer else {
            let message = pointer.flatMap { String(cString: sqlite3_errmsg($0)) } ?? L10n.tr("Unable to open SQLite database.")
            if let pointer { sqlite3_close(pointer) }
            throw AppError.database(message)
        }

        defer { sqlite3_close(pointer) }

        if sqlite3_exec(pointer, schemaSQL, nil, nil, nil) != SQLITE_OK {
            throw AppError.database(String(cString: sqlite3_errmsg(pointer)))
        }

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(pointer, "PRAGMA user_version;", -1, &statement, nil) != SQLITE_OK {
            throw AppError.database(String(cString: sqlite3_errmsg(pointer)))
        }
        defer { sqlite3_finalize(statement) }

        var currentVersion = 0
        if sqlite3_step(statement) == SQLITE_ROW {
            currentVersion = Int(sqlite3_column_int(statement, 0))
        }

        if currentVersion < appDatabaseVersion {
            let pragmaSQL = "PRAGMA user_version = \(appDatabaseVersion);"
            if sqlite3_exec(pointer, pragmaSQL, nil, nil, nil) != SQLITE_OK {
                throw AppError.database(String(cString: sqlite3_errmsg(pointer)))
            }
        }
    }
}
