import ConfigurableKit
import UIKit

@MainActor
final class CourseEditorCoordinator: NSObject {
    private static let weekRange = Array(1 ... 99)

    final class State {
        var courseId: String?
        var timetableId: String
        var name: String
        var teacher: String
        var location: String
        var color: String
        var note: String
        var meetings: [CourseMeetingInput]
        var periods: [TimetablePeriod]

        init(courseId: String?, timetableId: String, name: String, teacher: String, location: String, color: String, note: String, meetings: [CourseMeetingInput], periods: [TimetablePeriod]) {
            self.courseId = courseId
            self.timetableId = timetableId
            self.name = name
            self.teacher = teacher
            self.location = location
            self.color = color
            self.note = note
            self.meetings = meetings
            self.periods = periods
        }
    }

    private let repository: TimetableRepositoryProtocol
    fileprivate var state: State
    private let onFinished: () -> Void
    private weak var rootController: UIViewController?

    static func makeController(repository: TimetableRepositoryProtocol, courseId: String?, timetableId: String?, onFinished: @escaping () -> Void) -> UIViewController {
        let coordinator = CourseEditorCoordinator(repository: repository, state: placeholderState(timetableId: timetableId), onFinished: onFinished)
        let loadingController = CourseEditorLoadingViewController(title: courseId == nil ? "新建课程" : "编辑课程")
        loadingController.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: coordinator, action: #selector(CourseEditorCoordinator.cancelTapped))

        let nav = RetainedNavigationController(rootViewController: loadingController)
        nav.retainedObject = coordinator

        Task { [weak nav] in
            let loaded = await loadState(repository: repository, courseId: courseId, timetableId: timetableId)
            guard let nav else { return }
            coordinator.presentLoadedController(with: loaded, in: nav)
        }

        return nav
    }

    private static func placeholderState(timetableId: String?) -> State {
        State(
            courseId: nil,
            timetableId: timetableId ?? "",
            name: "",
            teacher: "",
            location: "",
            color: "",
            note: "",
            meetings: [defaultMeeting(periods: [])],
            periods: []
        )
    }

    private static func loadState(repository: TimetableRepositoryProtocol, courseId: String?, timetableId: String?) async -> State {
        if let courseId {
            let loadedCourse = try? await repository.getCourse(courseId: courseId)
            if let course = loadedCourse {
                let loadedPeriods = (try? await repository.listPeriods(timetableId: course.timetableId)) ?? []
                return State(
                    courseId: course.id,
                    timetableId: course.timetableId,
                    name: course.name,
                    teacher: course.teacher ?? "",
                    location: course.location ?? "",
                    color: course.color ?? "",
                    note: course.note ?? "",
                    meetings: course.meetings.map {
                        .init(
                            weekday: $0.weekday,
                            startWeek: $0.startWeek,
                            endWeek: $0.endWeek,
                            startPeriod: $0.startPeriod,
                            endPeriod: $0.endPeriod,
                            location: $0.location,
                            weekType: $0.weekType
                        )
                    },
                    periods: loadedPeriods
                )
            }
        }

        let timetables = (try? await repository.listTimetables()) ?? []
        let resolvedTimetableId = timetableId ?? resolvePreferredTimetable(timetables: timetables)?.id ?? ""
        let loadedPeriods = (try? await repository.listPeriods(timetableId: resolvedTimetableId)) ?? []

        return State(
            courseId: nil,
            timetableId: resolvedTimetableId,
            name: "",
            teacher: "",
            location: "",
            color: "",
            note: "",
            meetings: [defaultMeeting(periods: loadedPeriods)],
            periods: loadedPeriods
        )
    }

    private init(repository: TimetableRepositoryProtocol, state: State, onFinished: @escaping () -> Void) {
        self.repository = repository
        self.state = state
        self.onFinished = onFinished
        super.init()
    }

    private func presentLoadedController(with state: State, in navigationController: UINavigationController) {
        self.state = state

        let controller = CourseEditorController(coordinator: self)
        rootController = controller
        navigationController.setViewControllers([controller], animated: false)
    }

    var titleText: String {
        state.courseId == nil ? "新建课程" : "编辑课程"
    }

    var meetingsSummary: String {
        "共 \(state.meetings.count) 条"
    }

    var periods: [TimetablePeriod] {
        state.periods
    }

    func meeting(at index: Int) -> CourseMeetingInput? {
        guard state.meetings.indices.contains(index) else { return nil }
        return state.meetings[index]
    }

    func meetingTitle(at index: Int) -> String {
        "第 \(index + 1) 条"
    }

    func description(for meeting: CourseMeetingInput) -> String {
        var parts = [weekdayTitle(meeting.weekday)]
        parts.append("\(meeting.startWeek)-\(meeting.endWeek) 周")
        parts.append("第 \(meeting.startPeriod)-\(meeting.endPeriod) 节")
        parts.append(meeting.weekType.title)

        let timeText = buildPeriodTimeLabel(state.periods, startPeriod: meeting.startPeriod, endPeriod: meeting.endPeriod)
        if !timeText.isEmpty {
            parts.append(timeText)
        }
        if let location = normalizeOptionalText(meeting.location) {
            parts.append(location)
        }

        return parts.joined(separator: " · ")
    }

    func makeMeetingsController() -> UIViewController {
        CourseMeetingsController(coordinator: self)
    }

    func appendMeeting() {
        state.meetings.append(Self.defaultMeeting(periods: state.periods))
    }

    func deleteMeeting(at index: Int) {
        guard state.meetings.indices.contains(index) else { return }
        state.meetings.remove(at: index)
    }

    func presentEditor(for keyPath: ReferenceWritableKeyPath<State, String>, from view: UIView, title: String, message: String, placeholder: String, onChanged: ((String) -> Void)? = nil) {
        let input = AlertInputViewController(
            title: title,
            message: message,
            placeholder: placeholder,
            text: state[keyPath: keyPath],
            cancelButtonText: "取消",
            doneButtonText: "确定"
        ) { [weak self] output in
            guard let self else { return }
            state[keyPath: keyPath] = output
            onChanged?(output)
        }
        view.hostingViewController?.present(input, animated: true)
    }

    func presentMeetingWeekdayEditor(at index: Int, from view: UIView, onChanged: (() -> Void)? = nil) {
        guard let meeting = meeting(at: index) else { return }
        let options = (1 ... 7).map { weekdayTitle($0) }
        let picker = CourseEditorAlertOptionPickerViewController(
            title: "编辑星期",
            message: "选择这条时间所在的星期。",
            options: options,
            selectedIndex: max(0, min(meeting.weekday - 1, options.count - 1))
        ) { [weak self] selectedIndex in
            self?.updateMeeting(at: index) { current in
                current.weekday = selectedIndex + 1
            }
            onChanged?()
        }
        view.hostingViewController?.present(picker, animated: true)
    }

    func presentMeetingWeekEditor(at index: Int, from view: UIView, editingStart: Bool, onChanged: (() -> Void)? = nil) {
        guard let meeting = meeting(at: index) else { return }
        let options = Self.weekRange.map { "\($0) 周" }
        let currentValue = editingStart ? meeting.startWeek : meeting.endWeek
        let picker = CourseEditorAlertOptionPickerViewController(
            title: editingStart ? "编辑开始周" : "编辑结束周",
            message: "上下滑动选择周次。",
            options: options,
            selectedIndex: max(0, min(currentValue - 1, options.count - 1))
        ) { [weak self] selectedIndex in
            let newValue = Self.weekRange[selectedIndex]
            self?.updateMeeting(at: index) { current in
                if editingStart {
                    current.startWeek = newValue
                    current.endWeek = max(current.endWeek, newValue)
                } else {
                    current.endWeek = newValue
                    current.startWeek = min(current.startWeek, newValue)
                }
            }
            onChanged?()
        }
        view.hostingViewController?.present(picker, animated: true)
    }

    func presentMeetingPeriodEditor(at index: Int, from view: UIView, editingStart: Bool, onChanged: (() -> Void)? = nil) {
        guard let meeting = meeting(at: index) else { return }
        let periodRange = availablePeriodRange
        let options = periodRange.map { "第 \($0) 节" }
        let currentValue = editingStart ? meeting.startPeriod : meeting.endPeriod
        let picker = CourseEditorAlertOptionPickerViewController(
            title: editingStart ? "编辑开始节" : "编辑结束节",
            message: state.periods.isEmpty ? "当前课表还没有节次配置，先用默认值占位。" : "上下滑动选择节次。",
            options: options,
            selectedIndex: max(0, min(currentValue - 1, options.count - 1))
        ) { [weak self] selectedIndex in
            let newValue = periodRange[selectedIndex]
            self?.updateMeeting(at: index) { current in
                if editingStart {
                    current.startPeriod = newValue
                    current.endPeriod = max(current.endPeriod, newValue)
                } else {
                    current.endPeriod = newValue
                    current.startPeriod = min(current.startPeriod, newValue)
                }
            }
            onChanged?()
        }
        view.hostingViewController?.present(picker, animated: true)
    }

    func presentMeetingWeekTypeEditor(at index: Int, from view: UIView, onChanged: (() -> Void)? = nil) {
        guard let meeting = meeting(at: index) else { return }
        let options = WeekType.allCases.map(\.title)
        let picker = CourseEditorAlertOptionPickerViewController(
            title: "编辑单双周",
            message: "选择这条时间的生效周类型。",
            options: options,
            selectedIndex: max(0, WeekType.allCases.firstIndex(of: meeting.weekType) ?? 0)
        ) { [weak self] selectedIndex in
            self?.updateMeeting(at: index) { current in
                current.weekType = WeekType.allCases[selectedIndex]
            }
            onChanged?()
        }
        view.hostingViewController?.present(picker, animated: true)
    }

    func presentMeetingLocationEditor(at index: Int, from view: UIView, onChanged: (() -> Void)? = nil) {
        guard let meeting = meeting(at: index) else { return }
        let input = AlertInputViewController(
            title: "编辑本次地点",
            message: "",
            placeholder: "逸夫教学楼",
            text: meeting.location ?? "",
            cancelButtonText: "取消",
            doneButtonText: "确定"
        ) { [weak self] output in
            self?.updateMeeting(at: index) { current in
                current.location = normalizeOptionalText(output)
            }
            onChanged?()
        }
        view.hostingViewController?.present(input, animated: true)
    }

    @objc func deleteTapped() {
        Task { await deleteCourse() }
    }

    @objc func cancelTapped() {
        onFinished()
    }

    @objc func saveTapped() {
        Task {
            do {
                let input = SaveCourseInput(
                    id: state.courseId,
                    timetableId: state.timetableId,
                    name: state.name,
                    teacher: normalizeOptionalText(state.teacher),
                    location: normalizeOptionalText(state.location),
                    color: normalizeOptionalText(state.color),
                    note: normalizeOptionalText(state.note),
                    meetings: state.meetings
                )

                let warnings = try await repository.findCourseConflicts(input: input)
                if warnings.isEmpty {
                    _ = try await repository.saveCourse(input: input)
                    onFinished()
                } else {
                    presentConflictDialog(warnings: warnings, input: input)
                }
            } catch {
                presentError(error)
            }
        }
    }

    private func updateMeeting(at index: Int, _ mutate: (inout CourseMeetingInput) -> Void) {
        guard state.meetings.indices.contains(index) else { return }
        mutate(&state.meetings[index])
        sanitizeMeeting(at: index)
    }

    private func sanitizeMeeting(at index: Int) {
        guard state.meetings.indices.contains(index) else { return }
        let maxWeek = Self.weekRange.last ?? 99
        let maxPeriod = availablePeriodRange.last ?? 1

        state.meetings[index].weekday = min(max(state.meetings[index].weekday, 1), 7)
        state.meetings[index].startWeek = min(max(state.meetings[index].startWeek, 1), maxWeek)
        state.meetings[index].endWeek = min(max(state.meetings[index].endWeek, state.meetings[index].startWeek), maxWeek)
        state.meetings[index].startPeriod = min(max(state.meetings[index].startPeriod, 1), maxPeriod)
        state.meetings[index].endPeriod = min(max(state.meetings[index].endPeriod, state.meetings[index].startPeriod), maxPeriod)
    }

    private var availablePeriodRange: [Int] {
        let count = max(1, state.periods.count)
        return Array(1 ... count)
    }

    private func presentConflictDialog(warnings: [CourseConflictWarning], input: SaveCourseInput) {
        let alert = UIAlertController(title: "发现时间冲突", message: warnings.map { $0.message }.joined(separator: "\n"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "继续保存", style: .default) { _ in
            Task {
                do {
                    _ = try await self.repository.saveCourse(input: input)
                    self.onFinished()
                } catch {
                    self.presentError(error)
                }
            }
        })
        rootController?.present(alert, animated: true)
    }

    private func deleteCourse() async {
        guard let courseId = state.courseId else { return }
        do {
            try await repository.deleteCourse(courseId: courseId)
            onFinished()
        } catch {
            presentError(error)
        }
    }

    private func presentError(_ error: Error) {
        let alert = UIAlertController(title: "操作失败", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        rootController?.present(alert, animated: true)
    }

    private static func defaultMeeting(periods: [TimetablePeriod]) -> CourseMeetingInput {
        .init(
            weekday: 1,
            startWeek: 1,
            endWeek: 16,
            startPeriod: 1,
            endPeriod: min(2, max(1, periods.count)),
            location: nil,
            weekType: .all
        )
    }
}

private final class CourseEditorController: CourseEditorReloadableStackScrollController {
    private unowned let coordinator: CourseEditorCoordinator

    init(coordinator: CourseEditorCoordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
        title = coordinator.titleText
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: coordinator, action: #selector(CourseEditorCoordinator.cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "保存", style: .done, target: coordinator, action: #selector(CourseEditorCoordinator.saveTapped))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        rebuildContent()
    }

    override func buildContent() {
        appendEditableField(
            icon: "book",
            title: "课程名称",
            description: nil,
            value: coordinator.state.name,
            placeholder: "高等数学"
        ) { [weak coordinator] view in
            coordinator?.presentEditor(
                for: \CourseEditorCoordinator.State.name,
                from: view,
                title: "编辑课程名称",
                message: "课程的显示名称。",
                placeholder: "高等数学"
            ) { output in
                view.configure(value: output.isEmpty ? "未设置" : output)
            }
        }

        appendEditableField(
            icon: "person",
            title: "教师",
            description: nil,
            value: coordinator.state.teacher,
            placeholder: "李华"
        ) { [weak coordinator] view in
            coordinator?.presentEditor(
                for: \CourseEditorCoordinator.State.teacher,
                from: view,
                title: "编辑教师",
                message: "",
                placeholder: "李华"
            ) { output in
                view.configure(value: output.isEmpty ? "未设置" : output)
            }
        }

        appendEditableField(
            icon: "mappin.and.ellipse",
            title: "地点",
            description: nil,
            value: coordinator.state.location,
            placeholder: "逸夫教学楼"
        ) { [weak coordinator] view in
            coordinator?.presentEditor(
                for: \CourseEditorCoordinator.State.location,
                from: view,
                title: "编辑地点",
                message: "",
                placeholder: "逸夫教学楼"
            ) { output in
                view.configure(value: output.isEmpty ? "未设置" : output)
            }
        }

        appendEditableField(
            icon: "paintpalette",
            title: "颜色",
            description: nil,
            value: coordinator.state.color,
            placeholder: "#5B8FF9"
        ) { [weak coordinator] view in
            coordinator?.presentEditor(
                for: \CourseEditorCoordinator.State.color,
                from: view,
                title: "编辑颜色",
                message: "",
                placeholder: "#5B8FF9"
            ) { output in
                view.configure(value: output.isEmpty ? "未设置" : output)
            }
        }

        appendEditableField(
            icon: "note.text",
            title: "备注",
            description: nil,
            value: coordinator.state.note,
            placeholder: "老师要手写签到，快去"
        ) { [weak coordinator] view in
            coordinator?.presentEditor(
                for: \CourseEditorCoordinator.State.note,
                from: view,
                title: "编辑备注",
                message: "",
                placeholder: "老师要手写签到，快去"
            ) { output in
                view.configure(value: output.isEmpty ? "未设置" : output)
            }
        }

        appendPage(
            icon: "clock",
            title: "上课时间",
            description: coordinator.meetingsSummary
        ) { [weak coordinator] in
            coordinator?.makeMeetingsController()
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView().with(footer: "保存时会进行时间冲突检测。")
        ) { $0.top /= 2 }

        if coordinator.state.courseId != nil {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView().with(header: "管理")
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            let deleteAction = ConfigurableActionView { @MainActor [weak coordinator] _ in
                coordinator?.deleteTapped()
            }
            deleteAction.configure(icon: UIImage(systemName: "trash"))
            deleteAction.configure(title: "删除课程")
            deleteAction.configure(description: "永久删除这门课程及其全部上课时间。")
            deleteAction.titleLabel.textColor = .systemRed
            deleteAction.iconView.tintColor = .systemRed
            deleteAction.descriptionLabel.textColor = .systemRed
            deleteAction.imageView.tintColor = .systemRed
            stackView.addArrangedSubviewWithMargin(deleteAction)
            stackView.addArrangedSubview(SeparatorView())
        }

        stackView.addArrangedSubviewWithMargin(UIView())
    }

    private func appendEditableField(icon: String, title: String, description: String?, value: String, placeholder: String, tap: @escaping (ConfigurableInfoView) -> Void) {
        let view = ConfigurableInfoView()
        view.configure(icon: UIImage(systemName: icon))
        view.configure(title: title)
        view.configure(description: description ?? "")
        view.configure(value: value.isEmpty ? "未设置" : value)
        view.setTapBlock(tap)
        stackView.addArrangedSubviewWithMargin(view)
        stackView.addArrangedSubview(SeparatorView())
    }

    private func appendPage(icon: String, title: String, description: String, page: @escaping () -> UIViewController?) {
        let view = ConfigurablePageView(page: page)
        view.configure(icon: UIImage(systemName: icon))
        view.configure(title: title)
        view.configure(description: description)
        stackView.addArrangedSubviewWithMargin(view)
        stackView.addArrangedSubview(SeparatorView())
    }
}

private final class CourseMeetingsController: CourseEditorReloadableStackScrollController {
    private unowned let coordinator: CourseEditorCoordinator

    init(coordinator: CourseEditorCoordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
        title = "上课时间"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            style: .plain,
            target: self,
            action: #selector(addMeetingTapped)
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        rebuildContent()
    }

    override func buildContent() {
        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: "时间")
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        for index in coordinator.state.meetings.indices {
            let page = ConfigurablePageView(page: { [weak self] in
                guard let self else { return nil }
                return CourseMeetingDetailController(coordinator: coordinator, meetingIndex: index)
            })
            page.configure(icon: UIImage(systemName: "calendar.badge.clock"))
            page.configure(title: coordinator.meetingTitle(at: index))
            page.configure(description: coordinator.description(for: coordinator.state.meetings[index]))
            stackView.addArrangedSubviewWithMargin(page)
            stackView.addArrangedSubview(SeparatorView())
        }

        if coordinator.state.meetings.isEmpty {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(footer: "还没有上课时间，点击右上方“添加”开始创建。")
            ) { $0.top /= 2 }
        } else if coordinator.periods.isEmpty {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(footer: "当前课表还没有节次配置，保存课程前请先补充课表节次。")
            ) { $0.top /= 2 }
        }

        stackView.addArrangedSubviewWithMargin(UIView())
    }

    @objc private func addMeetingTapped() {
        coordinator.appendMeeting()
        rebuildContent()
    }
}

private final class CourseMeetingDetailController: CourseEditorReloadableStackScrollController {
    private unowned let coordinator: CourseEditorCoordinator
    private let meetingIndex: Int

    init(coordinator: CourseEditorCoordinator, meetingIndex: Int) {
        self.coordinator = coordinator
        self.meetingIndex = meetingIndex
        super.init(nibName: nil, bundle: nil)
        title = coordinator.meetingTitle(at: meetingIndex)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        rebuildContent()
    }

    override func buildContent() {
        guard let meeting = coordinator.meeting(at: meetingIndex) else {
            navigationController?.popViewController(animated: true)
            return
        }

        appendEditableField(
            icon: "calendar",
            title: "星期",
            description: nil,
            value: weekdayTitle(meeting.weekday),
            placeholder: "周一"
        ) { [weak self] view in
            self?.coordinator.presentMeetingWeekdayEditor(at: self?.meetingIndex ?? 0, from: view) {
                self?.rebuildContent()
            }
        }

        appendEditableField(
            icon: "number.square",
            title: "开始周",
            description: nil,
            value: "\(meeting.startWeek) 周",
            placeholder: "1 周"
        ) { [weak self] view in
            self?.coordinator.presentMeetingWeekEditor(at: self?.meetingIndex ?? 0, from: view, editingStart: true) {
                self?.rebuildContent()
            }
        }

        appendEditableField(
            icon: "number.square",
            title: "结束周",
            description: nil,
            value: "\(meeting.endWeek) 周",
            placeholder: "16 周"
        ) { [weak self] view in
            self?.coordinator.presentMeetingWeekEditor(at: self?.meetingIndex ?? 0, from: view, editingStart: false) {
                self?.rebuildContent()
            }
        }

        appendEditableField(
            icon: "clock.badge",
            title: "开始节",
            description: nil,
            value: "第 \(meeting.startPeriod) 节",
            placeholder: "第 1 节"
        ) { [weak self] view in
            self?.coordinator.presentMeetingPeriodEditor(at: self?.meetingIndex ?? 0, from: view, editingStart: true) {
                self?.rebuildContent()
            }
        }

        appendEditableField(
            icon: "clock.badge",
            title: "结束节",
            description: nil,
            value: "第 \(meeting.endPeriod) 节",
            placeholder: "第 2 节"
        ) { [weak self] view in
            self?.coordinator.presentMeetingPeriodEditor(at: self?.meetingIndex ?? 0, from: view, editingStart: false) {
                self?.rebuildContent()
            }
        }

        appendEditableField(
            icon: "repeat",
            title: "单双周",
            description: nil,
            value: meeting.weekType.title,
            placeholder: "全部"
        ) { [weak self] view in
            self?.coordinator.presentMeetingWeekTypeEditor(at: self?.meetingIndex ?? 0, from: view) {
                self?.rebuildContent()
            }
        }

        appendEditableField(
            icon: "mappin.and.ellipse",
            title: "本次地点",
            description: nil,
            value: normalizeOptionalText(meeting.location) ?? "未设置",
            placeholder: "逸夫教学楼"
        ) { [weak self] view in
            self?.coordinator.presentMeetingLocationEditor(at: self?.meetingIndex ?? 0, from: view) {
                self?.rebuildContent()
            }
        }

        let timeText = buildPeriodTimeLabel(coordinator.periods, startPeriod: meeting.startPeriod, endPeriod: meeting.endPeriod)
        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView().with(footer: timeText.isEmpty ? "当前还没有可对应的节次时间。" : "对应时间：\(timeText)")
        ) { $0.top /= 2 }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: "管理")
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        let deleteAction = ConfigurableActionView { @MainActor [weak self] _ in
            self?.deleteMeeting()
        }
        deleteAction.configure(icon: UIImage(systemName: "trash"))
        deleteAction.configure(title: "删除本条")
        deleteAction.configure(description: "删除这条上课时间。")
        deleteAction.titleLabel.textColor = .systemRed
        deleteAction.iconView.tintColor = .systemRed
        deleteAction.descriptionLabel.textColor = .systemRed
        deleteAction.imageView.tintColor = .systemRed
        stackView.addArrangedSubviewWithMargin(deleteAction)
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(UIView())
    }

    private func deleteMeeting() {
        coordinator.deleteMeeting(at: meetingIndex)
        navigationController?.popViewController(animated: true)
    }

    private func appendEditableField(icon: String, title: String, description: String?, value: String, placeholder: String, tap: @escaping (ConfigurableInfoView) -> Void) {
        let view = ConfigurableInfoView()
        view.configure(icon: UIImage(systemName: icon))
        view.configure(title: title)
        view.configure(description: description ?? "")
        view.configure(value: value.isEmpty ? placeholder : value)
        view.setTapBlock(tap)
        stackView.addArrangedSubviewWithMargin(view)
        stackView.addArrangedSubview(SeparatorView())
    }
}

private final class CourseEditorAlertOptionPickerContentController: AlertContentController, UIPickerViewDataSource, UIPickerViewDelegate {
    let picker = UIPickerView()

    private let options: [String]

    init(title: String = "", message: String = "", options: [String], selectedIndex: Int, setupActions: @escaping (ActionContext) -> Void) {
        self.options = options
        super.init(title: title, message: message, setupActions: setupActions)

        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.dataSource = self
        picker.delegate = self

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(picker)

        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: container.topAnchor),
            picker.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            picker.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: 216),
        ])

        customViews.append(container)
        picker.selectRow(max(0, min(selectedIndex, options.count - 1)), inComponent: 0, animated: false)
    }

    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        _ = pickerView
        return 1
    }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        _ = pickerView
        _ = component
        return options.count
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        _ = pickerView
        _ = component
        return options[row]
    }
}

private final class CourseEditorAlertOptionPickerViewController: AlertViewController {
    convenience init(
        title: String,
        message: String = "",
        options: [String],
        selectedIndex: Int,
        cancelButtonText: String = "取消",
        doneButtonText: String = "确定",
        onConfirm: @escaping (Int) -> Void
    ) {
        var controller: CourseEditorAlertOptionPickerContentController!
        controller = CourseEditorAlertOptionPickerContentController(
            title: title,
            message: message,
            options: options,
            selectedIndex: selectedIndex
        ) { context in
            context.addAction(title: cancelButtonText) {
                context.dispose()
            }
            context.addAction(title: doneButtonText, attribute: .accent) {
                context.dispose {
                    onConfirm(controller.picker.selectedRow(inComponent: 0))
                }
            }
        }

        self.init(contentViewController: controller)
    }

    required init(contentViewController: UIViewController) {
        super.init(contentViewController: contentViewController)
    }
}

private class CourseEditorReloadableStackScrollController: StackScrollController {
    override func setupContentViews() {
        buildContent()
    }

    func buildContent() {}

    func rebuildContent() {
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        buildContent()
        for separator in stackView.subviews.compactMap({ $0 as? SeparatorView }) {
            separator.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                separator.heightAnchor.constraint(equalToConstant: 0.5),
                separator.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            ])
        }
    }
}

private final class CourseEditorLoadingViewController: UIViewController {
    private let titleText: String

    init(title: String) {
        self.titleText = title
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.title = titleText
        navigationItem.largeTitleDisplayMode = .never

        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.startAnimating()

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "正在加载…"
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [indicator, label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}

private func weekdayTitle(_ weekday: Int) -> String {
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
