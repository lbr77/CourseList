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
        title = "课程预览"
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
                throw AppError.notFound("课程不存在，可能已经被删除。")
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
        title = course?.name ?? "课程预览"
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
                title: "课程预览",
                list: [loadingObject(text: "正在读取课程…")],
                footer: "正在读取课程数据…"
            )
        }

        if let loadError, course == nil {
            return ConfigurableManifest(
                title: "课程预览",
                list: [errorObject(error: loadError)],
                footer: statusFooterText
            )
        }

        guard let course else {
            return ConfigurableManifest(
                title: "课程预览",
                list: [infoObject(text: "课程不存在，可能已被删除。")],
                footer: statusFooterText
            )
        }

        var objects: [ConfigurableObject] = []
        objects.append(
            ConfigurableObject(
                icon: "location.viewfinder",
                title: "当前时段",
                explain: currentSelectionSummary(course: course),
                ephemeralAnnotation: .action { _ in }
            )
        )
        objects.append(
            ConfigurableObject(
                icon: "calendar",
                title: timetable?.name ?? "未找到所属课表",
                explain: buildTimetableLine(),
                ephemeralAnnotation: .action { _ in }
            )
        )
        objects.append(
            ConfigurableObject(
                icon: "person",
                title: "教师",
                explain: normalizeOptionalText(course.teacher) ?? "未设置",
                ephemeralAnnotation: .action { _ in }
            )
        )
        objects.append(
            ConfigurableObject(
                icon: "note.text",
                title: "备注",
                explain: normalizeOptionalText(course.note) ?? "未设置",
                ephemeralAnnotation: .action { _ in }
            )
        )

        objects.append(
            ConfigurableObject(
                icon: "square.and.pencil",
                title: "编辑课程",
                explain: "修改课程信息与上课时间",
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
            return "课表信息不可用"
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

        let location = normalizeOptionalText(selection.location) ?? normalizeOptionalText(course.location) ?? "未设置教室"
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
            title: "读取失败",
            explain: error.localizedDescription,
            ephemeralAnnotation: .action { _ in
                Task { await self.reloadData(showLoading: true) }
            }
        )
    }

    private var statusFooterText: String {
        if isRefreshing {
            return "正在刷新课程数据…"
        }
        if let refreshError {
            return "刷新失败：\(refreshError.localizedDescription)"
        }
        if let loadError, course == nil {
            return "点按上方条目可重试。"
        }
        if let course {
            return "共 \(course.meetings.count) 条上课时间"
        }
        return "请返回课表页刷新后重试。"
    }

    private func weekdayLabel(_ weekday: Int) -> String {
        switch weekday {
        case 1: return "周一"
        case 2: return "周二"
        case 3: return "周三"
        case 4: return "周四"
        case 5: return "周五"
        case 6: return "周六"
        case 7: return "周日"
        default: return "周一"
        }
    }
}
