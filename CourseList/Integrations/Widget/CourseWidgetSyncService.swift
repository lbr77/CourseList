import Foundation
import UIKit

#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
final class CourseWidgetSyncService {
    static let shared = CourseWidgetSyncService()

    private var repository: (any TimetableRepositoryProtocol)?
    private var observers: [NSObjectProtocol] = []
    private var started = false

    private init() {}

    func start(repository: any TimetableRepositoryProtocol) {
        self.repository = repository

        if !started {
            started = true
            installObservers()
        }

        Task {
            await syncNow()
        }
    }

    func syncNow(repository: (any TimetableRepositoryProtocol)? = nil) async {
        if let repository {
            self.repository = repository
        }

        guard let activeRepository = repository ?? self.repository else {
            return
        }

        let snapshot = await CourseWidgetSnapshotBuilder.make(repository: activeRepository)

        do {
            try CourseWidgetSnapshotStore.save(snapshot)
        } catch {
            return
        }

        #if canImport(WidgetKit)
        if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
    }

    private func installObservers() {
        let center = NotificationCenter.default

        observers.append(
            center.addObserver(forName: .timetableRepositoryDidChange, object: nil, queue: .main) { [weak self] _ in
                Task { await self?.syncNow() }
            }
        )
        observers.append(
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                Task { await self?.syncNow() }
            }
        )
        observers.append(
            center.addObserver(forName: UIApplication.significantTimeChangeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { await self?.syncNow() }
            }
        )
        observers.append(
            center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
                Task { await self?.syncNow() }
            }
        )
    }
}
