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
        var currentWeek: Int
        var weeksCount: Int
        var defaultWeekday: Int

        init(courseId: String?, timetableId: String, name: String, teacher: String, location: String, color: String, note: String, meetings: [CourseMeetingInput], periods: [TimetablePeriod], currentWeek: Int, weeksCount: Int, defaultWeekday: Int) {
            self.courseId = courseId
            self.timetableId = timetableId
            self.name = name
            self.teacher = teacher
            self.location = location
            self.color = color
            self.note = note
            self.meetings = meetings
            self.periods = periods
            self.currentWeek = currentWeek
            self.weeksCount = weeksCount
            self.defaultWeekday = defaultWeekday
        }
    }

    private let repository: TimetableRepositoryProtocol
    fileprivate var state: State
    private let onFinished: () -> Void
    private weak var rootController: UIViewController?

    static func makeController(repository: TimetableRepositoryProtocol, courseId: String?, timetableId: String?, onFinished: @escaping () -> Void) -> UIViewController {
        let coordinator = CourseEditorCoordinator(repository: repository, state: placeholderState(timetableId: timetableId), onFinished: onFinished)
        let loadingController = CourseEditorLoadingViewController(title: courseId == nil ? L10n.tr("Create new course") : L10n.tr("Edit course"))
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
        let defaultWeekday = currentWeekday()
        return State(
            courseId: nil,
            timetableId: timetableId ?? "",
            name: "",
            teacher: "",
            location: "",
            color: "",
            note: "",
            meetings: [defaultMeeting(periods: [], currentWeek: 1, weeksCount: 16, weekday: defaultWeekday)],
            periods: [],
            currentWeek: 1,
            weeksCount: 16,
            defaultWeekday: defaultWeekday
        )
    }

    private static func loadState(repository: TimetableRepositoryProtocol, courseId: String?, timetableId: String?) async -> State {
        if let courseId {
            let loadedCourse = try? await repository.getCourse(courseId: courseId)
            if let course = loadedCourse {
                let loadedPeriods = (try? await repository.listPeriods(timetableId: course.timetableId)) ?? []
                let timetables = (try? await repository.listTimetables()) ?? []
                let timetable = timetables.first(where: { $0.id == course.timetableId })
                let defaults = meetingDefaults(for: timetable)
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
                    periods: loadedPeriods,
                    currentWeek: defaults.currentWeek,
                    weeksCount: defaults.weeksCount,
                    defaultWeekday: defaults.weekday
                )
            }
        }

        let timetables = (try? await repository.listTimetables()) ?? []
        let timetable = (timetableId.flatMap { id in timetables.first(where: { $0.id == id }) }) ?? resolvePreferredTimetable(timetables: timetables)
        let resolvedTimetableId = timetable?.id ?? ""
        let loadedPeriods = (try? await repository.listPeriods(timetableId: resolvedTimetableId)) ?? []
        let defaults = meetingDefaults(for: timetable)

        return State(
            courseId: nil,
            timetableId: resolvedTimetableId,
            name: "",
            teacher: "",
            location: "",
            color: "",
            note: "",
            meetings: [defaultMeeting(periods: loadedPeriods, currentWeek: defaults.currentWeek, weeksCount: defaults.weeksCount, weekday: defaults.weekday)],
            periods: loadedPeriods,
            currentWeek: defaults.currentWeek,
            weeksCount: defaults.weeksCount,
            defaultWeekday: defaults.weekday
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
        state.courseId == nil ? L10n.tr("Create new course") : L10n.tr("Edit course")
    }

    var meetingsSummary: String {
        L10n.tr("%d items", state.meetings.count)
    }

    var periods: [TimetablePeriod] {
        state.periods
    }

    func meeting(at index: Int) -> CourseMeetingInput? {
        guard state.meetings.indices.contains(index) else { return nil }
        return state.meetings[index]
    }

    func meetingTitle(at index: Int) -> String {
        L10n.tr("Article %d", index + 1)
    }

    func description(for meeting: CourseMeetingInput) -> String {
        var parts = [weekdayTitle(meeting.weekday)]
        parts.append(L10n.tr("%d-%d weeks", meeting.startWeek, meeting.endWeek))
        parts.append(L10n.tr("Section %d-%d", meeting.startPeriod, meeting.endPeriod))
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
        state.meetings.append(Self.defaultMeeting(periods: state.periods, currentWeek: state.currentWeek, weeksCount: state.weeksCount, weekday: state.defaultWeekday))
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
            cancelButtonText: L10n.tr("Cancel"),
            doneButtonText: L10n.tr("Sure")
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
            title: L10n.tr("Editor's Week"),
            message: L10n.tr("Select the week this time falls on."),
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
        let options = Self.weekRange.map { L10n.tr("Week %d", $0) }
        let currentValue = editingStart ? meeting.startWeek : meeting.endWeek
        let picker = CourseEditorAlertOptionPickerViewController(
            title: editingStart ? L10n.tr("Editing start week") : L10n.tr("Edit end week"),
            message: L10n.tr("Swipe up or down to select a week."),
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
        let options = periodRange.map { L10n.tr("Period %d", $0) }
        let currentValue = editingStart ? meeting.startPeriod : meeting.endPeriod
        let picker = CourseEditorAlertOptionPickerViewController(
            title: editingStart ? L10n.tr("Edit start section") : L10n.tr("Edit end section"),
            message: state.periods.isEmpty ? L10n.tr("There is no section configuration in the current class schedule, so use the default value first.") : L10n.tr("Swipe up or down to select a section."),
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
            title: L10n.tr("Edit odd and fortnightly"),
            message: L10n.tr("Select the effective week type for this time."),
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
            title: L10n.tr("Edit this location"),
            message: "",
            placeholder: L10n.tr("Shaw Teaching Building"),
            text: meeting.location ?? "",
            cancelButtonText: L10n.tr("Cancel"),
            doneButtonText: L10n.tr("Sure")
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
        let alert = UIAlertController(title: L10n.tr("Time conflict found"), message: warnings.map { $0.message }.joined(separator: "\n"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.tr("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.tr("Continue to save"), style: .default) { _ in
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
        let alert = UIAlertController(title: L10n.tr("Operation failed"), message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.tr("Sure"), style: .default))
        rootController?.present(alert, animated: true)
    }

    private static func defaultMeeting(periods: [TimetablePeriod], currentWeek: Int, weeksCount: Int, weekday: Int) -> CourseMeetingInput {
        .init(
            weekday: weekday,
            startWeek: max(1, currentWeek),
            endWeek: max(max(1, currentWeek), weeksCount),
            startPeriod: 1,
            endPeriod: min(2, max(1, periods.count)),
            location: nil,
            weekType: .all
        )
    }

    private static func meetingDefaults(for timetable: Timetable?) -> (currentWeek: Int, weeksCount: Int, weekday: Int) {
        let weekday = currentWeekday()
        guard let timetable else {
            return (1, 16, weekday)
        }

        let currentWeek = clampWeek(getCurrentWeek(startDate: timetable.startDate), timetable: timetable)
        return (currentWeek, timetable.weeksCount, weekday)
    }

    private static func currentWeekday(on date: Date = Date()) -> Int {
        let weekday = Calendar(identifier: .gregorian).component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
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
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: L10n.tr("save"), style: .done, target: coordinator, action: #selector(CourseEditorCoordinator.saveTapped))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        rebuildContent()
    }

    override func buildContent() {
        appendEditableField(
            icon: "book",
            title: L10n.tr("Course name"),
            description: nil,
            value: coordinator.state.name,
            placeholder: L10n.tr("Advanced Mathematics")
        ) { [weak coordinator] view in
            coordinator?.presentEditor(
                for: \CourseEditorCoordinator.State.name,
                from: view,
                title: L10n.tr("Edit course name"),
                message: L10n.tr("The display name of the course."),
                placeholder: L10n.tr("Advanced Mathematics")
            ) { output in
                view.configure(value: output.isEmpty ? L10n.tr("not set") : output)
            }
        }

        appendEditableField(
            icon: "person",
            title: L10n.tr("teacher"),
            description: nil,
            value: coordinator.state.teacher,
            placeholder: L10n.tr("Li Hua")
        ) { [weak coordinator] view in
            coordinator?.presentEditor(
                for: \CourseEditorCoordinator.State.teacher,
                from: view,
                title: L10n.tr("Edit Teacher"),
                message: "",
                placeholder: L10n.tr("Li Hua")
            ) { output in
                view.configure(value: output.isEmpty ? L10n.tr("not set") : output)
            }
        }

        appendEditableField(
            icon: "mappin.and.ellipse",
            title: L10n.tr("Place"),
            description: nil,
            value: coordinator.state.location,
            placeholder: L10n.tr("Shaw Teaching Building")
        ) { [weak coordinator] view in
            coordinator?.presentEditor(
                for: \CourseEditorCoordinator.State.location,
                from: view,
                title: L10n.tr("Edit location"),
                message: ""                                                                                                                                           ,
                placeholder: L10n.tr("Shaw Teaching Building")
            ) { output in
                view.configure(value: output.isEmpty ? L10n.tr("not set") : output)
            }
        }

        appendEditableField(
            icon: "note.text",
            title: L10n.tr("Remark"),
            description: nil,
            value: coordinator.state.note,
            placeholder: L10n.tr("The teacher wants to sign in by hand. Go quickly.")
        ) { [weak coordinator] view in
            coordinator?.presentEditor(
                for: \CourseEditorCoordinator.State.note,
                from: view,
                title: L10n.tr("Editor's Notes"),
                message: "",
                placeholder: L10n.tr("The teacher wants to sign in by hand. Go quickly.")
            ) { output in
                view.configure(value: output.isEmpty ? L10n.tr("not set") : output)
            }
        }

        appendPage(
            icon: "clock",
            title: L10n.tr("Class time"),
            description: coordinator.meetingsSummary
        ) { [weak coordinator] in
            coordinator?.makeMeetingsController()
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView().with(footer: L10n.tr("Time conflict detection is performed when saving."))
        ) { $0.top /= 2 }

        if coordinator.state.courseId != nil {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView().with(header: L10n.tr("manage"))
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            let deleteAction = ConfigurableActionView { @MainActor [weak coordinator] _ in
                coordinator?.deleteTapped()
            }
            deleteAction.configure(icon: UIImage(systemName: "trash"))
            deleteAction.configure(title: L10n.tr("Delete course"))
            deleteAction.configure(description: L10n.tr("Permanently delete this course and all class times."))
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
        view.configure(value: value.isEmpty ? L10n.tr("not set") : value)
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
        title = L10n.tr("Class time")
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
            ConfigurableSectionHeaderView().with(header: L10n.tr("time"))
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
                ConfigurableSectionFooterView().with(footer: L10n.tr("There is no class time yet, click \"Add\" on the upper right to start creating."))
            ) { $0.top /= 2 }
        } else if coordinator.periods.isEmpty {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(footer: L10n.tr("The current class schedule does not have sections configured yet. Please add sections to the class schedule before saving the course."))
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
            title: L10n.tr("Week"),
            description: nil,
            value: weekdayTitle(meeting.weekday),
            placeholder: L10n.tr("on Monday")
        ) { [weak self] view in
            self?.coordinator.presentMeetingWeekdayEditor(at: self?.meetingIndex ?? 0, from: view) {
                self?.rebuildContent()
            }
        }

        appendEditableField(
            icon: "number.square",
            title: L10n.tr("start week"),
            description: nil,
            value: L10n.tr("Week %d", meeting.startWeek),
            placeholder: L10n.tr("1 week")
        ) { [weak self] view in
            self?.coordinator.presentMeetingWeekEditor(at: self?.meetingIndex ?? 0, from: view, editingStart: true) {
                self?.rebuildContent()
            }
        }

        appendEditableField(
            icon: "number.square",
            title: L10n.tr("end week"),
            description: nil,
            value: L10n.tr("Week %d", meeting.endWeek),
            placeholder: L10n.tr("16 weeks")
        ) { [weak self] view in
            self?.coordinator.presentMeetingWeekEditor(at: self?.meetingIndex ?? 0, from: view, editingStart: false) {
                self?.rebuildContent()
            }
        }

        appendEditableField(
            icon: "clock.badge",
            title: L10n.tr("start section"),
            description: nil,
            value: L10n.tr("Period %d", meeting.startPeriod),
            placeholder: L10n.tr("Section 1")
        ) { [weak self] view in
            self?.coordinator.presentMeetingPeriodEditor(at: self?.meetingIndex ?? 0, from: view, editingStart: true) {
                self?.rebuildContent()
            }
        }

        appendEditableField(
            icon: "clock.badge",
            title: L10n.tr("end section"),
            description: nil,
            value: L10n.tr("Period %d", meeting.endPeriod),
            placeholder: L10n.tr("Section 2")
        ) { [weak self] view in
            self?.coordinator.presentMeetingPeriodEditor(at: self?.meetingIndex ?? 0, from: view, editingStart: false) {
                self?.rebuildContent()
            }
        }

        appendEditableField(
            icon: "repeat",
            title: L10n.tr("Odd and even weeks"),
            description: nil,
            value: meeting.weekType.title,
            placeholder: L10n.tr("all")
        ) { [weak self] view in
            self?.coordinator.presentMeetingWeekTypeEditor(at: self?.meetingIndex ?? 0, from: view) {
                self?.rebuildContent()
            }
        }

        appendEditableField(
            icon: "mappin.and.ellipse",
            title: L10n.tr("This time location"),
            description: nil,
            value: normalizeOptionalText(meeting.location) ?? L10n.tr("not set"),
            placeholder: L10n.tr("Shaw Teaching Building")
        ) { [weak self] view in
            self?.coordinator.presentMeetingLocationEditor(at: self?.meetingIndex ?? 0, from: view) {
                self?.rebuildContent()
            }
        }

        let timeText = buildPeriodTimeLabel(coordinator.periods, startPeriod: meeting.startPeriod, endPeriod: meeting.endPeriod)
        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView().with(footer: timeText.isEmpty ? L10n.tr("There is currently no corresponding section time.") : "对应时间：\(timeText)")
        ) { $0.top /= 2 }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: L10n.tr("manage"))
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        let deleteAction = ConfigurableActionView { @MainActor [weak self] _ in
            self?.deleteMeeting()
        }
        deleteAction.configure(icon: UIImage(systemName: "trash"))
        deleteAction.configure(title: L10n.tr("Delete this article"))
        deleteAction.configure(description: L10n.tr("Delete this class time."))
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
        cancelButtonText: String = L10n.tr("Cancel"),
        doneButtonText: String = L10n.tr("Sure"),
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
        label.text = L10n.tr("Loading…")
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
