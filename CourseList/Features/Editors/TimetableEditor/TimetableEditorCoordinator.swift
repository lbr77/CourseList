import ConfigurableKit
import UIKit

@MainActor
final class TimetableEditorCoordinator: NSObject {
    private static let weeksCountRange = Array(1 ... 99)

    final class State {
        var timetableId: String?
        var name: String
        var startDate: String
        var weeksCount: Int
        var periodTemplateId: String?
        var periodTemplateName: String?
        var periods: [TimetablePeriodInput]

        init(timetableId: String?, name: String, startDate: String, weeksCount: Int, periodTemplateId: String?, periodTemplateName: String?, periods: [TimetablePeriodInput]) {
            self.timetableId = timetableId
            self.name = name
            self.startDate = startDate
            self.weeksCount = weeksCount
            self.periodTemplateId = periodTemplateId
            self.periodTemplateName = periodTemplateName
            self.periods = periods
        }
    }

    private let repository: TimetableRepositoryProtocol
    fileprivate var state: State
    private let onFinished: () -> Void
    private weak var rootController: UIViewController?

    static func makeController(repository: TimetableRepositoryProtocol, timetableId: String?, onFinished: @escaping () -> Void) -> UIViewController {
        let coordinator = TimetableEditorCoordinator(repository: repository, state: placeholderState(), onFinished: onFinished)
        let loadingController = TimetableEditorLoadingViewController(title: timetableId == nil ? L10n.tr("Create a new class schedule") : L10n.tr("Edit class schedule"))
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
            startDate: formatDateInput(Date()),
            weeksCount: 16,
            periodTemplateId: nil,
            periodTemplateName: nil,
            periods: defaultTimetablePeriods()
        )
    }

    private static func loadState(repository: TimetableRepositoryProtocol, timetableId: String?) async -> State {
        if let timetableId {
            async let timetablesTask = repository.listTimetables()
            async let periodsTask = repository.listPeriods(timetableId: timetableId)

            let timetables = (try? await timetablesTask) ?? []
            let loadedPeriods = (try? await periodsTask) ?? []
            let mappedPeriods = loadedPeriods.map { TimetablePeriodInput(periodIndex: $0.periodIndex, startTime: $0.startTime, endTime: $0.endTime) }

            if let timetable = timetables.first(where: { $0.id == timetableId }) {
                let matchedTemplate = await resolveMatchingTemplate(repository: repository, periods: mappedPeriods)
                return State(
                    timetableId: timetable.id,
                    name: timetable.name,
                    startDate: timetable.startDate,
                    weeksCount: timetable.weeksCount,
                    periodTemplateId: matchedTemplate?.id,
                    periodTemplateName: matchedTemplate?.name,
                    periods: mappedPeriods
                )
            }
        }

        if let defaultTemplate = try? await repository.getDefaultPeriodTemplate() {
            let templateItems = (try? await repository.listPeriodTemplateItems(templateId: defaultTemplate.id)) ?? []
            let periods = templateItems.map {
                TimetablePeriodInput(periodIndex: $0.periodIndex, startTime: $0.startTime, endTime: $0.endTime)
            }
            if !periods.isEmpty {
                return State(
                    timetableId: nil,
                    name: "",
                    startDate: formatDateInput(Date()),
                    weeksCount: 16,
                    periodTemplateId: defaultTemplate.id,
                    periodTemplateName: defaultTemplate.name,
                    periods: periods
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
        state.timetableId == nil ? L10n.tr("Create a new class schedule") : L10n.tr("Edit class schedule")
    }

    var canManageCourses: Bool {
        state.timetableId != nil
    }

    var periodsSummary: String {
        L10n.tr("%d periods", state.periods.count)
    }

    var periodTemplateSummary: String {
        let prefix = state.periodTemplateName ?? L10n.tr("Custom sections")
        return L10n.tr("%@ · Total %d sections", prefix, state.periods.count)
    }

    var coursesSummary: String {
        canManageCourses ? L10n.tr("Manage courses in this schedule") : L10n.tr("Courses can be managed after saving the schedule")
    }

    func makePeriodTemplateController() -> UIViewController {
        PeriodTemplatePickerController(
            repository: repository,
            selectedTemplateId: { [weak self] in self?.state.periodTemplateId },
            applyTemplate: { [weak self] template, periods in
                self?.state.periodTemplateId = template.id
                self?.state.periodTemplateName = template.name
                self?.state.periods = periods
            },
            onChange: { [weak self] in
                guard let root = self?.rootController as? TimetableEditorController else { return }
                root.rebuildContent()
            }
        )
    }

    func makeCoursesController() -> UIViewController {
        guard let timetableId = state.timetableId else {
            return MessageStackController(
                titleText: L10n.tr("Curriculum"),
                message: L10n.tr("Please save the class schedule first and then manage the course.")
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
            cancelButtonText: L10n.tr("Cancel"),
            doneButtonText: L10n.tr("Sure")
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

    func presentWeeksCountEditor(from view: UIView, onChanged: ((Int) -> Void)? = nil) {
        let selectedWeeksCount = Self.weeksCountRange.contains(state.weeksCount) ? state.weeksCount : 16
        let picker = AlertOptionPickerViewController(
            title: L10n.tr("Total number of weeks edited"),
            message: L10n.tr("Swipe up or down to select the total number of weeks."),
            options: Self.weeksCountRange.map { L10n.tr("Week %d", $0) },
            selectedIndex: selectedWeeksCount - 1
        ) { [weak self] selectedIndex in
            guard let self else { return }
            let weeksCount = Self.weeksCountRange[selectedIndex]
            state.weeksCount = weeksCount
            onChanged?(weeksCount)
        }
        view.hostingViewController?.present(picker, animated: true)
    }

    @objc func cancelTapped() {
        onFinished()
    }

    @objc func saveTapped() {
        Task {
            do {
                if let timetableId = state.timetableId {
                    try await repository.updateTimetable(input: .init(id: timetableId, name: state.name, startDate: state.startDate, weeksCount: state.weeksCount))
                    try await repository.replacePeriods(timetableId: timetableId, periods: state.periods)
                } else {
                    _ = try await repository.createTimetable(input: .init(name: state.name, startDate: state.startDate, weeksCount: state.weeksCount, periods: state.periods))
                }
                onFinished()
            } catch {
                presentError(error)
            }
        }
    }

    func promptDelete() {
        let alert = AlertViewController(
            title: L10n.tr("Delete class schedule"),
            message: L10n.tr("Are you sure you want to delete this class schedule?")
        ) { [weak self] context in
            context.addAction(title: L10n.tr("Cancel")) {
                context.dispose()
            }
            context.addAction(title: L10n.tr("delete"), attribute: .accent) {
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

    private static func resolveMatchingTemplate(repository: TimetableRepositoryProtocol, periods: [TimetablePeriodInput]) async -> PeriodTemplate? {
        let templates = (try? await repository.listPeriodTemplates()) ?? []
        for template in templates {
            let items = (try? await repository.listPeriodTemplateItems(templateId: template.id)) ?? []
            let templatePeriods = items.map {
                TimetablePeriodInput(periodIndex: $0.periodIndex, startTime: $0.startTime, endTime: $0.endTime)
            }
            if templatePeriods == periods {
                return template
            }
        }
        return nil
    }

    func presentError(_ error: Error) {
        let alert = AlertViewController(
            title: L10n.tr("Operation failed"),
            message: error.localizedDescription
        ) { context in
            context.addAction(title: L10n.tr("Sure"), attribute: .accent) {
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
            title: L10n.tr("Class schedule name"),
            description: nil,
            value: coordinator.state.name.isEmpty ? L10n.tr("not set") : coordinator.state.name,
            placeholder: L10n.tr("Junior year")
        ) { [weak coordinator] view in
            coordinator?.presentEditor(
                for: \TimetableEditorCoordinator.State.name,
                from: view,
                title: L10n.tr("Edit class name"),
                message: L10n.tr("The display name of the class schedule."),
                placeholder: L10n.tr("Junior year")
            ) { output in
                view.configure(value: output.isEmpty ? L10n.tr("not set") : output)
            }
        }

        appendEditableField(
            icon: "calendar.badge.clock",
            title: L10n.tr("School start date"),
            description: nil,
            value: coordinator.state.startDate,
            placeholder: "2026-03-02"
        ) { [weak coordinator] view in
            coordinator?.presentDateEditor(
                for: \TimetableEditorCoordinator.State.startDate,
                from: view,
                title: L10n.tr("Edit start date"),
                message: L10n.tr("Please select a start date.")
            ) { output in
                view.configure(value: output.isEmpty ? L10n.tr("not set") : output)
            }
        }

        appendEditableField(
            icon: "number",
            title: L10n.tr("total number of weeks"),
            description: nil,
            value: L10n.tr("Week %d", coordinator.state.weeksCount),
            placeholder: L10n.tr("16 weeks")
        ) { [weak coordinator] view in
            coordinator?.presentWeeksCountEditor(from: view) { weeksCount in
                view.configure(value: L10n.tr("Week %d", weeksCount))
            }
        }

        appendPage(
            icon: "clock.badge",
            title: L10n.tr("Section template"),
            description: coordinator.periodTemplateSummary
        ) { [weak coordinator] in
            coordinator?.makePeriodTemplateController()
        }

        appendPage(
            icon: "book.closed",
            title: L10n.tr("Curriculum"),
            description: coordinator.coursesSummary
        ) { [weak coordinator] in
            coordinator?.makeCoursesController()
        }

        if coordinator.canManageCourses {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView().with(header: L10n.tr("manage"))
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            let deleteAction = ConfigurableActionView { @MainActor [weak coordinator] _ in
                coordinator?.promptDelete()
            }
            deleteAction.configure(icon: UIImage(systemName: "trash"))
            deleteAction.configure(title: L10n.tr("Delete class schedule"))
            deleteAction.configure(description: L10n.tr("Permanently delete this schedule and its course data."))
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

private final class AlertOptionPickerContentController: AlertContentController, UIPickerViewDataSource, UIPickerViewDelegate {
    let picker = UIPickerView()

    private let options: [String]

    init(
        title: String = "",
        message: String = "",
        options: [String],
        selectedIndex: Int,
        setupActions: @escaping (ActionContext) -> Void
    ) {
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

private final class AlertOptionPickerViewController: AlertViewController {
    convenience init(
        title: String,
        message: String = "",
        options: [String],
        selectedIndex: Int,
        cancelButtonText: String = L10n.tr("Cancel"),
        doneButtonText: String = L10n.tr("Sure"),
        onConfirm: @escaping (Int) -> Void
    ) {
        var controller: AlertOptionPickerContentController!
        controller = AlertOptionPickerContentController(
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

private final class PeriodTemplatePickerController: ReloadableStackScrollController {
    private let repository: TimetableRepositoryProtocol
    private let selectedTemplateId: () -> String?
    private let applyTemplate: (PeriodTemplate, [TimetablePeriodInput]) -> Void
    private let onChange: () -> Void

    private var templates: [PeriodTemplate] = []
    private var templatePeriods: [String: [TimetablePeriodInput]] = [:]
    private var loadError: Error?
    private var refreshError: Error?
    private var isLoading = true
    private var isRefreshing = false
    private var hasLoadedOnce = false

    init(
        repository: TimetableRepositoryProtocol,
        selectedTemplateId: @escaping () -> String?,
        applyTemplate: @escaping (PeriodTemplate, [TimetablePeriodInput]) -> Void,
        onChange: @escaping () -> Void
    ) {
        self.repository = repository
        self.selectedTemplateId = selectedTemplateId
        self.applyTemplate = applyTemplate
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
        title = L10n.tr("Section template")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { await reloadData() }
    }

    override func buildContent() {
        if isLoading && !hasLoadedOnce {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(footer: L10n.tr("Reading section template..."))
            )
            stackView.addArrangedSubviewWithMargin(UIView())
            return
        }

        if let loadError, templates.isEmpty {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(footer: loadError.localizedDescription)
            )
            stackView.addArrangedSubviewWithMargin(UIView())
            return
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: L10n.tr("template"))
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        if templates.isEmpty {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(footer: L10n.tr("There is no section template yet, please go to the settings page to create a template first."))
            )
            stackView.addArrangedSubview(SeparatorView())
        } else {
            for template in templates {
                let action = ConfigurableActionView { [weak self] _ in
                    self?.selectTemplate(template)
                }
                let isSelected = template.id == selectedTemplateId()
                let iconName = isSelected ? "checkmark.circle.fill" : (template.isDefault ? "star.circle" : "clock.badge")
                let periods = templatePeriods[template.id] ?? []
                let tags = [
                    isSelected ? L10n.tr("currently in use") : nil,
                    template.isDefault ? L10n.tr("default") : nil,
                    L10n.tr("%d periods", periods.count)
                ].compactMap { $0 }
                action.configure(icon: UIImage(systemName: iconName))
                action.configure(title: template.name)
                action.configure(description: tags.joined(separator: " · "))
                stackView.addArrangedSubviewWithMargin(action)
                stackView.addArrangedSubview(SeparatorView())
            }
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView().with(footer: statusFooterText)
        )
        stackView.addArrangedSubviewWithMargin(UIView())
    }

    private func reloadData() async {
        if !hasLoadedOnce {
            isLoading = true
            loadError = nil
            refreshError = nil
            rebuildContent()
        } else {
            isRefreshing = true
            refreshError = nil
            rebuildContent()
        }

        do {
            let loadedTemplates = try await repository.listPeriodTemplates()
            var loadedPeriods: [String: [TimetablePeriodInput]] = [:]
            for template in loadedTemplates {
                let items = try await repository.listPeriodTemplateItems(templateId: template.id)
                loadedPeriods[template.id] = items.map {
                    .init(periodIndex: $0.periodIndex, startTime: $0.startTime, endTime: $0.endTime)
                }
            }
            templates = loadedTemplates
            templatePeriods = loadedPeriods
            loadError = nil
            refreshError = nil
        } catch {
            if hasLoadedOnce && !templates.isEmpty {
                refreshError = error
            } else {
                templates = []
                templatePeriods = [:]
                loadError = error
            }
        }

        hasLoadedOnce = true
        isLoading = false
        isRefreshing = false
        rebuildContent()
    }

    private var statusFooterText: String {
        if isRefreshing {
            return L10n.tr("Refreshing template list...")
        }
        if let refreshError {
            return L10n.tr("Refresh failed: %@", refreshError.localizedDescription)
        }
        return L10n.tr("After selecting a template, the section settings of the current class schedule will be overwritten with the template sections.")
    }

    private func selectTemplate(_ template: PeriodTemplate) {
        let periods = templatePeriods[template.id] ?? []
        guard !periods.isEmpty else { return }
        applyTemplate(template, periods)
        onChange()
        navigationController?.popViewController(animated: true)
    }
}

private final class CourseManagementController: ReloadableStackScrollController {
    private let repository: TimetableRepositoryProtocol
    private let timetableId: String

    private var courses: [CourseWithMeetings] = []
    private var loadError: Error?
    private var refreshError: Error?
    private var isLoading = true
    private var isRefreshing = false
    private var hasLoadedOnce = false

    init(repository: TimetableRepositoryProtocol, timetableId: String) {
        self.repository = repository
        self.timetableId = timetableId
        super.init(nibName: nil, bundle: nil)
        title = L10n.tr("Curriculum")
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
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { await reloadData() }
    }

    override func buildContent() {
        if isLoading && !hasLoadedOnce {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(footer: L10n.tr("Loading courses…"))
            )
            stackView.addArrangedSubviewWithMargin(UIView())
            return
        }

        if let loadError, courses.isEmpty {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(footer: loadError.localizedDescription)
            )
            stackView.addArrangedSubviewWithMargin(UIView())
            return
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: L10n.tr("course"))
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
                ConfigurableSectionFooterView().with(footer: L10n.tr("There is no course yet, click \"Add Course\" on the upper right to start creating it."))
            ) { $0.top /= 2 }
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView().with(footer: statusFooterText)
        ) { $0.top /= 2 }
        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(UIView())
    }

    private func courseSummary(for course: CourseWithMeetings) -> String {
        let teacher = normalizeOptionalText(course.teacher) ?? L10n.tr("No teacher set")
        let location = normalizeOptionalText(course.location) ?? L10n.tr("No location set")
        return L10n.tr("%@ · %@ · Total %d times", teacher, location, course.meetings.count)
    }

    @objc private func addCourseTapped() {
        presentCourseEditor(from: self, courseId: nil)
    }

    private func presentCourseEditor(from controller: UIViewController?, courseId: String?) {
        let editor = CourseList.CourseEditorCoordinator.makeController(
            repository: repository,
            courseId: courseId,
            timetableId: timetableId,
            onFinished: { [weak controller] in
                controller?.dismiss(animated: true)
            }
        )
        controller?.present(editor, animated: true)
    }

    private func reloadData() async {
        if !hasLoadedOnce {
            isLoading = true
            loadError = nil
            refreshError = nil
            rebuildContent()
        } else {
            isRefreshing = true
            refreshError = nil
            rebuildContent()
        }
        do {
            courses = try await repository.listCourses(timetableId: timetableId)
            loadError = nil
            refreshError = nil
        } catch {
            if hasLoadedOnce && !courses.isEmpty {
                refreshError = error
            } else {
                courses = []
                loadError = error
            }
        }
        hasLoadedOnce = true
        isLoading = false
        isRefreshing = false
        rebuildContent()
    }

    private var statusFooterText: String {
        if isRefreshing {
            return L10n.tr("Refreshing course list...")
        }
        if let refreshError {
            return L10n.tr("Refresh failed: %@", refreshError.localizedDescription)
        }
        return L10n.tr("Modified courses will take effect immediately on the course schedule display.")
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
        title = L10n.tr("Section settings")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: nil,
            image: UIImage(systemName: "plus"),
            primaryAction: nil,
            menu: makeAddMenu()
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        rebuildContent()
    }

    override func buildContent() {
        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: L10n.tr("section"))
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
            page.configure(title: L10n.tr("Period %d", period.periodIndex))
            page.configure(description: "\(period.startTime) - \(period.endTime)")
            stackView.addArrangedSubviewWithMargin(page)
            stackView.addArrangedSubview(SeparatorView())
        }

        if getPeriods().isEmpty {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(footer: L10n.tr("Click + Add Section in the upper right corner."))
            )
            stackView.addArrangedSubview(SeparatorView())
        }

        stackView.addArrangedSubviewWithMargin(UIView())
    }

    private func makeAddMenu() -> UIMenu {
        UIMenu(children: [
            UIAction(
                title: L10n.tr("Add single section"),
                image: UIImage(systemName: "plus.circle")
            ) { [weak self] _ in
                self?.addSinglePeriod()
            },
            UIAction(
                title: L10n.tr("Add in batches"),
                image: UIImage(systemName: "square.stack.3d.up.badge.plus")
            ) { [weak self] _ in
                self?.presentBatchAddPrompt()
            },
        ])
    }

    private func addSinglePeriod() {
        let newPeriod = nextPeriod(after: getPeriods())
        var periods = getPeriods()
        periods.append(newPeriod)
        setPeriods(periods)
        onChange()
        rebuildContent()

        navigationController?.pushViewController(
            PeriodDetailController(
                periodIndex: newPeriod.periodIndex,
                getPeriods: getPeriods,
                setPeriods: setPeriods,
                onChange: onChange
            ),
            animated: true
        )
    }

    private func presentBatchAddPrompt() {
        let input = AlertInputViewController(
            title: L10n.tr("Add sections in batches"),
            message: L10n.tr("Please enter the number of sections to add consecutively."),
            placeholder: "",
            text: "2",
            cancelButtonText: L10n.tr("Cancel"),
            doneButtonText: L10n.tr("Sure")
        ) { [weak self] output in
            self?.handleBatchAdd(output: output)
        }
        present(input, animated: true)
    }

    private func handleBatchAdd(output: String) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let count = Int(trimmed), count > 0 else {
            presentMessage(title: L10n.tr("Invalid quantity"), message: L10n.tr("Please enter an integer greater than 0."))
            return
        }

        var periods = getPeriods()
        for _ in 0 ..< count {
            periods.append(nextPeriod(after: periods))
        }

        setPeriods(periods)
        onChange()
        rebuildContent()
    }

    private func nextPeriod(after periods: [TimetablePeriodInput]) -> TimetablePeriodInput {
        makeNextTimetablePeriodInput(after: periods)
    }

    private func presentMessage(title: String, message: String) {
        let alert = AlertViewController(title: title, message: message) { context in
            context.addAction(title: L10n.tr("Sure"), attribute: .accent) {
                context.dispose()
            }
        }
        present(alert, animated: true)
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
        title = L10n.tr("Period %d", periodIndex)
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
            title: L10n.tr("start time"),
            description: nil,
            value: period.startTime,
            placeholder: "08:00"
        ) { [weak self] view in
            self?.presentTimePicker(from: view, title: L10n.tr("Edit start time"), message: L10n.tr("Please select a start time."), currentValue: period.startTime) { newValue in
                self?.updateCurrentPeriod { $0.startTime = newValue }
                view.configure(value: newValue)
            }
        }

        appendEditableField(
            icon: "clock.badge",
            title: L10n.tr("end time"),
            description: nil,
            value: period.endTime,
            placeholder: "08:45"
        ) { [weak self] view in
            self?.presentTimePicker(from: view, title: L10n.tr("Edit end time"), message: L10n.tr("Please select an end time."), currentValue: period.endTime) { newValue in
                self?.updateCurrentPeriod { $0.endTime = newValue }
                view.configure(value: newValue)
            }
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: L10n.tr("manage"))
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        let deleteAction = ConfigurableActionView { @MainActor [weak self] _ in
            self?.deletePeriod()
        }
        deleteAction.configure(icon: UIImage(systemName: "trash"))
        deleteAction.configure(title: L10n.tr("Delete this section"))
        deleteAction.configure(description: L10n.tr("Delete this section and automatically rearrange the serial numbers of subsequent sections."))
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
