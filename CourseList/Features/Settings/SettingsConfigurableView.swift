import ConfigurableKit
import SwiftUI
import UIKit

struct SettingsConfigurableView: UIViewControllerRepresentable {
    let repository: any TimetableRepositoryProtocol
    let currentTimetable: Timetable?
    let bootstrapError: String?
    let onImportTap: () -> Void
    let onNewTimetableTap: () -> Void
    let onEditTimetableTap: (String?) -> Void
    let onRepositoryChanged: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let navigationController = UINavigationController(rootViewController: makeRootController())
        navigationController.navigationBar.prefersLargeTitles = true
        return navigationController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard let navigationController = uiViewController as? UINavigationController else { return }

        var viewControllers = navigationController.viewControllers
        let rootController = makeRootController()

        if viewControllers.isEmpty {
            navigationController.setViewControllers([rootController], animated: false)
            return
        }

        viewControllers[0] = rootController
        navigationController.setViewControllers(viewControllers, animated: false)
    }

    private func makeRootController() -> UIViewController {
        let controller = ConfigurableViewController(manifest: makeManifest())
        controller.title = "设置"
        controller.navigationItem.title = "设置"
        controller.navigationItem.largeTitleDisplayMode = .always
        return controller
    }

    private func makeManifest() -> ConfigurableManifest {
        ConfigurableManifest(
            title: "设置",
            list: [
                ConfigurableObject(
                    icon: "calendar",
                    title: "课表管理",
                    explain: "管理课表",
                    ephemeralAnnotation: .page {
                        TimetableManagementController(
                            repository: repository,
                            onImportTap: onImportTap,
                            onCreateTimetable: onNewTimetableTap,
                            onEditTimetable: onEditTimetableTap,
                            onRepositoryChanged: onRepositoryChanged
                        )
                    }
                ),
                ConfigurableObject(
                    icon: "clock.badge",
                    title: "节次模板",
                    explain: "管理默认节次与模板",
                    ephemeralAnnotation: .page {
                        PeriodTemplateManagementController(repository: repository)
                    }
                ),
                ConfigurableObject(
                    icon: "paintbrush",
                    title: "外观设置",
                    explain: "主题、颜色与显示方式",
                    ephemeralAnnotation: .page {
                        TimetableAppearanceSettingsController()
                    }
                ),
                ConfigurableObject(
                    icon: "lock.shield",
                    title: "权限管理",
                    explain: "通知、日历等系统权限",
                    ephemeralAnnotation: .page {
                        UIHostingController(rootView: PlaceholderSettingsPageView(
                            title: "权限管理",
                            description: "这里后续放通知、日历与其它系统权限管理。"
                        ))
                    }
                ),
                ConfigurableObject(
                    icon: "info.circle",
                    title: "关于",
                    explain: appVersionSummary,
                    ephemeralAnnotation: .page {
                        AboutSettingsController(
                            currentTimetable: currentTimetable,
                            bootstrapError: bootstrapError
                        )
                    }
                ),
            ],
            footer: footerText
        )
    }

    private var appVersionSummary: String {
        "版本 \(appVersion)(\(appBuild))"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "未知"
    }

    private var footerText: String {
        "版本 \(appVersion)(\(appBuild))"
    }
}

private struct PlaceholderSettingsPageView: View {
    let title: String
    let description: String

    var body: some View {
        List {
            Section {
                Text(description)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(title)
    }
}

@MainActor
private final class AboutSettingsController: SettingsReloadableStackScrollController {
    let currentTimetable: Timetable?
    let bootstrapError: String?

    init(currentTimetable: Timetable?, bootstrapError: String?) {
        self.currentTimetable = currentTimetable
        self.bootstrapError = bootstrapError
        super.init(nibName: nil, bundle: nil)
        title = "关于"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func buildContent() {
        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: "应用")
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        appendInfoField(icon: "app", title: "名称", value: "CourseList")
        appendInfoField(icon: "tag", title: "版本", value: appVersion)
        appendInfoField(icon: "number", title: "构建号", value: appBuild)

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: "状态")
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        appendInfoField(
            icon: "internaldrive",
            title: "数据库",
            value: bootstrapError == nil ? "正常" : "初始化失败"
        )
        appendInfoField(
            icon: "calendar",
            title: "当前课表",
            value: currentTimetable?.name ?? "无"
        )

        if let bootstrapError {
            let footer = ConfigurableSectionFooterView().with(footer: bootstrapError)
            footer.titleLabel.textColor = .systemOrange
            stackView.addArrangedSubviewWithMargin(footer) { $0.top /= 2 }
            stackView.addArrangedSubview(SeparatorView())
        }

        stackView.addArrangedSubviewWithMargin(UIView())
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知版本"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "未知构建"
    }

    private func appendInfoField(icon: String, title: String, value: String) {
        let view = ConfigurableInfoView()
        view.configure(icon: UIImage(systemName: icon))
        view.configure(title: title)
        view.configure(description: "")
        view.valueLabel.setAttributedTitle(nil, for: .normal)
        view.valueLabel.setTitle(value, for: .normal)
        view.valueLabel.setTitleColor(.secondaryLabel, for: .normal)
        stackView.addArrangedSubviewWithMargin(view)
        stackView.addArrangedSubview(SeparatorView())
    }
}

@MainActor
private final class TimetableAppearanceSettingsController: SettingsReloadableStackScrollController {
    private var visibleHourRange = TimetableVisibleHourRange.default
    private var weekStart = TimetableWeekStart.default

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "外观设置"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        visibleHourRange = loadTimetableVisibleHourRange()
        weekStart = loadTimetableWeekStart()
        rebuildContent()
    }

    override func buildContent() {
        appendEditableField(
            icon: "clock",
            title: "显示开始时间",
            description: "课表顶部显示的起始小时",
            value: hourLabel(visibleHourRange.startHour),
            placeholder: ""
        ) { [weak self] view in
            self?.presentStartHourPicker(from: view)
        }

        appendEditableField(
            icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
            title: "显示结束时间",
            description: "课表底部显示到该小时",
            value: hourLabel(visibleHourRange.endHour),
            placeholder: ""
        ) { [weak self] view in
            self?.presentEndHourPicker(from: view)
        }

        appendMenuField(
            icon: "calendar",
            title: "每周起始日",
            description: "设置周视图从周天或周一开始",
            value: weekStart.label,
            menu: weekStartMenu()
        )

        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView().with(
                footer: "课表会按该范围拉伸显示，适合课程集中在白天时提高可读性。"
            )
        )
        stackView.addArrangedSubviewWithMargin(UIView())
    }

    private func presentStartHourPicker(from view: UIView) {
        let options = Array(0 ... 23)
        let picker = SettingsAlertOptionPickerViewController(
            title: "显示开始时间",
            message: "选择课表从几点开始显示。",
            options: options.map(hourLabel),
            selectedIndex: options.firstIndex(of: visibleHourRange.startHour) ?? 0
        ) { [weak self] selectedIndex in
            guard let self else { return }
            let selectedStart = options[selectedIndex]
            let adjustedEnd = max(visibleHourRange.endHour, selectedStart + 1)
            updateVisibleHourRange(TimetableVisibleHourRange(startHour: selectedStart, endHour: adjustedEnd))
        }
        view.hostingViewController?.present(picker, animated: true)
    }

    private func presentEndHourPicker(from view: UIView) {
        let options = Array((visibleHourRange.startHour + 1) ... 24)
        let selectedIndex = options.firstIndex(of: visibleHourRange.endHour) ?? max(0, options.count - 1)
        let picker = SettingsAlertOptionPickerViewController(
            title: "显示结束时间",
            message: "选择课表显示到几点。",
            options: options.map(hourLabel),
            selectedIndex: selectedIndex
        ) { [weak self] index in
            guard let self else { return }
            updateVisibleHourRange(TimetableVisibleHourRange(startHour: visibleHourRange.startHour, endHour: options[index]))
        }
        view.hostingViewController?.present(picker, animated: true)
    }

    private func updateVisibleHourRange(_ newRange: TimetableVisibleHourRange) {
        visibleHourRange = newRange
        saveTimetableVisibleHourRange(newRange)
        NotificationCenter.default.post(name: .timetableAppearanceDidChange, object: nil)
        rebuildContent()
    }

    private func updateWeekStart(_ newWeekStart: TimetableWeekStart) {
        weekStart = newWeekStart
        saveTimetableWeekStart(newWeekStart)
        NotificationCenter.default.post(name: .timetableAppearanceDidChange, object: nil)
        rebuildContent()
    }

    private func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
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

    private func appendMenuField(icon: String, title: String, description: String?, value: String, menu: UIMenu) {
        let view = ConfigurableInfoView()
        view.configure(icon: UIImage(systemName: icon))
        view.configure(title: title)
        view.configure(description: description ?? "")
        view.configure(value: value)
        view.configure(menu: menu)
        stackView.addArrangedSubviewWithMargin(view)
        stackView.addArrangedSubview(SeparatorView())
    }

    private func weekStartMenu() -> UIMenu {
        let actions = TimetableWeekStart.allCases.map { option in
            UIAction(
                title: option.label,
                state: option == weekStart ? .on : .off
            ) { [weak self] _ in
                self?.updateWeekStart(option)
            }
        }
        return UIMenu(options: [.displayInline], children: actions)
    }
}

@MainActor
private final class PeriodTemplateManagementController: SettingsReloadableStackScrollController {
    private let repository: any TimetableRepositoryProtocol

    private var templates: [PeriodTemplate] = []
    private var loadError: Error?
    private var isLoading = true

    init(repository: any TimetableRepositoryProtocol) {
        self.repository = repository
        super.init(nibName: nil, bundle: nil)
        title = "节次模板"
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
            action: #selector(addTemplateTapped)
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { await reloadData() }
    }

    override func buildContent() {
        if isLoading {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(footer: "正在读取节次模板…")
            )
            stackView.addArrangedSubviewWithMargin(UIView())
            return
        }

        if let loadError {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(footer: loadError.localizedDescription)
            )
            stackView.addArrangedSubviewWithMargin(UIView())
            return
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: "模板")
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        if templates.isEmpty {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(footer: "还没有节次模板，点击右上角 + 新建。")
            )
            stackView.addArrangedSubview(SeparatorView())
        } else {
            for template in templates {
                let action = ConfigurableActionView { [weak self] _ in
                    self?.presentEditor(templateId: template.id)
                }
                action.configure(icon: UIImage(systemName: template.isDefault ? "star.circle.fill" : "clock.badge"))
                action.configure(title: template.name)
                action.configure(description: template.isDefault ? "默认模板 · 点击编辑" : "点击编辑节次")
                stackView.addArrangedSubviewWithMargin(action)
                stackView.addArrangedSubview(SeparatorView())
            }
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView().with(footer: "默认模板会用于新建课表的初始节次；现有课表不会自动变更。")
        )
        stackView.addArrangedSubviewWithMargin(UIView())
    }

    @objc private func addTemplateTapped() {
        presentEditor(templateId: nil)
    }

    private func presentEditor(templateId: String?) {
        let editor = PeriodTemplateEditorController(
            repository: repository,
            templateId: templateId,
            onFinished: { [weak self] in
                self?.dismiss(animated: true)
                NotificationCenter.default.post(name: .timetableRepositoryDidChange, object: nil)
                Task { await self?.reloadData() }
            }
        )
        let navigationController = UINavigationController(rootViewController: editor)
        navigationController.navigationBar.prefersLargeTitles = false
        present(navigationController, animated: true)
    }

    private func reloadData() async {
        isLoading = true
        loadError = nil
        rebuildContent()
        do {
            templates = try await repository.listPeriodTemplates()
        } catch {
            templates = []
            loadError = error
        }
        isLoading = false
        rebuildContent()
    }
}

@MainActor
private final class PeriodTemplateEditorController: SettingsReloadableStackScrollController {
    private let repository: any TimetableRepositoryProtocol
    private let onFinished: () -> Void

    private var templateId: String?
    private var templateName = ""
    private var periods: [TimetablePeriodInput] = []
    private var isDefaultTemplate = false
    private var isLoading = true
    private var loadError: Error?

    init(repository: any TimetableRepositoryProtocol, templateId: String?, onFinished: @escaping () -> Void) {
        self.repository = repository
        self.templateId = templateId
        self.onFinished = onFinished
        super.init(nibName: nil, bundle: nil)
        title = templateId == nil ? "新建模板" : "编辑模板"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "checkmark"),
            style: .done,
            target: self,
            action: #selector(saveTapped)
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if isLoading {
            Task { await loadData() }
        } else {
            rebuildContent()
        }
    }

    override func buildContent() {
        if isLoading {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(footer: "正在读取模板…")
            )
            stackView.addArrangedSubviewWithMargin(UIView())
            return
        }

        if let loadError {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(footer: loadError.localizedDescription)
            )
            stackView.addArrangedSubviewWithMargin(UIView())
            return
        }

        appendEditableField(
            icon: "textformat",
            title: "模板名称",
            description: isDefaultTemplate ? "当前默认模板" : nil,
            value: templateName,
            placeholder: ""
        ) { [weak self] view in
            self?.presentNameEditor(from: view)
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: "节次")
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        for period in periods {
            let page = ConfigurablePageView(page: { [weak self] in
                guard let self else { return nil }
                return PeriodTemplatePeriodDetailController(
                    periodIndex: period.periodIndex,
                    getPeriods: { [weak self] in self?.periods ?? [] },
                    setPeriods: { [weak self] in self?.periods = $0 },
                    onChange: { }
                )
            })
            page.configure(icon: UIImage(systemName: "clock"))
            page.configure(title: "第 \(period.periodIndex) 节")
            page.configure(description: "\(period.startTime) - \(period.endTime)")
            stackView.addArrangedSubviewWithMargin(page)
            stackView.addArrangedSubview(SeparatorView())
        }

        if periods.isEmpty {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(footer: "当前还没有节次，请先添加节次。")
            )
            stackView.addArrangedSubview(SeparatorView())
        }

        let addAction = ConfigurableActionView { [weak self] _ in
            self?.presentAddMenu()
        }
        addAction.configure(icon: UIImage(systemName: "plus.circle"))
        addAction.configure(title: "添加节次")
        stackView.addArrangedSubviewWithMargin(addAction)
        stackView.addArrangedSubview(SeparatorView())

        if templateId != nil {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView().with(header: "管理")
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            if !isDefaultTemplate {
                let defaultAction = ConfigurableActionView { [weak self] _ in
                    self?.setAsDefaultTemplate()
                }
                defaultAction.configure(icon: UIImage(systemName: "star"))
                defaultAction.configure(title: "设为默认模板")
                defaultAction.configure(description: "新建课表时默认使用这套节次。")
                stackView.addArrangedSubviewWithMargin(defaultAction)
                stackView.addArrangedSubview(SeparatorView())
            }

            let deleteAction = ConfigurableActionView { [weak self] _ in
                self?.promptDeleteTemplate()
            }
            deleteAction.configure(icon: UIImage(systemName: "trash"))
            deleteAction.configure(title: "删除模板")
            deleteAction.configure(description: "删除这个节次模板。若它是默认模板，会自动切换到其它模板。")
            deleteAction.titleLabel.textColor = .systemRed
            deleteAction.iconView.tintColor = .systemRed
            deleteAction.descriptionLabel.textColor = .systemRed
            deleteAction.imageView.tintColor = .systemRed
            stackView.addArrangedSubviewWithMargin(deleteAction)
            stackView.addArrangedSubview(SeparatorView())
        }

        stackView.addArrangedSubviewWithMargin(UIView())
    }

    private func loadData() async {
        do {
            if let templateId {
                async let templateTask = repository.getPeriodTemplate(id: templateId)
                async let itemsTask = repository.listPeriodTemplateItems(templateId: templateId)
                let template = try await templateTask
                let items = try await itemsTask

                guard let template else {
                    throw AppError.validation("模板不存在。")
                }

                templateName = template.name
                isDefaultTemplate = template.isDefault
                periods = items.map {
                    .init(periodIndex: $0.periodIndex, startTime: $0.startTime, endTime: $0.endTime)
                }
            } else {
                periods = []
            }
            loadError = nil
        } catch {
            loadError = error
        }

        isLoading = false
        rebuildContent()
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func saveTapped() {
        Task {
            do {
                let savedId = try await repository.savePeriodTemplate(
                    input: .init(id: templateId, name: templateName, periods: periods)
                )
                templateId = savedId
                onFinished()
            } catch {
                presentError(error)
            }
        }
    }

    private func presentNameEditor(from view: UIView) {
        let input = AlertInputViewController(
            title: "编辑模板名称",
            message: "请输入模板名称。",
            placeholder: "",
            text: templateName,
            cancelButtonText: "取消",
            doneButtonText: "确定"
        ) { [weak self] output in
            self?.templateName = output
            self?.rebuildContent()
        }
        view.hostingViewController?.present(input, animated: true)
    }

    private func presentAddMenu() {
        let alert = AlertViewController(title: "添加节次", message: "请选择添加方式。") { [weak self] context in
            context.addAction(title: "取消") {
                context.dispose()
            }
            context.addAction(title: "添加单节", attribute: .accent) {
                context.dispose {
                    self?.addSinglePeriod()
                }
            }
            context.addAction(title: "批量添加") {
                context.dispose {
                    self?.presentBatchAddPrompt()
                }
            }
        }
        present(alert, animated: true)
    }

    private func addSinglePeriod() {
        let newPeriod = makeNextTimetablePeriodInput(after: periods)
        periods.append(newPeriod)
        rebuildContent()

        navigationController?.pushViewController(
            PeriodTemplatePeriodDetailController(
                periodIndex: newPeriod.periodIndex,
                getPeriods: { [weak self] in self?.periods ?? [] },
                setPeriods: { [weak self] in self?.periods = $0 },
                onChange: { }
            ),
            animated: true
        )
    }

    private func presentBatchAddPrompt() {
        let controller = PeriodTemplateBatchAddController { [weak self] generatedPeriods in
            guard let self else { return }
            periods.append(contentsOf: generatedPeriods)
            rebuildContent()
        }
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.navigationBar.prefersLargeTitles = false
        present(navigationController, animated: true)
    }

    private func setAsDefaultTemplate() {
        guard let templateId else { return }
        Task {
            do {
                _ = try await repository.savePeriodTemplate(
                    input: .init(id: templateId, name: templateName, periods: periods)
                )
                try await repository.setDefaultPeriodTemplate(id: templateId)
                onFinished()
            } catch {
                presentError(error)
            }
        }
    }

    private func promptDeleteTemplate() {
        let alert = AlertViewController(
            title: "删除模板",
            message: "确定删除这个节次模板吗？此操作无法撤销。"
        ) { [weak self] context in
            context.addAction(title: "取消") {
                context.dispose()
            }
            context.addAction(title: "删除", attribute: .accent) {
                context.dispose {
                    self?.deleteTemplate()
                }
            }
        }
        present(alert, animated: true)
    }

    private func deleteTemplate() {
        guard let templateId else { return }
        Task {
            do {
                try await repository.deletePeriodTemplate(id: templateId)
                onFinished()
            } catch {
                presentError(error)
            }
        }
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

    private func presentError(_ error: Error) {
        presentMessage(title: "操作失败", message: error.localizedDescription)
    }

    private func presentMessage(title: String, message: String) {
        let alert = AlertViewController(title: title, message: message) { context in
            context.addAction(title: "确定", attribute: .accent) {
                context.dispose()
            }
        }
        present(alert, animated: true)
    }
}

private final class SettingsAlertOptionPickerContentController: AlertContentController, UIPickerViewDataSource, UIPickerViewDelegate {
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

private final class SettingsAlertOptionPickerViewController: AlertViewController {
    convenience init(
        title: String,
        message: String = "",
        options: [String],
        selectedIndex: Int,
        cancelButtonText: String = "取消",
        doneButtonText: String = "确定",
        onConfirm: @escaping (Int) -> Void
    ) {
        var controller: SettingsAlertOptionPickerContentController!
        controller = SettingsAlertOptionPickerContentController(
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

private final class PeriodTemplateBatchAddController: SettingsReloadableStackScrollController {
    private static let durationOptions = Array(stride(from: 30, through: 120, by: 5))
    private static let breakOptions = Array(stride(from: 0, through: 60, by: 5))
    private static let countOptions = Array(0 ... 12)

    private var durationMinutes = 45
    private var breakMinutes = 10
    private var morningStartTime = ""
    private var morningCount = 0
    private var afternoonStartTime = ""
    private var afternoonCount = 0

    private let onConfirm: ([TimetablePeriodInput]) -> Void

    init(onConfirm: @escaping ([TimetablePeriodInput]) -> Void) {
        self.onConfirm = onConfirm
        super.init(nibName: nil, bundle: nil)
        title = "批量添加节次"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "checkmark"),
            style: .done,
            target: self,
            action: #selector(confirmTapped)
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        rebuildContent()
    }

    override func buildContent() {
        appendEditableField(
            icon: "timer",
            title: "每节时长",
            description: nil,
            value: "\(durationMinutes) 分钟",
            placeholder: ""
        ) { [weak self] view in
            self?.presentDurationPicker(from: view)
        }

        appendEditableField(
            icon: "pause.circle",
            title: "课间时间",
            description: nil,
            value: "\(breakMinutes) 分钟",
            placeholder: ""
        ) { [weak self] view in
            self?.presentBreakPicker(from: view)
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: "上午")
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        appendEditableField(
            icon: "sun.max",
            title: "开始时间",
            description: nil,
            value: morningStartTime.isEmpty ? "未设置" : morningStartTime,
            placeholder: ""
        ) { [weak self] view in
            self?.presentTimePicker(from: view, title: "上午第一节开始时间", currentValue: self?.morningStartTime ?? "") { newValue in
                self?.morningStartTime = newValue
                view.configure(value: newValue)
            }
        }

        appendEditableField(
            icon: "number",
            title: "几节课",
            description: nil,
            value: "\(morningCount) 节",
            placeholder: ""
        ) { [weak self] view in
            self?.presentCountPicker(from: view, title: "上午几节课", currentCount: self?.morningCount ?? 0) { count in
                self?.morningCount = count
                view.configure(value: "\(count) 节")
            }
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: "下午")
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        appendEditableField(
            icon: "sunset",
            title: "第一节时间",
            description: nil,
            value: afternoonStartTime.isEmpty ? "未设置" : afternoonStartTime,
            placeholder: ""
        ) { [weak self] view in
            self?.presentTimePicker(from: view, title: "下午第一节开始时间", currentValue: self?.afternoonStartTime ?? "") { newValue in
                self?.afternoonStartTime = newValue
                view.configure(value: newValue)
            }
        }

        appendEditableField(
            icon: "number",
            title: "几节课",
            description: nil,
            value: "\(afternoonCount) 节",
            placeholder: ""
        ) { [weak self] view in
            self?.presentCountPicker(from: view, title: "下午几节课", currentCount: self?.afternoonCount ?? 0) { count in
                self?.afternoonCount = count
                view.configure(value: "\(count) 节")
            }
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView().with(footer: "会按设定的时长和课间时间生成相邻节次。")
        )
        stackView.addArrangedSubviewWithMargin(UIView())
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func confirmTapped() {
        do {
            let generated = try buildPeriods()
            onConfirm(generated)
            dismiss(animated: true)
        } catch {
            presentMessage(title: "参数无效", message: error.localizedDescription)
        }
    }

    private func buildPeriods() throws -> [TimetablePeriodInput] {
        if morningCount == 0 && afternoonCount == 0 {
            throw AppError.validation("上午和下午至少要填写一段课程。")
        }

        var generated: [TimetablePeriodInput] = []
        if morningCount > 0 {
            guard let start = parseTimeInput(morningStartTime) else {
                throw AppError.validation("请设置上午第一节开始时间。")
            }
            generated.append(contentsOf: makePeriods(start: start, count: morningCount, startIndex: generated.count + 1))
        }

        if afternoonCount > 0 {
            guard let start = parseTimeInput(afternoonStartTime) else {
                throw AppError.validation("请设置下午第一节开始时间。")
            }
            generated.append(contentsOf: makePeriods(start: start, count: afternoonCount, startIndex: generated.count + 1))
        }

        return generated
    }

    private func makePeriods(start: Date, count: Int, startIndex: Int) -> [TimetablePeriodInput] {
        var result: [TimetablePeriodInput] = []
        let duration = TimeInterval(durationMinutes * 60)
        let breakDuration = TimeInterval(breakMinutes * 60)

        for offset in 0 ..< count {
            let currentStart = start.addingTimeInterval(TimeInterval(offset) * (duration + breakDuration))
            let currentEnd = currentStart.addingTimeInterval(duration)
            result.append(
                TimetablePeriodInput(
                    periodIndex: startIndex + offset,
                    startTime: formatTimeInput(currentStart),
                    endTime: formatTimeInput(currentEnd)
                )
            )
        }
        return result
    }

    private func presentDurationPicker(from view: UIView) {
        let selectedIndex = Self.durationOptions.firstIndex(of: durationMinutes) ?? 3
        let picker = SettingsAlertOptionPickerViewController(
            title: "每节时长",
            message: "选择每节课的时长。",
            options: Self.durationOptions.map { "\($0) 分钟" },
            selectedIndex: selectedIndex
        ) { [weak self] index in
            guard let self else { return }
            durationMinutes = Self.durationOptions[index]
            rebuildContent()
        }
        view.hostingViewController?.present(picker, animated: true)
    }

    private func presentBreakPicker(from view: UIView) {
        let selectedIndex = Self.breakOptions.firstIndex(of: breakMinutes) ?? 2
        let picker = SettingsAlertOptionPickerViewController(
            title: "课间时间",
            message: "选择每节之间的课间时间。",
            options: Self.breakOptions.map { "\($0) 分钟" },
            selectedIndex: selectedIndex
        ) { [weak self] index in
            guard let self else { return }
            breakMinutes = Self.breakOptions[index]
            rebuildContent()
        }
        view.hostingViewController?.present(picker, animated: true)
    }

    private func presentCountPicker(from view: UIView, title: String, currentCount: Int, onConfirm: @escaping (Int) -> Void) {
        let picker = SettingsAlertOptionPickerViewController(
            title: title,
            message: "选择节数。",
            options: Self.countOptions.map { "\($0) 节" },
            selectedIndex: min(currentCount, Self.countOptions.count - 1)
        ) { index in
            onConfirm(Self.countOptions[index])
        }
        view.hostingViewController?.present(picker, animated: true)
    }

    private func presentTimePicker(from view: UIView, title: String, currentValue: String, onConfirm: @escaping (String) -> Void) {
        let selectedDate = parseTimeInput(currentValue) ?? parseTimeInput("08:00") ?? Date()
        let picker = AlertDatePickerViewController(
            title: title,
            mode: .time,
            selectedDate: selectedDate
        ) { date in
            let output = formatTimeInput(date)
            onConfirm(output)
        }
        view.hostingViewController?.present(picker, animated: true)
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

    private func presentMessage(title: String, message: String) {
        let alert = AlertViewController(title: title, message: message) { context in
            context.addAction(title: "确定", attribute: .accent) {
                context.dispose()
            }
        }
        present(alert, animated: true)
    }
}

private final class PeriodTemplatePeriodDetailController: SettingsReloadableStackScrollController {
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
            placeholder: ""
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
            placeholder: ""
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

        let deleteAction = ConfigurableActionView { [weak self] _ in
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

private class SettingsReloadableStackScrollController: StackScrollController {
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
