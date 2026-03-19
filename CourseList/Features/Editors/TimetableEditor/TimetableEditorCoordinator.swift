import ConfigurableKit
import UIKit

@MainActor
final class TimetableEditorCoordinator: NSObject {
    final class State {
        var timetableId: String?
        var name: String
        var termName: String
        var startDate: String
        var weeksCount: String
        var periods: [TimetablePeriodInput]

        init(timetableId: String?, name: String, termName: String, startDate: String, weeksCount: String, periods: [TimetablePeriodInput]) {
            self.timetableId = timetableId
            self.name = name
            self.termName = termName
            self.startDate = startDate
            self.weeksCount = weeksCount
            self.periods = periods
        }
    }

    private let repository: TimetableRepositoryProtocol
    fileprivate var state: State
    private let onFinished: () -> Void
    private weak var rootController: UIViewController?

    static func makeController(repository: TimetableRepositoryProtocol, timetableId: String?, onFinished: @escaping () -> Void) -> UIViewController {
        let coordinator = TimetableEditorCoordinator(repository: repository, state: placeholderState(), onFinished: onFinished)
        let loadingController = TimetableEditorLoadingViewController(title: timetableId == nil ? "新建课表" : "编辑课表")
        loadingController.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: coordinator, action: #selector(TimetableEditorCoordinator.cancelTapped))

        let navigationController = RetainedNavigationController(rootViewController: loadingController)
        navigationController.retainedObject = coordinator

        Task { [weak navigationController] in
            let loaded = await loadState(repository: repository, timetableId: timetableId)
            guard let navigationController else { return }
            coordinator.presentLoadedController(with: loaded, in: navigationController)
        }

        return navigationController
    }

    private static func placeholderState() -> State {
        State(
            timetableId: nil,
            name: "",
            termName: "",
            startDate: formatDateInput(Date()),
            weeksCount: "16",
            periods: [
                .init(periodIndex: 1, startTime: "08:00", endTime: "08:45"),
                .init(periodIndex: 2, startTime: "08:55", endTime: "09:40"),
            ]
        )
    }

    private static func loadState(repository: TimetableRepositoryProtocol, timetableId: String?) async -> State {
        if let timetableId {
            async let timetablesTask = repository.listTimetables()
            async let periodsTask = repository.listPeriods(timetableId: timetableId)

            let timetables = (try? await timetablesTask) ?? []
            let loadedPeriods = (try? await periodsTask) ?? []

            if let timetable = timetables.first(where: { $0.id == timetableId }) {
                return State(
                    timetableId: timetable.id,
                    name: timetable.name,
                    termName: timetable.termName,
                    startDate: timetable.startDate,
                    weeksCount: String(timetable.weeksCount),
                    periods: loadedPeriods.map { .init(periodIndex: $0.periodIndex, startTime: $0.startTime, endTime: $0.endTime) }
                )
            }
        }

        return placeholderState()
    }

    private init(repository: TimetableRepositoryProtocol, state: State, onFinished: @escaping () -> Void) {
        self.repository = repository
        self.state = state
        self.onFinished = onFinished
        super.init()
    }

    private func presentLoadedController(with state: State, in navigationController: UINavigationController) {
        self.state = state

        let controller = TimetableEditorController(coordinator: self)
        rootController = controller
        navigationController.setViewControllers([controller], animated: false)
    }

    var titleText: String {
        state.timetableId == nil ? "新建课表" : "编辑课表"
    }

    var canManageCourses: Bool {
        state.timetableId != nil
    }

    var periodsSummary: String {
        "共 \(state.periods.count) 节"
    }

    var coursesSummary: String {
        canManageCourses ? "管理本课表中的课程" : "保存课表后可管理课程"
    }

    func makePeriodsController() -> UIViewController {
        PeriodsManagementController(
            getPeriods: { [weak self] in self?.state.periods ?? [] },
            setPeriods: { [weak self] in self?.state.periods = $0 },
            onChange: { [weak self] in
                guard let root = self?.rootController as? TimetableEditorController else { return }
                root.rebuildContent()
            }
        )
    }

    func makeCoursesController() -> UIViewController {
        guard let timetableId = state.timetableId else {
            return MessageStackController(
                titleText: "课程设置",
                message: "请先保存课表，然后再管理课程。"
            )
        }
        return CourseManagementController(repository: repository, timetableId: timetableId)
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

    func presentDateEditor(for keyPath: ReferenceWritableKeyPath<State, String>, from view: UIView, title: String, message: String = "", onChanged: ((String) -> Void)? = nil) {
        let selectedDate = parseDateInput(state[keyPath: keyPath]) ?? Date()
        let picker = AlertDatePickerViewController(
            title: title,
            message: message,
            mode: .date,
            selectedDate: selectedDate
        ) { [weak self] date in
            guard let self else { return }
            let output = formatDateInput(date)
            state[keyPath: keyPath] = output
            onChanged?(output)
        }
        view.hostingViewController?.present(picker, animated: true)
    }

    @objc func cancelTapped() {
        onFinished()
    }

    @objc func saveTapped() {
        Task {
            do {
                guard let weeksCount = Int(state.weeksCount) else {
                    throw AppError.validation("总周数必须是数字。")
                }
                if let timetableId = state.timetableId {
                    try await repository.updateTimetable(input: .init(id: timetableId, name: state.name, termName: state.termName, startDate: state.startDate, weeksCount: weeksCount))
                    try await repository.replacePeriods(timetableId: timetableId, periods: state.periods)
                } else {
                    _ = try await repository.createTimetable(input: .init(name: state.name, termName: state.termName, startDate: state.startDate, weeksCount: weeksCount, periods: state.periods))
                }
                onFinished()
            } catch {
                presentError(error)
            }
        }
    }

    func promptDelete() {
        let alert = AlertViewController(
            title: "删除课表",
            message: "确定删除这个课表吗？此操作无法撤销。"
        ) { [weak self] context in
            context.addAction(title: "取消") {
                context.dispose()
            }
            context.addAction(title: "删除", attribute: .accent) {
                context.dispose {
                    guard let self else { return }
                    await self.deleteTimetable()
                }
            }
        }
        rootController?.present(alert, animated: true)
    }

    private func deleteTimetable() async {
        guard let timetableId = state.timetableId else { return }
        do {
            try await repository.deleteTimetable(id: timetableId)
            onFinished()
        } catch {
            presentError(error)
        }
    }

    func presentError(_ error: Error) {
        let alert = AlertViewController(
            title: "操作失败",
            message: error.localizedDescription
        ) { context in
            context.addAction(title: "确定", attribute: .accent) {
                context.dispose()
            }
        }
        rootController?.present(alert, animated: true)
    }
}

private final class TimetableEditorController: ReloadableStackScrollController {
    private unowned let coordinator: TimetableEditorCoordinator

    init(coordinator: TimetableEditorCoordinator) {
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
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: coordinator, action: #selector(TimetableEditorCoordinator.cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "checkmark"),
            style: .done,
            target: coordinator,
            action: #selector(TimetableEditorCoordinator.saveTapped)
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        rebuildContent()
    }

    override func buildContent() {
        appendEditableField(
            icon: "calendar",
            title: "课表名称",
            description: nil,
            value: coordinator.state.name.isEmpty ? "未设置" : coordinator.state.name,
            placeholder: "例如：我的课表"
        ) { [weak coordinator] view in
            coordinator?.presentEditor(
                for: \TimetableEditorCoordinator.State.name,
                from: view,
                title: "编辑课表名称",
                message: "课表的显示名称。",
                placeholder: "例如：我的课表"
            ) { output in
                view.configure(value: output.isEmpty ? "未设置" : output)
            }
        }

        appendEditableField(
            icon: "graduationcap",
            title: "学期名称",
            description: nil,
            value: coordinator.state.termName.isEmpty ? "未设置" : coordinator.state.termName,
            placeholder: "例如：2025-2026 春季"
        ) { [weak coordinator] view in
            coordinator?.presentEditor(
                for: \TimetableEditorCoordinator.State.termName,
                from: view,
                title: "编辑学期名称",
                message: "学期的显示名称。",
                placeholder: "例如：2025-2026 春季"
            ) { output in
                view.configure(value: output.isEmpty ? "未设置" : output)
            }
        }

        appendEditableField(
            icon: "calendar.badge.clock",
            title: "开学日期",
            description: "点击选择日期",
            value: coordinator.state.startDate,
            placeholder: "2026-03-02"
        ) { [weak coordinator] view in
            coordinator?.presentDateEditor(
                for: \TimetableEditorCoordinator.State.startDate,
                from: view,
                title: "编辑开学日期",
                message: "请选择开学日期。"
            ) { output in
                view.configure(value: output.isEmpty ? "未设置" : output)
            }
        }

        appendEditableField(
            icon: "number",
            title: "总周数",
            description: nil,
            value: coordinator.state.weeksCount,
            placeholder: "16"
        ) { [weak coordinator] view in
            coordinator?.presentEditor(
                for: \TimetableEditorCoordinator.State.weeksCount,
                from: view,
                title: "编辑总周数",
                message: "请输入数字。",
                placeholder: "16"
            ) { output in
                view.configure(value: output.isEmpty ? "未设置" : output)
            }
        }

        appendPage(
            icon: "clock.badge",
            title: "节次设置",
            description: coordinator.periodsSummary
        ) { [weak coordinator] in
            coordinator?.makePeriodsController()
        }

        appendPage(
            icon: "book.closed",
            title: "课程设置",
            description: coordinator.coursesSummary
        ) { [weak coordinator] in
            coordinator?.makeCoursesController()
        }

        if coordinator.canManageCourses {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView().with(header: "管理")
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            let deleteAction = ConfigurableActionView { @MainActor [weak coordinator] _ in
                coordinator?.promptDelete()
            }
            deleteAction.configure(icon: UIImage(systemName: "trash"))
            deleteAction.configure(title: "删除课表")
            deleteAction.configure(description: "永久删除这个课表及其课程数据。")
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
        view.configure(value: value.isEmpty ? placeholder : value)
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

private final class CourseManagementController: ReloadableStackScrollController {
    private let repository: TimetableRepositoryProtocol
    private let timetableId: String

    private var courses: [CourseWithMeetings] = []
    private var loadError: Error?
    private var isLoading = true

    init(repository: TimetableRepositoryProtocol, timetableId: String) {
        self.repository = repository
        self.timetableId = timetableId
        super.init(nibName: nil, bundle: nil)
        title = "课程设置"
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
            action: #selector(addCourseTapped)
        )
        Task { await reloadData() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { await reloadData() }
    }

    override func buildContent() {
        if isLoading {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(footer: "正在加载课程…")
            )
            return
        }

        if let loadError {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(footer: loadError.localizedDescription)
            )
            return
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: "课程")
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        for course in courses {
            let action = ConfigurableActionView { [weak self] controller in
                self?.presentCourseEditor(from: controller, courseId: course.id)
            }
            action.configure(icon: UIImage(systemName: "book.closed"))
            action.configure(title: course.name)
            action.configure(description: courseSummary(for: course))
            stackView.addArrangedSubviewWithMargin(action)
            stackView.addArrangedSubview(SeparatorView())
        }

        if courses.isEmpty {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(footer: "还没有课程，点击右上方“添加课程”开始创建。")
            ) { $0.top /= 2 }
        }

        stackView.addArrangedSubviewWithMargin(UIView())
    }

    private func courseSummary(for course: CourseWithMeetings) -> String {
        let teacher = normalizeOptionalText(course.teacher) ?? "未设置教师"
        let location = normalizeOptionalText(course.location) ?? "未设置地点"
        return "\(teacher) · \(location) · 共 \(course.meetings.count) 条时间"
    }

    @objc private func addCourseTapped() {
        presentCourseEditor(from: self, courseId: nil)
    }

    private func presentCourseEditor(from controller: UIViewController?, courseId: String?) {
        let editor = CourseEditorCoordinator.makeController(
            repository: repository,
            courseId: courseId,
            timetableId: timetableId,
            onFinished: { [weak self, weak controller] in
                controller?.dismiss(animated: true)
                Task { await self?.reloadData() }
            }
        )
        controller?.present(editor, animated: true)
    }

    private func reloadData() async {
        isLoading = true
        loadError = nil
        rebuildContent()
        do {
            courses = try await repository.listCourses(timetableId: timetableId)
        } catch {
            courses = []
            loadError = error
        }
        isLoading = false
        rebuildContent()
    }
}

private final class PeriodsManagementController: ReloadableStackScrollController {
    private let getPeriods: () -> [TimetablePeriodInput]
    private let setPeriods: ([TimetablePeriodInput]) -> Void
    private let onChange: () -> Void

    init(getPeriods: @escaping () -> [TimetablePeriodInput], setPeriods: @escaping ([TimetablePeriodInput]) -> Void, onChange: @escaping () -> Void) {
        self.getPeriods = getPeriods
        self.setPeriods = setPeriods
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
        title = "节次设置"
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
        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: "节次")
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        for period in getPeriods() {
            let page = ConfigurablePageView(page: { [weak self] in
                guard let self else { return nil }
                return PeriodDetailController(
                    periodIndex: period.periodIndex,
                    getPeriods: self.getPeriods,
                    setPeriods: self.setPeriods,
                    onChange: self.onChange
                )
            })
            page.configure(icon: UIImage(systemName: "clock"))
            page.configure(title: "第 \(period.periodIndex) 节")
            page.configure(description: "\(period.startTime) - \(period.endTime)")
            stackView.addArrangedSubviewWithMargin(page)
            stackView.addArrangedSubview(SeparatorView())
        }

        let addAction = ConfigurableActionView { [weak self] _ in
            guard let self else { return }
            var periods = getPeriods()
            periods.append(.init(periodIndex: periods.count + 1, startTime: "10:00", endTime: "10:45"))
            setPeriods(periods)
            onChange()
            rebuildContent()
        }
        addAction.configure(icon: UIImage(systemName: "plus.circle"))
        addAction.configure(title: "添加节次")
        addAction.configure(description: "新增一个节次。")
        stackView.addArrangedSubviewWithMargin(addAction)
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(UIView())
    }
}

private final class PeriodDetailController: ReloadableStackScrollController {
    private let periodIndex: Int
    private let getPeriods: () -> [TimetablePeriodInput]
    private let setPeriods: ([TimetablePeriodInput]) -> Void
    private let onChange: () -> Void

    init(periodIndex: Int, getPeriods: @escaping () -> [TimetablePeriodInput], setPeriods: @escaping ([TimetablePeriodInput]) -> Void, onChange: @escaping () -> Void) {
        self.periodIndex = periodIndex
        self.getPeriods = getPeriods
        self.setPeriods = setPeriods
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
        title = "第 \(periodIndex) 节"
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
        guard let period = currentPeriod else {
            navigationController?.popViewController(animated: true)
            return
        }

        appendEditableField(
            icon: "clock.badge",
            title: "开始时间",
            description: nil,
            value: period.startTime,
            placeholder: "08:00"
        ) { [weak self] view in
            self?.presentTimePicker(from: view, title: "编辑开始时间", message: "请选择开始时间。", currentValue: period.startTime) { newValue in
                self?.updateCurrentPeriod { $0.startTime = newValue }
                view.configure(value: newValue)
            }
        }

        appendEditableField(
            icon: "clock.badge",
            title: "结束时间",
            description: nil,
            value: period.endTime,
            placeholder: "08:45"
        ) { [weak self] view in
            self?.presentTimePicker(from: view, title: "编辑结束时间", message: "请选择结束时间。", currentValue: period.endTime) { newValue in
                self?.updateCurrentPeriod { $0.endTime = newValue }
                view.configure(value: newValue)
            }
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: "管理")
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        let deleteAction = ConfigurableActionView { @MainActor [weak self] _ in
            self?.deletePeriod()
        }
        deleteAction.configure(icon: UIImage(systemName: "trash"))
        deleteAction.configure(title: "删除本节")
        deleteAction.configure(description: "删除这个节次，并自动重排后续节次序号。")
        deleteAction.titleLabel.textColor = .systemRed
        deleteAction.iconView.tintColor = .systemRed
        deleteAction.descriptionLabel.textColor = .systemRed
        deleteAction.imageView.tintColor = .systemRed
        stackView.addArrangedSubviewWithMargin(deleteAction)
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(UIView())
    }

    private var currentPeriod: TimetablePeriodInput? {
        getPeriods().first(where: { $0.periodIndex == periodIndex })
    }

    private func updateCurrentPeriod(_ mutate: (inout TimetablePeriodInput) -> Void) {
        var periods = getPeriods()
        guard let index = periods.firstIndex(where: { $0.periodIndex == periodIndex }) else { return }
        mutate(&periods[index])
        setPeriods(periods)
        onChange()
    }

    private func presentTimePicker(from view: UIView, title: String, message: String = "", currentValue: String, onConfirm: @escaping (String) -> Void) {
        let selectedDate = parseTimeInput(currentValue) ?? parseTimeInput("08:00") ?? Date()
        let picker = AlertDatePickerViewController(
            title: title,
            message: message,
            mode: .time,
            selectedDate: selectedDate
        ) { date in
            onConfirm(formatTimeInput(date))
        }
        view.hostingViewController?.present(picker, animated: true)
    }

    private func deletePeriod() {
        var periods = getPeriods()
        periods.removeAll { $0.periodIndex == periodIndex }
        for index in periods.indices {
            periods[index].periodIndex = index + 1
        }
        setPeriods(periods)
        onChange()
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

private final class MessageStackController: ReloadableStackScrollController {
    private let titleText: String
    private let message: String

    init(titleText: String, message: String) {
        self.titleText = titleText
        self.message = message
        super.init(nibName: nil, bundle: nil)
        title = titleText
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func buildContent() {
        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView().with(footer: message)
        )
        stackView.addArrangedSubviewWithMargin(UIView())
    }
}

private class ReloadableStackScrollController: StackScrollController {
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

private final class TimetableEditorLoadingViewController: UIViewController {
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
