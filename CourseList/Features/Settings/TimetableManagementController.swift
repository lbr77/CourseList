import ConfigurableKit
import UIKit

extension Notification.Name {
    static let timetableRepositoryDidChange = Notification.Name("CourseList.timetableRepositoryDidChange")
}

@MainActor
final class TimetableManagementController: UIViewController {
    private let repository: any TimetableRepositoryProtocol
    private let onImportTap: () -> Void
    private let onCreateTimetable: () -> Void
    private let onEditTimetable: (String?) -> Void
    private let onRepositoryChanged: () -> Void

    private var timetables: [Timetable] = []
    private var loadError: Error?
    private var refreshError: Error?
    private var isLoading = true
    private var isRefreshing = false
    private var hasLoadedOnce = false
    private var contentController: UIViewController?

    init(
        repository: any TimetableRepositoryProtocol,
        onImportTap: @escaping () -> Void,
        onCreateTimetable: @escaping () -> Void,
        onEditTimetable: @escaping (String?) -> Void,
        onRepositoryChanged: @escaping () -> Void
    ) {
        self.repository = repository
        self.onImportTap = onImportTap
        self.onCreateTimetable = onCreateTimetable
        self.onEditTimetable = onEditTimetable
        self.onRepositoryChanged = onRepositoryChanged
        super.init(nibName: nil, bundle: nil)
        title = L10n.tr("Timetable management")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.title = L10n.tr("Timetable management")
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: nil,
            image: UIImage(systemName: "plus"),
            primaryAction: nil,
            menu: makeAddMenu()
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(repositoryDidChange),
            name: .timetableRepositoryDidChange,
            object: nil
        )

        render()
        Task { await reloadData() }
    }

    @objc private func repositoryDidChange() {
        onRepositoryChanged()
        Task { await reloadData() }
    }

    private func reloadData() async {
        if !hasLoadedOnce {
            isLoading = true
            loadError = nil
            refreshError = nil
            render()
        } else {
            isRefreshing = true
            refreshError = nil
            render()
        }

        do {
            timetables = try await repository.listTimetables().sorted { shouldDisplayTimetableBefore($0, $1) }
            loadError = nil
            refreshError = nil
        } catch {
            if hasLoadedOnce && !timetables.isEmpty {
                refreshError = error
            } else {
                loadError = error
            }
        }

        hasLoadedOnce = true
        isLoading = false
        isRefreshing = false
        render()
    }

    private func render() {
        let controller = ConfigurableViewController(manifest: makeManifest())
        controller.title = title
        replaceContent(with: controller)
    }

    private func replaceContent(with controller: UIViewController) {
        if let contentController {
            contentController.willMove(toParent: nil)
            contentController.view.removeFromSuperview()
            contentController.removeFromParent()
        }

        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        controller.didMove(toParent: self)
        contentController = controller
    }

    private func makeManifest() -> ConfigurableManifest {
        var objects: [ConfigurableObject] = []

        if isLoading && !hasLoadedOnce {
            objects.append(loadingObject(text: L10n.tr("Reading class schedule...")))
        } else if let loadError, timetables.isEmpty {
            objects.append(errorObject(error: loadError))
        } else {

            if timetables.isEmpty {
                objects.append(infoObject(text: L10n.tr("There is no class schedule yet, click + in the upper right corner to create a new one or import it.")))
            } else {
                objects.append(contentsOf: timetables.map(makeTimetableObject))
            }
        }

        return ConfigurableManifest(
            title: L10n.tr("Timetable management"),
            list: objects,
            footer: footerText
        )
    }

    private func makeAddMenu() -> UIMenu {
        UIMenu(children: [
            UIAction(
                title: L10n.tr("Academic Affairs Import"),
                image: UIImage(systemName: "square.and.arrow.down")
            ) { [weak self] _ in
                self?.onImportTap()
            },
            UIAction(
                title: L10n.tr("Create a new class schedule"),
                image: UIImage(systemName: "square.and.pencil")
            ) { [weak self] _ in
                self?.onCreateTimetable()
            },
        ])
    }

    private func makeTimetableObject(_ timetable: Timetable) -> ConfigurableObject {
        ConfigurableObject(
            icon: iconName(for: timetable),
            title: timetable.name,
            explain: buildTimetableSummary(timetable),
            ephemeralAnnotation: .action { _ in
                self.onEditTimetable(timetable.id)
            }
        )
    }

    private func iconName(for timetable: Timetable) -> String {
        switch resolveTimetablePhase(timetable) {
        case .current:
            return "calendar.badge.clock"
        case .upcoming:
            return "calendar.badge.plus"
        case .past:
            return "calendar.badge.minus"
        case .unknown:
            return "calendar"
        }
    }

    private func loadingObject(text: String) -> ConfigurableObject {
        ConfigurableObject(customView: {
            let label = UILabel()
            label.numberOfLines = 0
            label.textAlignment = .center
            label.font = .preferredFont(forTextStyle: .body)
            label.textColor = .secondaryLabel
            label.text = text
            return label
        })
    }

    private func infoObject(text: String) -> ConfigurableObject {
        ConfigurableObject(customView: {
            let label = UILabel()
            label.numberOfLines = 0
            label.textAlignment = .center
            label.font = .preferredFont(forTextStyle: .body)
            label.textColor = .secondaryLabel
            label.text = text
            return label
        })
    }

    private func errorObject(error: Error) -> ConfigurableObject {
        ConfigurableObject(
            icon: "exclamationmark.triangle",
            title: L10n.tr("Read failed"),
            explain: error.localizedDescription,
            ephemeralAnnotation: .action { _ in
                Task { await self.reloadData() }
            }
        )
    }

    private var footerText: String {
        if isLoading && !hasLoadedOnce {
            return L10n.tr("Reading class schedule data...")
        }
        if isRefreshing {
            return L10n.tr("Refreshing class schedule data...")
        }
        if let refreshError {
            return "刷新失败：\(refreshError.localizedDescription)"
        }
        if loadError != nil && timetables.isEmpty {
            return L10n.tr("Failed to read the class schedule. Click the entry above to try again.")
        }
        if timetables.isEmpty {
            return L10n.tr("If there is no class schedule, click + in the upper right corner to add one~")
        }
        return "共 \(timetables.count) 个课表，首页会按日期自动显示当前课表。"
    }
}
