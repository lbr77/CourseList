import Combine
import Foundation

@MainActor
final class AppContainer: ObservableObject {
    @Published private(set) var repository: TimetableRepositoryProtocol?
    @Published private(set) var isBootstrapping = true
    @Published private(set) var bootstrapError: String?

    init(repository: TimetableRepositoryProtocol? = nil) {
        if let repository {
            self.repository = repository
            isBootstrapping = false
            CourseNotificationService.shared.start(repository: repository)
            CourseWidgetSyncService.shared.start(repository: repository)
        } else {
            Task {
                await bootstrapRepository()
            }
        }
    }

    private func bootstrapRepository() async {
        do {
            let repository = try await Task.detached(priority: .userInitiated) { () -> TimetableRepositoryProtocol in
                let manager = try DatabaseManager()
                return TimetableRepository(manager: manager)
            }.value
            self.repository = repository
            bootstrapError = nil
            CourseNotificationService.shared.start(repository: repository)
            CourseWidgetSyncService.shared.start(repository: repository)
        } catch {
            repository = nil
            bootstrapError = L10n.tr("Database initialization failed: %@", error.localizedDescription)
        }
        isBootstrapping = false
    }
}
