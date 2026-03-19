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
                        UIHostingController(rootView: PlaceholderSettingsPageView(
                            title: "外观设置",
                            description: "这里后续放主题、颜色、课表显示样式等设置。"
                        ))
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
                        UIHostingController(
                            rootView: AboutSettingsView(
                                currentTimetable: currentTimetable,
                                bootstrapError: bootstrapError
                            )
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

private struct AboutSettingsView: View {
    let currentTimetable: Timetable?
    let bootstrapError: String?

    var body: some View {
        List {
            Section("应用") {
                LabeledContent("名称", value: "CourseList")
                LabeledContent("版本", value: appVersion)
                LabeledContent("构建号", value: appBuild)
            }

            Section("状态") {
                LabeledContent("数据库", value: bootstrapError == nil ? "正常" : "初始化失败")
                if let currentTimetable {
                    LabeledContent("当前课表", value: currentTimetable.name)
                } else {
                    LabeledContent("当前课表", value: "无")
                }
                if let bootstrapError {
                    Text(bootstrapError)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("关于")
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知版本"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "未知构建"
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
                let page = ConfigurablePageView(page: { [weak self] in
                    guard let self else { return nil }
                    return PeriodTemplateDetailController(
                        repository: self.repository,
                        templateId: template.id,
                        onChanged: { [weak self] in
                            Task { await self?.reloadData() }
                        }
                    )
                })
                page.configure(icon: UIImage(systemName: template.isDefault ? "star.circle.fill" : "clock.badge"))
                page.configure(title: template.name)
                page.configure(description: template.isDefault ? "默认模板" : "点击编辑节次")
                stackView.addArrangedSubviewWithMargin(page)
                stackView.addArrangedSubview(SeparatorView())
            }
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView().with(footer: "默认模板会用于新建课表的初始节次；现有课表不会自动变更。")
        )
        stackView.addArrangedSubviewWithMargin(UIView())
    }

    @objc private func addTemplateTapped() {
        let input = AlertInputViewController(
            title: "新建节次模板",
            message: "请输入模板名称。",
            placeholder: "例如：本科默认作息",
            text: "",
            cancelButtonText: "取消",
            doneButtonText: "确定"
        ) { [weak self] output in
            self?.handleCreateTemplate(name: output)
        }
        present(input, animated: true)
    }

    private func handleCreateTemplate(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            presentMessage(title: "名称无效", message: "模板名称不能为空。")
            return
        }

        Task {
            do {
                var seedPeriods = defaultTimetablePeriods()
                if let defaultTemplate = try await repository.getDefaultPeriodTemplate() {
                    let items = try await repository.listPeriodTemplateItems(templateId: defaultTemplate.id)
                    let mapped = items.map {
                        TimetablePeriodInput(periodIndex: $0.periodIndex, startTime: $0.startTime, endTime: $0.endTime)
                    }
                    if !mapped.isEmpty {
                        seedPeriods = mapped
                    }
                }

                let templateId = try await repository.savePeriodTemplate(
                    input: .init(id: nil, name: trimmed, periods: seedPeriods)
                )
                NotificationCenter.default.post(name: .timetableRepositoryDidChange, object: nil)
                await reloadData()
                navigationController?.pushViewController(
                    PeriodTemplateDetailController(
                        repository: repository,
                        templateId: templateId,
                        onChanged: { [weak self] in
                            Task { await self?.reloadData() }
                        }
                    ),
                    animated: true
                )
            } catch {
                presentError(error)
            }
        }
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

@MainActor
private final class PeriodTemplateDetailController: SettingsReloadableStackScrollController {
    private let repository: any TimetableRepositoryProtocol
    private let templateId: String
    private let onChanged: () -> Void

    private var template: PeriodTemplate?
    private var periods: [TimetablePeriodInput] = []
    private var loadError: Error?
    private var isLoading = true

    init(repository: any TimetableRepositoryProtocol, templateId: String, onChanged: @escaping () -> Void) {
        self.repository = repository
        self.templateId = templateId
        self.onChanged = onChanged
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
            title: nil,
            image: UIImage(systemName: "plus"),
            primaryAction: nil,
            menu: makeAddMenu()
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { await reloadData() }
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

        guard let template else {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(footer: "模板不存在。")
            )
            stackView.addArrangedSubviewWithMargin(UIView())
            return
        }

        appendEditableField(
            icon: "textformat",
            title: "模板名称",
            description: template.isDefault ? "当前默认模板" : nil,
            value: template.name,
            placeholder: "未设置"
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
                    onChange: { [weak self] in
                        self?.saveCurrentTemplate()
                    }
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
                ConfigurableSectionFooterView().with(footer: "点击右上角 + 添加节次。")
            )
            stackView.addArrangedSubview(SeparatorView())
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: "管理")
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        if !template.isDefault {
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

        stackView.addArrangedSubviewWithMargin(UIView())
    }

    private func reloadData() async {
        isLoading = true
        loadError = nil
        rebuildContent()

        do {
            async let templateTask = repository.getPeriodTemplate(id: templateId)
            async let periodsTask = repository.listPeriodTemplateItems(templateId: templateId)

            template = try await templateTask
            periods = try await periodsTask.map {
                .init(periodIndex: $0.periodIndex, startTime: $0.startTime, endTime: $0.endTime)
            }
            title = template?.name ?? "节次模板"
        } catch {
            loadError = error
        }

        isLoading = false
        rebuildContent()
    }

    private func makeAddMenu() -> UIMenu {
        UIMenu(children: [
            UIAction(
                title: "添加单节",
                image: UIImage(systemName: "plus.circle")
            ) { [weak self] _ in
                self?.addSinglePeriod()
            },
            UIAction(
                title: "批量添加",
                image: UIImage(systemName: "square.stack.3d.up.badge.plus")
            ) { [weak self] _ in
                self?.presentBatchAddPrompt()
            },
        ])
    }

    private func addSinglePeriod() {
        let newPeriod = makeNextTimetablePeriodInput(after: periods)
        periods.append(newPeriod)
        rebuildContent()
        saveCurrentTemplate()

        navigationController?.pushViewController(
            PeriodTemplatePeriodDetailController(
                periodIndex: newPeriod.periodIndex,
                getPeriods: { [weak self] in self?.periods ?? [] },
                setPeriods: { [weak self] in self?.periods = $0 },
                onChange: { [weak self] in
                    self?.saveCurrentTemplate()
                }
            ),
            animated: true
        )
    }

    private func presentBatchAddPrompt() {
        let input = AlertInputViewController(
            title: "批量添加节次",
            message: "请输入要连续添加的节次数量。",
            placeholder: "例如：4",
            text: "2",
            cancelButtonText: "取消",
            doneButtonText: "确定"
        ) { [weak self] output in
            self?.handleBatchAdd(output: output)
        }
        present(input, animated: true)
    }

    private func handleBatchAdd(output: String) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let count = Int(trimmed), count > 0 else {
            presentMessage(title: "数量无效", message: "请输入大于 0 的整数。")
            return
        }

        for _ in 0 ..< count {
            periods.append(makeNextTimetablePeriodInput(after: periods))
        }
        rebuildContent()
        saveCurrentTemplate()
    }

    private func presentNameEditor(from view: UIView) {
        guard let template else { return }
        let input = AlertInputViewController(
            title: "编辑模板名称",
            message: "请输入模板名称。",
            placeholder: "例如：本科默认作息",
            text: template.name,
            cancelButtonText: "取消",
            doneButtonText: "确定"
        ) { [weak self] output in
            self?.handleNameChange(output: output)
        }
        view.hostingViewController?.present(input, animated: true)
    }

    private func handleNameChange(output: String) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            presentMessage(title: "名称无效", message: "模板名称不能为空。")
            return
        }

        template?.name = trimmed
        title = trimmed
        rebuildContent()
        saveCurrentTemplate()
    }

    private func saveCurrentTemplate() {
        guard let template else { return }
        Task {
            do {
                _ = try await repository.savePeriodTemplate(
                    input: .init(id: template.id, name: template.name, periods: periods)
                )
                NotificationCenter.default.post(name: .timetableRepositoryDidChange, object: nil)
                onChanged()
            } catch {
                presentError(error)
                await reloadData()
            }
        }
    }

    private func setAsDefaultTemplate() {
        Task {
            do {
                try await repository.setDefaultPeriodTemplate(id: templateId)
                NotificationCenter.default.post(name: .timetableRepositoryDidChange, object: nil)
                onChanged()
                await reloadData()
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
        Task {
            do {
                try await repository.deletePeriodTemplate(id: templateId)
                NotificationCenter.default.post(name: .timetableRepositoryDidChange, object: nil)
                onChanged()
                navigationController?.popViewController(animated: true)
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
