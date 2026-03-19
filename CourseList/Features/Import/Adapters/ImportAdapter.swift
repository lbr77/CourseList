import Foundation

protocol ImportAdapter: Sendable {
    var id: String { get }
    var label: String { get }
    var captureJavaScript: String { get }
    func matches(_ context: ImportContext) -> Bool
    func normalize(rawPayload: Any, context: ImportContext) throws -> ImportedTimetableDraft
}

enum ImportAdapterRegistry {
    static let adapters: [ImportAdapter] = [JLUVPNImportAdapter()]

    static func adapter(id: String?) -> ImportAdapter? {
        guard let id else { return nil }
        return adapters.first(where: { $0.id == id })
    }

    static func match(context: ImportContext) -> ImportAdapter? {
        adapters.first(where: { $0.matches(context) })
    }
}
