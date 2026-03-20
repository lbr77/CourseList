import Combine
import Foundation

@MainActor
final class ImportViewModel: ObservableObject {
    @Published var phase: ImportPhase = .browsing
    @Published var sourceURL: String
    @Published var pageTitle: String = ""
    @Published var canGoBack = false
    @Published var draft: ImportedTimetableDraft?
    @Published var draftErrors: [String] = []
    @Published var errorMessage: String?
    @Published var unsupportedReason: String?

    let proxy = WebViewProxy()

    private let repository: TimetableRepositoryProtocol
    let school: TimetableImportSchool
    private let preferredAdapter: ImportAdapter?

    init(repository: TimetableRepositoryProtocol, school: TimetableImportSchool) {
        self.repository = repository
        self.school = school
        sourceURL = school.defaultImportURL
        preferredAdapter = ImportAdapterRegistry.adapter(id: school.adapterId)
    }

    func navigationChanged(url: String, title: String?, canGoBack: Bool) {
        if !url.isEmpty { sourceURL = url }
        pageTitle = title ?? ""
        self.canGoBack = canGoBack
    }

    func inspectAndCapture() async {
        phase = .capturing
        errorMessage = nil
        unsupportedReason = nil
        draft = nil
        draftErrors = []

        do {
            let context = try await inspectContext()
            guard let adapter = preferredAdapter ?? ImportAdapterRegistry.match(context: context) else {
                phase = .unsupported
                unsupportedReason = L10n.tr("The current page does not support automatic import.")
                return
            }
            guard let raw = try await proxy.evaluate(adapter.captureJavaScript) else { throw AppError.importCapture(L10n.tr("Page scraping returns empty.")) }
            let normalized = try adapter.normalize(rawPayload: raw, context: context)
            let errors = validateImportedTimetableDraft(normalized)
            draft = normalized
            draftErrors = errors
            phase = .preview
        } catch {
            phase = .error
            errorMessage = error.localizedDescription
        }
    }

    func importDraft() async -> Bool {
        guard let draft else { return false }
        phase = .importing
        do {
            _ = try await repository.importTimetableDraft(draft)
            phase = .done
            return true
        } catch {
            phase = .error
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func inspectContext() async throws -> ImportContext {
        let script = """
        (() => ({
          url: window.location.href,
          title: document.title,
          textSample: (document.body?.innerText || '').slice(0, 2000),
          htmlSample: (document.body?.innerHTML || '').slice(0, 3000),
          html: document.documentElement?.outerHTML || ''
        }))();
        """
        guard let raw = try await proxy.evaluate(script) as? [String: Any] else {
            throw AppError.importCapture(L10n.tr("Unable to read the current page content."))
        }
        return ImportContext(
            url: raw["url"] as? String ?? sourceURL,
            title: raw["title"] as? String,
            textSample: raw["textSample"] as? String,
            htmlSample: raw["htmlSample"] as? String,
            html: raw["html"] as? String
        )
    }
}
