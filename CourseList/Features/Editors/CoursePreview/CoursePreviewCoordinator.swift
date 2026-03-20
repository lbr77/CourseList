import ConfigurableKit
import UIKit

@MainActor
enum CoursePreviewCoordinator {
    static func makeController(
        repository: any TimetableRepositoryProtocol,
        courseId: String,
        selection: CoursePreviewSelectionContext,
        onFinished: @escaping () -> Void,
        onEditCourse: @escaping (CourseWithMeetings) -> Void
    ) -> UIViewController {
        let controller = CoursePreviewController(
            repository: repository,
            courseId: courseId,
            selection: selection,
            onFinished: onFinished,
            onEditCourse: onEditCourse
        )
        return RetainedNavigationController(rootViewController: controller)
    }
}

@MainActor
private final class CoursePreviewController: UIViewController {
    private let repository: any TimetableRepositoryProtocol
    private let courseId: String
    private let selection: CoursePreviewSelectionContext
    private let onFinished: () -> Void
    private let onEditCourse: (CourseWithMeetings) -> Void

    private var course: CourseWithMeetings?
    private var timetable: Timetable?
    private var periods: [TimetablePeriod] = []
    private var loadError: Error?
    private var refreshError: Error?
    private var isLoading = true
    private var isRefreshing = false
    private var hasLoadedOnce = false
    private var contentController: UIViewController?

    init(
        repository: any TimetableRepositoryProtocol,
        courseId: String,
        selection: CoursePreviewSelectionContext,
        onFinished: @escaping () -> Void,
        onEditCourse: @escaping (CourseWithMeetings) -> Void
    ) {
        self.repository = repository
        self.courseId = courseId
        self.selection = selection
        self.onFinished = onFinished
        self.onEditCourse = onEditCourse
        super.init(nibName: nil, bundle: nil)
        title = L10n.tr("Course preview")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )
        render()
        Task { await reloadData(showLoading: true) }
    }

    @objc private func closeTapped() {
        onFinished()
    }

    @objc private func editTapped() {
        guard let course else { return }
        onEditCourse(course)
    }

    private func reloadData(showLoading: Bool) async {
        if showLoading {
            if hasLoadedOnce {
                isRefreshing = true
                refreshError = nil
            } else {
                isLoading = true
                loadError = nil
            }
            render()
        }

        let previousCourse = course
        let previousTimetable = timetable
        let previousPeriods = periods

        do {
            guard let loadedCourse = try await repository.getCourse(courseId: courseId) else {
                throw AppError.notFound(L10n.tr("The course does not exist and may have been deleted."))
            }

            async let periodsTask = repository.listPeriods(timetableId: loadedCourse.timetableId)
            async let timetablesTask = repository.listTimetables()

            let loadedPeriods = try await periodsTask
            let timetables = try await timetablesTask

            course = loadedCourse
            periods = loadedPeriods
            timetable = timetables.first(where: { $0.id == loadedCourse.timetableId })
            loadError = nil
            refreshError = nil
        } catch {
            if previousCourse != nil {
                course = previousCourse
                periods = previousPeriods
                timetable = previousTimetable
                refreshError = error
            } else {
                course = nil
                periods = []
                timetable = nil
                loadError = error
            }
        }

        hasLoadedOnce = true
        isLoading = false
        isRefreshing = false
        render()
    }

    private func render() {
        title = course?.name ?? L10n.tr("Course preview")
        navigationItem.rightBarButtonItem?.isEnabled = course != nil && !isLoading && !isRefreshing && loadError == nil

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
        if isLoading && !hasLoadedOnce {
            return ConfigurableManifest(
                title: L10n.tr("Course preview"),
                list: [loadingObject(text: L10n.tr("Reading course…"))],
                footer: L10n.tr("Reading course data...")
            )
        }

        if let loadError, course == nil {
            return ConfigurableManifest(
                title: L10n.tr("Course preview"),
                list: [errorObject(error: loadError)],
                footer: statusFooterText
            )
        }

        guard let course else {
            return ConfigurableManifest(
                title: L10n.tr("Course preview"),
                list: [infoObject(text: L10n.tr("The course does not exist and may have been deleted."))],
                footer: statusFooterText
            )
        }

        var objects: [ConfigurableObject] = []
        objects.append(
            ConfigurableObject(
                icon: "location.viewfinder",
                title: L10n.tr("Current period"),
                explain: currentSelectionSummary(course: course),
                ephemeralAnnotation: .action { _ in }
            )
        )
        objects.append(
            ConfigurableObject(
                icon: "calendar",
                title: timetable?.name ?? L10n.tr("The class schedule was not found"),
                explain: buildTimetableLine(),
                ephemeralAnnotation: .action { _ in }
            )
        )
        objects.append(
            ConfigurableObject(
                icon: "person",
                title: L10n.tr("teacher"),
                explain: normalizeOptionalText(course.teacher) ?? L10n.tr("not set"),
                ephemeralAnnotation: .action { _ in }
            )
        )
        objects.append(
            ConfigurableObject(
                icon: "note.text",
                title: L10n.tr("Remark"),
                explain: normalizeOptionalText(course.note) ?? L10n.tr("not set"),
                ephemeralAnnotation: .action { _ in }
            )
        )

        objects.append(
            ConfigurableObject(
                icon: "square.and.pencil",
                title: L10n.tr("Edit course"),
                explain: L10n.tr("Modify course information and class time"),
                ephemeralAnnotation: .action { _ in
                    self.editTapped()
                }
            )
        )

        return ConfigurableManifest(
            title: course.name,
            list: objects,
            footer: statusFooterText
        )
    }

    private func buildTimetableLine() -> String {
        guard let timetable else {
            return L10n.tr("Class schedule information is not available")
        }
        return "\(timetable.startDate) 开学 · \(timetable.weeksCount) 周"
    }

    private func currentSelectionSummary(course: CourseWithMeetings) -> String {
        var parts: [String] = []
        parts.append("\(weekdayLabel(selection.weekday)) 第\(selection.startPeriod)-\(selection.endPeriod)节")

        let timeText = selectionTimeText()
        if !timeText.isEmpty {
            parts.append(timeText)
        }

        parts.append("第\(selection.week)周")

        let location = normalizeOptionalText(selection.location) ?? normalizeOptionalText(course.location) ?? L10n.tr("No classroom set up")
        parts.append("教室：\(location)")
        return parts.joined(separator: " · ")
    }

    private func selectionTimeText() -> String {
        switch (normalizeOptionalText(selection.startTime), normalizeOptionalText(selection.endTime)) {
        case let (start?, end?):
            return "\(start)-\(end)"
        case let (start?, nil):
            return start
        case let (nil, end?):
            return end
        case (nil, nil):
            return ""
        }
    }

    private func meetingSummary(_ meeting: CourseMeeting) -> String {
        var parts: [String] = []
        parts.append(weekdayLabel(meeting.weekday))
        parts.append("\(meeting.startWeek)-\(meeting.endWeek) 周")
        parts.append("第 \(meeting.startPeriod)-\(meeting.endPeriod) 节")
        parts.append(meeting.weekType.title)

        let timeText = buildPeriodTimeLabel(periods, startPeriod: meeting.startPeriod, endPeriod: meeting.endPeriod)
        if !timeText.isEmpty {
            parts.append(timeText)
        }

        let location = normalizeOptionalText(meeting.location) ?? normalizeOptionalText(course?.location)
        if let location {
            parts.append(location)
        }

        return parts.joined(separator: " · ")
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
                Task { await self.reloadData(showLoading: true) }
            }
        )
    }

    private var statusFooterText: String {
        if isRefreshing {
            return L10n.tr("Refreshing course data...")
        }
        if let refreshError {
            return "刷新失败：\(refreshError.localizedDescription)"
        }
        if let loadError, course == nil {
            return L10n.tr("Tap the entry above to try again.")
        }
        if let course {
            return "共 \(course.meetings.count) 条上课时间"
        }
        return L10n.tr("Please return to the class schedule page to refresh and try again.")
    }

    private func weekdayLabel(_ weekday: Int) -> String {
        switch weekday {
        case 1: return L10n.tr("on Monday")
        case 2: return L10n.tr("Tuesday")
        case 3: return L10n.tr("Wednesday")
        case 4: return L10n.tr("Thursday")
        case 5: return L10n.tr("Friday")
        case 6: return L10n.tr("Saturday")
        case 7: return L10n.tr("Sunday")
        default: return L10n.tr("on Monday")
        }
    }
}
