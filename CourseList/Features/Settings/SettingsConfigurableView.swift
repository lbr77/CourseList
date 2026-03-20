import ConfigurableKit
import EventKit
import SwiftUI
import UIKit
import UserNotifications

struct SettingsConfigurableView: UIViewControllerRepresentable {
    let repository: any TimetableRepositoryProtocol
    let currentTimetable: Timetable?
    let bootstrapError: String?
    let onImportTap: () -> Void
    let onNewTimetableTap: () -> Void
    let onEditTimetableTap: (String?) -> Void
    let onRepositoryChanged: () -> Void
    let embedInNavigationController: Bool
    let onCloseTap: (() -> Void)?

    final class Coordinator: NSObject {
        private let onCloseTap: (() -> Void)?

        init(onCloseTap: (() -> Void)?) {
            self.onCloseTap = onCloseTap
        }

        @objc func closeTapped() {
            onCloseTap?()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCloseTap: onCloseTap)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let rootController = makeRootController(context: context)

        if embedInNavigationController {
            let navigationController = UINavigationController(rootViewController: rootController)
            navigationController.navigationBar.prefersLargeTitles = true
            return navigationController
        }

        let containerController = SettingsHostingController()
        containerController.setRootController(rootController)
        return containerController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        let rootController = makeRootController(context: context)

        if let navigationController = uiViewController as? UINavigationController {
            var viewControllers = navigationController.viewControllers

            if viewControllers.isEmpty {
                navigationController.setViewControllers([rootController], animated: false)
                return
            }

            viewControllers[0] = rootController
            navigationController.setViewControllers(viewControllers, animated: false)
            return
        }

        guard let containerController = uiViewController as? SettingsHostingController else { return }
        containerController.setRootController(rootController)
    }

    private func makeRootController(context: Context) -> UIViewController {
        let controller = ConfigurableViewController(manifest: makeManifest())
        controller.title = L10n.tr("set up")
        controller.navigationItem.title = L10n.tr("set up")
        controller.navigationItem.largeTitleDisplayMode = .never
        if onCloseTap != nil {
            if #available(iOS 26.0, *) {
                controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
                    barButtonSystemItem: .close,
                    target: context.coordinator,
                    action: #selector(Coordinator.closeTapped)
                )
            } else {
                controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
                    title: L10n.tr("closure"),
                    style: .plain,
                    target: context.coordinator,
                    action: #selector(Coordinator.closeTapped)
                )
            }
        }
        return controller
    }

    private func makeManifest() -> ConfigurableManifest {
        ConfigurableManifest(
            title: L10n.tr("set up"),
            list: [
                ConfigurableObject(
                    icon: "calendar",
                    title: L10n.tr("Timetable management"),
                    explain: L10n.tr("Manage class schedule"),
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
                    title: L10n.tr("Section template"),
                    explain: L10n.tr("Manage default sections and templates"),
                    ephemeralAnnotation: .page {
                        PeriodTemplateManagementController(repository: repository)
                    }
                ),
                ConfigurableObject(
                    icon: "paintbrush",
                    title: L10n.tr("Appearance settings"),
                    explain: L10n.tr("Themes, colors and display"),
                    ephemeralAnnotation: .page {
                        TimetableAppearanceSettingsController()
                    }
                ),
                ConfigurableObject(
                    icon: "wrench.and.screwdriver",
                    title: L10n.tr("tool"),
                    explain: L10n.tr("Useful functions such as export to calendar"),
                    ephemeralAnnotation: .page {
                        ToolSettingsController(
                            repository: repository,
                            onRepositoryChanged: onRepositoryChanged
                        )
                    }
                ),
                ConfigurableObject(
                    icon: "lock.shield",
                    title: L10n.tr("Permission management"),
                    explain: L10n.tr("Notifications, calendar and other system permissions"),
                    ephemeralAnnotation: .page {
                        NotificationPermissionSettingsController(repository: repository)
                    }
                ),
                ConfigurableObject(
                    icon: "info.circle",
                    title: L10n.tr("about"),
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
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? L10n.tr("unknown")
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? L10n.tr("unknown")
    }

    private var footerText: String {
        "版本 \(appVersion)(\(appBuild))"
    }
}

private final class SettingsHostingController: UIViewController {
    private var rootController: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
    }

    func setRootController(_ controller: UIViewController) {
        if let rootController {
            rootController.willMove(toParent: nil)
            rootController.view.removeFromSuperview()
            rootController.removeFromParent()
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

        rootController = controller
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
        title = L10n.tr("about")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func buildContent() {
        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: L10n.tr("application"))
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        appendInfoField(icon: "app", title: L10n.tr("name"), value: "CourseList")
        appendInfoField(icon: "tag", title: L10n.tr("Version"), value: appVersion)
        appendInfoField(icon: "number", title: L10n.tr("Build number"), value: appBuild)

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: L10n.tr("state"))
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        appendInfoField(
            icon: "internaldrive",
            title: L10n.tr("database"),
            value: bootstrapError == nil ? L10n.tr("normal") : L10n.tr("Initialization failed")
        )
        appendInfoField(
            icon: "calendar",
            title: L10n.tr("Current class schedule"),
            value: currentTimetable?.name ?? L10n.tr("none")
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
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? L10n.tr("Unknown version")
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? L10n.tr("unknown build")
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
    private var appLanguage = AppLanguage.default

    init() {
        super.init(nibName: nil, bundle: nil)
        title = L10n.tr("Appearance settings")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        visibleHourRange = loadTimetableVisibleHourRange()
        weekStart = loadTimetableWeekStart()
        appLanguage = L10n.currentLanguage()
        rebuildContent()
    }

    override func buildContent() {
        appendEditableField(
            icon: "clock",
            title: L10n.tr("Show start time"),
            description: L10n.tr("The starting hour shown at the top of the schedule"),
            value: hourLabel(visibleHourRange.startHour),
            placeholder: ""
        ) { [weak self] view in
            self?.presentStartHourPicker(from: view)
        }

        appendEditableField(
            icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
            title: L10n.tr("Show end time"),
            description: L10n.tr("The hour is displayed at the bottom of the schedule"),
            value: hourLabel(visibleHourRange.endHour),
            placeholder: ""
        ) { [weak self] view in
            self?.presentEndHourPicker(from: view)
        }

        appendMenuField(
            icon: "calendar",
            title: L10n.tr("start day of week"),
            description: L10n.tr("Set the week view to start on Sunday or Monday"),
            value: weekStart.label,
            menu: weekStartMenu()
        )

        appendMenuField(
            icon: "globe",
            title: L10n.tr("Language"),
            description: L10n.tr("Switch app display language"),
            value: appLanguage.title,
            menu: languageMenu()
        )

        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView().with(
                footer: L10n.tr("The class schedule will be stretched and displayed according to this range, which is suitable for improving readability when classes are concentrated during the day.")
            )
        )
        stackView.addArrangedSubviewWithMargin(UIView())
    }

    private func presentStartHourPicker(from view: UIView) {
        let options = Array(0 ... 23)
        let picker = SettingsAlertOptionPickerViewController(
            title: L10n.tr("Show start time"),
            message: L10n.tr("Select the time from which the class schedule will be displayed."),
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
            title: L10n.tr("Show end time"),
            message: L10n.tr("Select until what time the class schedule is displayed."),
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

    private func updateLanguage(_ language: AppLanguage) {
        guard language != appLanguage else { return }
        appLanguage = language
        L10n.setLanguage(language)
        title = L10n.tr("Appearance settings")
        navigationItem.title = title
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

    private func languageMenu() -> UIMenu {
        let actions = AppLanguage.allCases.map { option in
            UIAction(
                title: option.title,
                state: option == appLanguage ? .on : .off
            ) { [weak self] _ in
                self?.updateLanguage(option)
            }
        }
        return UIMenu(options: [.displayInline], children: actions)
    }
}

@MainActor
private final class NotificationPermissionSettingsController: SettingsReloadableStackScrollController {
    private let repository: any TimetableRepositoryProtocol
    private let eventStore = EKEventStore()

    private var isNotificationEnabled = loadCourseNotificationEnabled()
    private var leadMinutes = loadCourseNotificationLeadMinutes()
    private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private var calendarAuthorizationStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    init(repository: any TimetableRepositoryProtocol) {
        self.repository = repository
        super.init(nibName: nil, bundle: nil)
        title = L10n.tr("Permission management")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isNotificationEnabled = loadCourseNotificationEnabled()
        leadMinutes = loadCourseNotificationLeadMinutes()
        calendarAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
        rebuildContent()

        Task { [weak self] in
            guard let self else { return }
            authorizationStatus = await CourseNotificationService.shared.authorizationStatus()
            calendarAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
            rebuildContent()
        }
    }

    override func buildContent() {
        appendSwitchField(
            icon: "bell.badge",
            title: L10n.tr("Course reminder"),
            description: L10n.tr("Send system notification before class"),
            isOn: isNotificationEnabled
        ) { [weak self] isOn in
            self?.updateNotificationEnabled(isOn)
        }

        appendEditableField(
            icon: "timer",
            title: L10n.tr("advance notice"),
            description: L10n.tr("How long before the course starts"),
            value: "\(leadMinutes) 分钟前",
            placeholder: ""
        ) { [weak self] view in
            self?.presentLeadMinutesPicker(from: view)
        }

        appendEditableField(
            icon: "calendar.badge.clock",
            title: L10n.tr("Calendar access"),
            description: calendarPermissionActionDescription,
            value: calendarAuthorizationStatusLabel(calendarAuthorizationStatus),
            placeholder: ""
        ) { [weak self] _ in
            self?.handleCalendarPermissionTap()
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView().with(footer: footerText)
        )
        stackView.addArrangedSubviewWithMargin(UIView())
    }

    private func presentLeadMinutesPicker(from view: UIView) {
        let options = courseNotificationLeadMinuteOptions
        let selectedIndex = options.firstIndex(of: leadMinutes) ?? max(0, options.count - 1)
        let picker = SettingsAlertOptionPickerViewController(
            title: L10n.tr("advance notice"),
            message: L10n.tr("Choose a reminder time before the course starts."),
            options: options.map { "\($0) 分钟前" },
            selectedIndex: selectedIndex
        ) { [weak self] selectedIndex in
            guard let self else { return }
            updateLeadMinutes(options[selectedIndex])
        }
        view.hostingViewController?.present(picker, animated: true)
    }

    private func updateNotificationEnabled(_ enabled: Bool) {
        guard enabled != isNotificationEnabled else { return }
        isNotificationEnabled = enabled
        saveCourseNotificationEnabled(enabled)
        triggerNotificationSync()
        rebuildContent()
    }

    private func updateLeadMinutes(_ minutes: Int) {
        let normalized = normalizeCourseNotificationLeadMinutes(minutes)
        guard normalized != leadMinutes else { return }
        leadMinutes = normalized
        saveCourseNotificationLeadMinutes(normalized)
        triggerNotificationSync()
        rebuildContent()
    }

    private func triggerNotificationSync() {
        NotificationCenter.default.post(name: .courseNotificationSettingsDidChange, object: nil)
        Task { await CourseNotificationService.shared.syncNow(repository: repository) }
    }

    private func handleCalendarPermissionTap() {
        if hasCalendarReadPermission(status: calendarAuthorizationStatus) {
            rebuildContent()
            return
        }

        switch calendarAuthorizationStatus {
        case .notDetermined:
            requestCalendarPermission()
        case .denied, .restricted:
            openSystemSettings()
        case .authorized:
            rebuildContent()
        @unknown default:
            if #available(iOS 17.0, *) {
                if calendarAuthorizationStatus == .writeOnly {
                    requestCalendarPermission()
                    return
                }
                if calendarAuthorizationStatus == .fullAccess {
                    rebuildContent()
                    return
                }
            }
            rebuildContent()
        }
    }

    private func requestCalendarPermission() {
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await requestCalendarReadPermission(using: eventStore)
                calendarAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
                rebuildContent()
            } catch {
                presentError(error)
            }
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var calendarPermissionActionDescription: String {
        switch calendarAuthorizationStatus {
        case .notDetermined:
            return L10n.tr("Click Request calendar access.")
        case .restricted:
            return L10n.tr("System limit and cannot be modified.")
        case .denied:
            return L10n.tr("Rejected, click to go to system settings to turn it on.")
        case .authorized:
            return L10n.tr("Authorized to access the system calendar.")
        @unknown default:
            if #available(iOS 17.0, *) {
                if calendarAuthorizationStatus == .writeOnly {
                    return L10n.tr("Write permission only.")
                }
                if calendarAuthorizationStatus == .fullAccess {
                    return L10n.tr("Authorized to access the system calendar.")
                }
            }
            return L10n.tr("Permission status is unknown.")
        }
    }

    private var footerText: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return L10n.tr("Notifications are available; calendar permissions are available in Tools -> Export to Calendar.")
        case .notDetermined:
            return L10n.tr("The notification is undecided; system authorization pop-up window will be triggered when course reminder is enabled.")
        case .denied:
            return L10n.tr("Notifications have been denied and can be turned back on in system settings; calendar permissions can be managed separately.")
        @unknown default:
            return L10n.tr("System permissions such as notifications and calendars can be managed here.")
        }
    }

    private func presentError(_ error: Error) {
        let alert = UIAlertController(title: L10n.tr("Operation failed"), message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.tr("knew"), style: .default))
        present(alert, animated: true)
    }

    private func appendSwitchField(icon: String, title: String, description: String?, isOn: Bool, onToggle: @escaping (Bool) -> Void) {
        let view = SettingsSwitchFieldView()
        view.configure(icon: UIImage(systemName: icon))
        view.configure(title: title)
        view.configure(description: description ?? "")
        view.configure(isOn: isOn, onToggle: onToggle)
        stackView.addArrangedSubviewWithMargin(view)
        stackView.addArrangedSubview(SeparatorView())
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

@MainActor
private final class ToolSettingsController: SettingsReloadableStackScrollController {
    private let repository: any TimetableRepositoryProtocol
    private let onRepositoryChanged: () -> Void

    init(repository: any TimetableRepositoryProtocol, onRepositoryChanged: @escaping () -> Void) {
        self.repository = repository
        self.onRepositoryChanged = onRepositoryChanged
        super.init(nibName: nil, bundle: nil)
        title = L10n.tr("tool")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func buildContent() {
        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: L10n.tr("tool"))
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        let page = ConfigurablePageView(page: { [weak self] in
            guard let self else { return nil }
            return CalendarExportSettingsController(repository: self.repository)
        })
        page.configure(icon: UIImage(systemName: "calendar.badge.plus"))
        page.configure(title: L10n.tr("Export to calendar"))
        page.configure(description: L10n.tr("Write the class schedule into the system calendar."))
        stackView.addArrangedSubviewWithMargin(page)
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView().with(footer: L10n.tr("The export will not modify the class schedule data, it will only be written to the system calendar."))
        )
        stackView.addArrangedSubviewWithMargin(UIView())
    }
}

@MainActor
private final class CalendarImportSettingsController: SettingsReloadableStackScrollController {
    private struct TimeSlot: Hashable {
        let startMinute: Int
        let endMinute: Int
    }

    private struct EventOccurrence {
        let week: Int
        let weekday: Int
        let startPeriod: Int
        let endPeriod: Int
        let location: String?
    }

    private struct CourseBucket {
        var name: String
        var location: String?
        var note: String?
        var occurrences: [EventOccurrence]
    }

    private struct MeetingSignature: Hashable {
        let weekday: Int
        let startPeriod: Int
        let endPeriod: Int
        let location: String?
    }

    private let repository: any TimetableRepositoryProtocol
    private let onRepositoryChanged: () -> Void
    private let eventStore = EKEventStore()
    private let calendar = Calendar(identifier: .gregorian)

    private var calendarAuthorizationStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    private var availableCalendars: [EKCalendar] = []
    private var selectedCalendarIDs: Set<String> = []
    private var rangeStartDate: Date
    private var rangeEndDate: Date
    private var timetableName: String
    private var isImporting = false

    init(repository: any TimetableRepositoryProtocol, onRepositoryChanged: @escaping () -> Void) {
        self.repository = repository
        self.onRepositoryChanged = onRepositoryChanged

        let today = Calendar(identifier: .gregorian).startOfDay(for: Date())
        rangeStartDate = today
        rangeEndDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: 16 * 7, to: today) ?? today
        timetableName = "日历导入 \(formatDateInput(Date()))"

        super.init(nibName: nil, bundle: nil)
        title = L10n.tr("Import calendar")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshCalendarAccessState()
        rebuildContent()
    }

    override func buildContent() {
        appendEditableField(
            icon: "calendar.badge.clock",
            title: L10n.tr("Calendar read permission"),
            description: calendarPermissionActionDescription,
            value: calendarAuthorizationStatusLabel(calendarAuthorizationStatus),
            placeholder: ""
        ) { [weak self] _ in
            self?.handleCalendarPermissionTap()
        }

        guard hasCalendarReadPermission(status: calendarAuthorizationStatus) else {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(footer: L10n.tr("Calendar reading needs to be allowed before system calendar events can be imported."))
            )
            stackView.addArrangedSubviewWithMargin(UIView())
            return
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: L10n.tr("Source Calendar"))
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        if availableCalendars.isEmpty {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(footer: L10n.tr("There is currently no system calendar to read."))
            )
            stackView.addArrangedSubview(SeparatorView())
        } else {
            for sourceCalendar in availableCalendars {
                appendSwitchField(
                    icon: "calendar",
                    title: sourceCalendar.title,
                    description: sourceCalendar.source.title,
                    isOn: selectedCalendarIDs.contains(sourceCalendar.calendarIdentifier)
                ) { [weak self] isOn in
                    self?.toggleCalendarSelection(id: sourceCalendar.calendarIdentifier, isOn: isOn)
                }
            }
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: L10n.tr("Import settings"))
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        appendEditableField(
            icon: "textformat",
            title: L10n.tr("Class schedule name"),
            description: L10n.tr("After importing, a new class schedule will be created."),
            value: timetableName,
            placeholder: ""
        ) { [weak self] view in
            self?.presentNameEditor(from: view)
        }

        appendEditableField(
            icon: "calendar",
            title: L10n.tr("start date"),
            description: L10n.tr("Only events on and after this date will be imported."),
            value: formatDateInput(rangeStartDate),
            placeholder: ""
        ) { [weak self] view in
            self?.presentDateEditor(from: view, editingStart: true)
        }

        appendEditableField(
            icon: "calendar",
            title: L10n.tr("end date"),
            description: L10n.tr("Only events on and before this date will be imported."),
            value: formatDateInput(rangeEndDate),
            placeholder: ""
        ) { [weak self] view in
            self?.presentDateEditor(from: view, editingStart: false)
        }

        let importAction = ConfigurableActionView { [weak self] _ in
            self?.startImport()
        }
        importAction.configure(icon: UIImage(systemName: isImporting ? "hourglass" : "square.and.arrow.down"))
        importAction.configure(title: isImporting ? L10n.tr("Importing…") : L10n.tr("Start importing"))
        importAction.configure(description: "\(selectedCalendarIDs.count) 个日历 · \(formatDateInput(rangeStartDate)) 至 \(formatDateInput(rangeEndDate))")
        importAction.isUserInteractionEnabled = !isImporting
        stackView.addArrangedSubviewWithMargin(importAction)
        stackView.addArrangedSubview(SeparatorView())

        let refreshAction = ConfigurableActionView { [weak self] _ in
            self?.refreshCalendarAccessState()
            self?.rebuildContent()
        }
        refreshAction.configure(icon: UIImage(systemName: "arrow.clockwise"))
        refreshAction.configure(title: L10n.tr("Refresh calendar list"))
        refreshAction.configure(description: L10n.tr("The system calendar can be refreshed manually when there are changes."))
        stackView.addArrangedSubviewWithMargin(refreshAction)
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView().with(
                footer: L10n.tr("Import rules: All-day events and cross-day events will be ignored; remaining events will be automatically converted by week and week.")
            )
        )
        stackView.addArrangedSubviewWithMargin(UIView())
    }

    private func refreshCalendarAccessState() {
        calendarAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
        guard hasCalendarReadPermission(status: calendarAuthorizationStatus) else {
            availableCalendars = []
            selectedCalendarIDs = []
            return
        }

        availableCalendars = eventStore.calendars(for: .event).sorted {
            if $0.source.title != $1.source.title {
                return $0.source.title.localizedCompare($1.source.title) == .orderedAscending
            }
            return $0.title.localizedCompare($1.title) == .orderedAscending
        }

        if selectedCalendarIDs.isEmpty {
            selectedCalendarIDs = Set(availableCalendars.map(\.calendarIdentifier))
        } else {
            let availableIDs = Set(availableCalendars.map(\.calendarIdentifier))
            selectedCalendarIDs.formIntersection(availableIDs)
            if selectedCalendarIDs.isEmpty {
                selectedCalendarIDs = availableIDs
            }
        }
    }

    private func handleCalendarPermissionTap() {
        if hasCalendarReadPermission(status: calendarAuthorizationStatus) {
            refreshCalendarAccessState()
            rebuildContent()
            return
        }

        switch calendarAuthorizationStatus {
        case .notDetermined:
            requestCalendarPermission()
        case .denied, .restricted:
            openSystemSettings()
        case .authorized:
            refreshCalendarAccessState()
            rebuildContent()
        @unknown default:
            if #available(iOS 17.0, *) {
                if calendarAuthorizationStatus == .writeOnly {
                    requestCalendarPermission()
                    return
                }
                if calendarAuthorizationStatus == .fullAccess {
                    refreshCalendarAccessState()
                    rebuildContent()
                    return
                }
            }
            rebuildContent()
        }
    }

    private func requestCalendarPermission() {
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await requestCalendarReadPermission(using: eventStore)
                refreshCalendarAccessState()
                rebuildContent()
            } catch {
                presentError(error)
            }
        }
    }

    private func startImport() {
        guard !isImporting else { return }
        guard hasCalendarReadPermission(status: calendarAuthorizationStatus) else {
            handleCalendarPermissionTap()
            return
        }
        guard !selectedCalendarIDs.isEmpty else {
            presentMessage(title: L10n.tr("Unable to import"), message: L10n.tr("Please select at least one calendar."))
            return
        }
        guard rangeStartDate <= rangeEndDate else {
            presentMessage(title: L10n.tr("Invalid date range"), message: L10n.tr("End date cannot be earlier than start date."))
            return
        }

        isImporting = true
        rebuildContent()

        Task { [weak self] in
            guard let self else { return }
            do {
                let draft = try buildImportDraft()
                let _ = try await repository.importTimetableDraft(draft)
                NotificationCenter.default.post(name: .timetableRepositoryDidChange, object: nil)
                onRepositoryChanged()
                isImporting = false
                rebuildContent()
                presentMessage(
                    title: L10n.tr("Import completed"),
                    message: "已创建课表「\(draft.name)」，共 \(draft.courses.count) 门课程。"
                ) { [weak self] in
                    self?.navigationController?.popViewController(animated: true)
                }
            } catch {
                isImporting = false
                rebuildContent()
                presentError(error)
            }
        }
    }

    private func buildImportDraft() throws -> ImportedTimetableDraft {
        let selectedCalendars = availableCalendars.filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
        guard !selectedCalendars.isEmpty else {
            throw AppError.validation(L10n.tr("Please select at least one calendar."))
        }

        let rangeStart = calendar.startOfDay(for: rangeStartDate)
        let rangeEnd = calendar.startOfDay(for: rangeEndDate)
        guard let endExclusive = calendar.date(byAdding: .day, value: 1, to: rangeEnd) else {
            throw AppError.validation(L10n.tr("Invalid import date range."))
        }

        let predicate = eventStore.predicateForEvents(withStart: rangeStart, end: endExclusive, calendars: selectedCalendars)
        let events = eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }

        var skippedAllDay = 0
        var skippedCrossDay = 0
        var skippedInvalidTime = 0

        struct PreparedEvent {
            let key: String
            let name: String
            let location: String?
            let note: String?
            let day: Date
            let weekday: Int
            let startMinute: Int
            let endMinute: Int
        }

        var preparedEvents: [PreparedEvent] = []
        preparedEvents.reserveCapacity(events.count)

        for event in events {
            if event.isAllDay {
                skippedAllDay += 1
                continue
            }

            if !calendar.isDate(event.startDate, inSameDayAs: event.endDate) {
                skippedCrossDay += 1
                continue
            }

            let startMinute = minuteOfDay(event.startDate)
            let endMinute = minuteOfDay(event.endDate)
            guard endMinute > startMinute else {
                skippedInvalidTime += 1
                continue
            }

            let normalizedTitle = normalizeWhitespace(event.title)
            let name = normalizedTitle.isEmpty ? L10n.tr("Calendar events") : normalizedTitle
            let location = normalizeOptionalText(event.location)
            let note = normalizeOptionalText(event.notes)
            let day = calendar.startOfDay(for: event.startDate)
            let weekday = toInternalWeekday(event.startDate)
            let key = [name, location ?? "", event.calendar.calendarIdentifier].joined(separator: "|")

            preparedEvents.append(
                PreparedEvent(
                    key: key,
                    name: name,
                    location: location,
                    note: note,
                    day: day,
                    weekday: weekday,
                    startMinute: startMinute,
                    endMinute: endMinute
                )
            )
        }

        guard !preparedEvents.isEmpty else {
            throw AppError.validation(L10n.tr("There are no calendar events that can be imported within the selection range (all-day events and cross-day events will be ignored)."))
        }

        guard let firstDay = preparedEvents.map(\.day).min(),
              let lastDay = preparedEvents.map(\.day).max()
        else {
            throw AppError.validation(L10n.tr("Unable to parse calendar event date."))
        }

        let importStartDate = startOfWeekMonday(for: firstDay)
        let daysDiff = calendar.dateComponents([.day], from: importStartDate, to: lastDay).day ?? 0
        let weeksCount = max(1, daysDiff / 7 + 1)

        var slotSet = Set<TimeSlot>()
        for event in preparedEvents {
            slotSet.insert(TimeSlot(startMinute: event.startMinute, endMinute: event.endMinute))
        }
        let slots = slotSet.sorted {
            if $0.startMinute != $1.startMinute {
                return $0.startMinute < $1.startMinute
            }
            return $0.endMinute < $1.endMinute
        }
        guard !slots.isEmpty else {
            throw AppError.validation(L10n.tr("Import failed: Unable to generate section."))
        }

        var periodBySlot: [TimeSlot: Int] = [:]
        for (index, slot) in slots.enumerated() {
            periodBySlot[slot] = index + 1
        }

        let periods: [ImportedPeriodDraft] = slots.enumerated().map { index, slot in
            ImportedPeriodDraft(
                periodIndex: index + 1,
                startTime: formatMinuteOfDay(slot.startMinute),
                endTime: formatMinuteOfDay(slot.endMinute)
            )
        }

        var buckets: [String: CourseBucket] = [:]
        for event in preparedEvents {
            let dayOffset = calendar.dateComponents([.day], from: importStartDate, to: event.day).day ?? 0
            let week = max(1, dayOffset / 7 + 1)
            guard week <= weeksCount else { continue }
            let slot = TimeSlot(startMinute: event.startMinute, endMinute: event.endMinute)
            guard let periodIndex = periodBySlot[slot] else { continue }

            let occurrence = EventOccurrence(
                week: week,
                weekday: event.weekday,
                startPeriod: periodIndex,
                endPeriod: periodIndex,
                location: event.location
            )

            if var bucket = buckets[event.key] {
                bucket.occurrences.append(occurrence)
                if bucket.note == nil {
                    bucket.note = event.note
                }
                buckets[event.key] = bucket
            } else {
                buckets[event.key] = CourseBucket(
                    name: event.name,
                    location: event.location,
                    note: event.note,
                    occurrences: [occurrence]
                )
            }
        }

        var courses: [ImportedCourseDraft] = []
        courses.reserveCapacity(buckets.count)

        for bucket in buckets.values.sorted(by: { $0.name.localizedCompare($1.name) == .orderedAscending }) {
            let groups = Dictionary(grouping: bucket.occurrences) {
                MeetingSignature(
                    weekday: $0.weekday,
                    startPeriod: $0.startPeriod,
                    endPeriod: $0.endPeriod,
                    location: $0.location
                )
            }

            var meetings: [ImportedMeetingDraft] = []
            for (signature, occurrences) in groups {
                let weeks = Array(Set(occurrences.map(\.week))).sorted()
                for range in compressWeeksIntoRanges(weeks) {
                    meetings.append(
                        ImportedMeetingDraft(
                            weekday: signature.weekday,
                            startWeek: range.lowerBound,
                            endWeek: range.upperBound,
                            startPeriod: signature.startPeriod,
                            endPeriod: signature.endPeriod,
                            location: signature.location,
                            weekType: .all
                        )
                    )
                }
            }

            meetings.sort {
                if $0.weekday != $1.weekday { return $0.weekday < $1.weekday }
                if $0.startPeriod != $1.startPeriod { return $0.startPeriod < $1.startPeriod }
                if $0.startWeek != $1.startWeek { return $0.startWeek < $1.startWeek }
                return $0.endWeek < $1.endWeek
            }

            courses.append(
                ImportedCourseDraft(
                    name: bucket.name,
                    teacher: nil,
                    location: bucket.location,
                    color: nil,
                    note: bucket.note,
                    meetings: meetings
                )
            )
        }

        guard !courses.isEmpty else {
            throw AppError.validation(L10n.tr("Import failed: No course data available."))
        }

        var warnings: [ImportWarning] = []
        let skippedCount = skippedAllDay + skippedCrossDay + skippedInvalidTime
        if skippedCount > 0 {
            warnings.append(
                ImportWarning(
                    code: "calendar_event_skipped",
                    message: "已忽略 \(skippedCount) 条事件（全天 \(skippedAllDay) 条、跨天 \(skippedCrossDay) 条、时间无效 \(skippedInvalidTime) 条）。",
                    severity: .info
                )
            )
        }

        let normalizedName = normalizeWhitespace(timetableName)
        let finalName = normalizedName.isEmpty ? "日历导入 \(formatDateInput(Date()))" : normalizedName
        let selectedCalendarTitle = selectedCalendars.map(\.title).joined(separator: ", ")

        return ImportedTimetableDraft(
            name: finalName,
            startDate: formatDateInput(importStartDate),
            weeksCount: weeksCount,
            periods: periods,
            courses: courses,
            warnings: warnings,
            source: .init(
                adapterId: "system-calendar",
                adapterLabel: L10n.tr("System calendar"),
                capturedAt: nowISO8601String(),
                url: "local://calendar",
                title: selectedCalendarTitle.isEmpty ? nil : selectedCalendarTitle
            )
        )
    }

    private func presentNameEditor(from view: UIView) {
        let input = AlertInputViewController(
            title: L10n.tr("Class schedule name"),
            message: L10n.tr("After importing, a new class schedule will be created."),
            placeholder: "",
            text: timetableName,
            cancelButtonText: L10n.tr("Cancel"),
            doneButtonText: L10n.tr("Sure")
        ) { [weak self] value in
            guard let self else { return }
            timetableName = value
            rebuildContent()
        }
        view.hostingViewController?.present(input, animated: true)
    }

    private func presentDateEditor(from view: UIView, editingStart: Bool) {
        let selectedDate = editingStart ? rangeStartDate : rangeEndDate
        let picker = AlertDatePickerViewController(
            title: editingStart ? L10n.tr("start date") : L10n.tr("end date"),
            message: L10n.tr("Select the import date."),
            mode: .date,
            selectedDate: selectedDate
        ) { [weak self] date in
            guard let self else { return }
            let day = calendar.startOfDay(for: date)
            if editingStart {
                rangeStartDate = day
                if rangeEndDate < rangeStartDate {
                    rangeEndDate = rangeStartDate
                }
            } else {
                rangeEndDate = day
                if rangeEndDate < rangeStartDate {
                    rangeStartDate = rangeEndDate
                }
            }
            rebuildContent()
        }
        view.hostingViewController?.present(picker, animated: true)
    }

    private func toggleCalendarSelection(id: String, isOn: Bool) {
        if isOn {
            selectedCalendarIDs.insert(id)
        } else {
            selectedCalendarIDs.remove(id)
        }
        rebuildContent()
    }

    private var calendarPermissionActionDescription: String {
        switch calendarAuthorizationStatus {
        case .notDetermined:
            return L10n.tr("Click to apply for permission to read the calendar.")
        case .restricted:
            return L10n.tr("System limit and cannot be modified.")
        case .denied:
            return L10n.tr("Rejected, click to go to system settings to turn it on.")
        case .authorized:
            return L10n.tr("Authorized to read the system calendar.")
        @unknown default:
            if #available(iOS 17.0, *) {
                if calendarAuthorizationStatus == .writeOnly {
                    return L10n.tr("Write permission only, click to upgrade to read.")
                }
                if calendarAuthorizationStatus == .fullAccess {
                    return L10n.tr("Authorized to read the system calendar.")
                }
            }
            return L10n.tr("Permission status is unknown.")
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func minuteOfDay(_ date: Date) -> Int {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return hour * 60 + minute
    }

    private func toInternalWeekday(_ date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    private func startOfWeekMonday(for date: Date) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        let offset = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: date) ?? date
    }

    private func formatMinuteOfDay(_ minute: Int) -> String {
        let hour = minute / 60
        let minuteOfHour = minute % 60
        return String(format: "%02d:%02d", hour, minuteOfHour)
    }

    private func compressWeeksIntoRanges(_ weeks: [Int]) -> [ClosedRange<Int>] {
        guard !weeks.isEmpty else { return [] }
        var ranges: [ClosedRange<Int>] = []
        var start = weeks[0]
        var end = weeks[0]

        for week in weeks.dropFirst() {
            if week == end + 1 {
                end = week
            } else {
                ranges.append(start ... end)
                start = week
                end = week
            }
        }

        ranges.append(start ... end)
        return ranges
    }

    private func presentMessage(title: String, message: String, completion: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.tr("knew"), style: .default) { _ in completion?() })
        present(alert, animated: true)
    }

    private func presentError(_ error: Error) {
        presentMessage(title: L10n.tr("Import failed"), message: error.localizedDescription)
    }

    private func appendSwitchField(icon: String, title: String, description: String?, isOn: Bool, onToggle: @escaping (Bool) -> Void) {
        let view = SettingsSwitchFieldView()
        view.configure(icon: UIImage(systemName: icon))
        view.configure(title: title)
        view.configure(description: description ?? "")
        view.configure(isOn: isOn, onToggle: onToggle)
        stackView.addArrangedSubviewWithMargin(view)
        stackView.addArrangedSubview(SeparatorView())
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

@MainActor
private final class CalendarExportSettingsController: SettingsReloadableStackScrollController {
    private struct ExportEventDraft {
        let title: String
        let startDate: Date
        let endDate: Date
        let location: String?
        let notes: String?
        let url: URL?
    }

    private struct ExportSummary {
        let createdCount: Int
        let removedCount: Int
        let skippedCount: Int
    }

    private let repository: any TimetableRepositoryProtocol
    private let eventStore = EKEventStore()
    private let calendar = Calendar(identifier: .gregorian)

    private var calendarAuthorizationStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    private var availableCalendars: [EKCalendar] = []
    private var availableTimetables: [Timetable] = []
    private var selectedTimetableID: String?
    private var selectedCalendarID: String?
    private var rangeStartDate: Date
    private var rangeEndDate: Date
    private var isExporting = false

    private var selectedTimetable: Timetable? {
        availableTimetables.first { $0.id == selectedTimetableID }
    }

    private var selectedCalendar: EKCalendar? {
        availableCalendars.first { $0.calendarIdentifier == selectedCalendarID }
    }

    init(repository: any TimetableRepositoryProtocol) {
        self.repository = repository

        let today = Calendar(identifier: .gregorian).startOfDay(for: Date())
        rangeStartDate = today
        rangeEndDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: 16 * 7, to: today) ?? today

        super.init(nibName: nil, bundle: nil)
        title = L10n.tr("Export to calendar")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshCalendarAccessState()
        rebuildContent()
        Task { [weak self] in
            await self?.refreshTimetableState()
        }
    }

    override func buildContent() {
        appendEditableField(
            icon: "calendar.badge.clock",
            title: L10n.tr("Calendar access"),
            description: calendarPermissionActionDescription,
            value: calendarAuthorizationStatusLabel(calendarAuthorizationStatus),
            placeholder: ""
        ) { [weak self] _ in
            self?.handleCalendarPermissionTap()
        }

        guard hasCalendarReadPermission(status: calendarAuthorizationStatus) else {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(footer: L10n.tr("You need to allow access to the calendar before you can export the class schedule to the system calendar."))
            )
            stackView.addArrangedSubviewWithMargin(UIView())
            return
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: L10n.tr("Source schedule"))
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        if availableTimetables.isEmpty {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(footer: L10n.tr("There is currently no class schedule. Please create a new class schedule or import a class schedule first."))
            )
            stackView.addArrangedSubview(SeparatorView())
        } else {
            appendEditableField(
                icon: "tablecells",
                title: L10n.tr("curriculum"),
                description: selectedTimetable.map { buildTimetableSummary($0) },
                value: selectedTimetable?.name ?? L10n.tr("Please select"),
                placeholder: ""
            ) { [weak self] view in
                self?.presentTimetablePicker(from: view)
            }
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: L10n.tr("target calendar"))
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        if availableCalendars.isEmpty {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(footer: L10n.tr("There are currently no system calendars available for writing."))
            )
            stackView.addArrangedSubview(SeparatorView())
        } else {
            appendEditableField(
                icon: "calendar",
                title: L10n.tr("write to"),
                description: selectedCalendar?.source.title ?? L10n.tr("Please select a system calendar to write to."),
                value: selectedCalendar?.title ?? L10n.tr("Please select"),
                placeholder: ""
            ) { [weak self] view in
                self?.presentCalendarPicker(from: view)
            }
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: L10n.tr("Export settings"))
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        appendEditableField(
            icon: "calendar",
            title: L10n.tr("start date"),
            description: L10n.tr("Only courses on and after this date will be exported."),
            value: formatDateInput(rangeStartDate),
            placeholder: ""
        ) { [weak self] view in
            self?.presentDateEditor(from: view, editingStart: true)
        }

        appendEditableField(
            icon: "calendar",
            title: L10n.tr("end date"),
            description: L10n.tr("Only courses on and before this date will be exported."),
            value: formatDateInput(rangeEndDate),
            placeholder: ""
        ) { [weak self] view in
            self?.presentDateEditor(from: view, editingStart: false)
        }

        let timetableName = selectedTimetable?.name ?? L10n.tr("No class schedule selected")
        let calendarName = selectedCalendar?.title ?? L10n.tr("No calendar selected")

        let exportAction = ConfigurableActionView { [weak self] _ in
            self?.startExport()
        }
        exportAction.configure(icon: UIImage(systemName: isExporting ? "hourglass" : "square.and.arrow.up"))
        exportAction.configure(title: isExporting ? L10n.tr("Exporting…") : L10n.tr("Start export"))
        exportAction.configure(
            description: "\(timetableName) -> \(calendarName) · \(formatDateInput(rangeStartDate)) 至 \(formatDateInput(rangeEndDate))"
        )
        exportAction.isUserInteractionEnabled = !isExporting
        stackView.addArrangedSubviewWithMargin(exportAction)
        stackView.addArrangedSubview(SeparatorView())

        let refreshAction = ConfigurableActionView { [weak self] _ in
            guard let self else { return }
            refreshCalendarAccessState()
            rebuildContent()
            Task { [weak self] in
                await self?.refreshTimetableState()
            }
        }
        refreshAction.configure(icon: UIImage(systemName: "arrow.clockwise"))
        refreshAction.configure(title: L10n.tr("Refresh data"))
        refreshAction.configure(description: L10n.tr("You can manually refresh the class schedule or system calendar when there are changes."))
        stackView.addArrangedSubviewWithMargin(refreshAction)
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView().with(
                footer: L10n.tr("Export rules: Events created by CourseList in the same range of the target calendar of the current class schedule will be deleted first, and then the latest courses will be written.")
            )
        )
        stackView.addArrangedSubviewWithMargin(UIView())
    }

    private func refreshCalendarAccessState() {
        calendarAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
        guard hasCalendarReadPermission(status: calendarAuthorizationStatus) else {
            availableCalendars = []
            selectedCalendarID = nil
            return
        }

        let writableCalendars = eventStore.calendars(for: .event).filter(\.allowsContentModifications)
        availableCalendars = writableCalendars.sorted {
            if $0.source.title != $1.source.title {
                return $0.source.title.localizedCompare($1.source.title) == .orderedAscending
            }
            return $0.title.localizedCompare($1.title) == .orderedAscending
        }

        let availableIDs = Set(availableCalendars.map(\.calendarIdentifier))
        if let selectedCalendarID, availableIDs.contains(selectedCalendarID) {
            return
        }

        if let defaultCalendar = eventStore.defaultCalendarForNewEvents,
           availableIDs.contains(defaultCalendar.calendarIdentifier) {
            self.selectedCalendarID = defaultCalendar.calendarIdentifier
        } else {
            self.selectedCalendarID = availableCalendars.first?.calendarIdentifier
        }
    }

    private func refreshTimetableState() async {
        do {
            let timetables = try await repository.listTimetables().sorted { shouldDisplayTimetableBefore($0, $1) }
            availableTimetables = timetables

            let availableIDs = Set(timetables.map(\.id))
            let previousSelectedID = selectedTimetableID
            if let selectedTimetableID, availableIDs.contains(selectedTimetableID) {
                // Keep existing selection.
            } else {
                selectedTimetableID = resolvePreferredTimetable(timetables: timetables)?.id
            }

            if selectedTimetableID != previousSelectedID, let timetable = selectedTimetable {
                applyDateRange(from: timetable)
            }
        } catch {
            availableTimetables = []
            selectedTimetableID = nil
            presentError(error)
        }
        rebuildContent()
    }

    private func handleCalendarPermissionTap() {
        if hasCalendarReadPermission(status: calendarAuthorizationStatus) {
            refreshCalendarAccessState()
            rebuildContent()
            return
        }

        switch calendarAuthorizationStatus {
        case .notDetermined:
            requestCalendarPermission()
        case .denied, .restricted:
            openSystemSettings()
        case .authorized:
            refreshCalendarAccessState()
            rebuildContent()
        @unknown default:
            if #available(iOS 17.0, *) {
                if calendarAuthorizationStatus == .writeOnly {
                    requestCalendarPermission()
                    return
                }
                if calendarAuthorizationStatus == .fullAccess {
                    refreshCalendarAccessState()
                    rebuildContent()
                    return
                }
            }
            rebuildContent()
        }
    }

    private func requestCalendarPermission() {
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await requestCalendarReadPermission(using: eventStore)
                refreshCalendarAccessState()
                rebuildContent()
            } catch {
                presentError(error)
            }
        }
    }

    private func applyDateRange(from timetable: Timetable) {
        guard let parsedStartDate = parseDateInput(timetable.startDate) else { return }
        let startDay = calendar.startOfDay(for: parsedStartDate)
        let durationDays = max(1, timetable.weeksCount * 7)
        let endDay = calendar.date(byAdding: .day, value: durationDays - 1, to: startDay) ?? startDay
        rangeStartDate = startDay
        rangeEndDate = endDay
    }

    private func startExport() {
        guard !isExporting else { return }
        guard hasCalendarReadPermission(status: calendarAuthorizationStatus) else {
            handleCalendarPermissionTap()
            return
        }
        guard selectedTimetable != nil else {
            presentMessage(title: L10n.tr("Unable to export"), message: L10n.tr("Please select your class schedule first."))
            return
        }
        guard selectedCalendar != nil else {
            presentMessage(title: L10n.tr("Unable to export"), message: L10n.tr("Please select a destination calendar first."))
            return
        }
        guard rangeStartDate <= rangeEndDate else {
            presentMessage(title: L10n.tr("Invalid date range"), message: L10n.tr("End date cannot be earlier than start date."))
            return
        }

        isExporting = true
        rebuildContent()

        Task { [weak self] in
            guard let self else { return }
            do {
                let summary = try await exportTimetableToCalendar()
                isExporting = false
                rebuildContent()

                let message: String
                if summary.skippedCount > 0 {
                    message = "已写入 \(summary.createdCount) 条课程事件，替换 \(summary.removedCount) 条旧事件，忽略 \(summary.skippedCount) 条无效课程数据。"
                } else {
                    message = "已写入 \(summary.createdCount) 条课程事件，替换 \(summary.removedCount) 条旧事件。"
                }
                presentMessage(title: L10n.tr("Export completed"), message: message) { [weak self] in
                    self?.navigationController?.popViewController(animated: true)
                }
            } catch {
                isExporting = false
                rebuildContent()
                presentError(error)
            }
        }
    }

    private func exportTimetableToCalendar() async throws -> ExportSummary {
        guard let timetable = selectedTimetable else {
            throw AppError.validation(L10n.tr("Please select your class schedule first."))
        }
        guard let targetCalendar = selectedCalendar else {
            throw AppError.validation(L10n.tr("Please select a destination calendar first."))
        }
        guard let parsedStartDate = parseDateInput(timetable.startDate) else {
            throw AppError.validation(L10n.tr("The schedule start date is invalid."))
        }

        let timetableStartDay = calendar.startOfDay(for: parsedStartDate)
        let rangeStart = calendar.startOfDay(for: rangeStartDate)
        let rangeEnd = calendar.startOfDay(for: rangeEndDate)
        guard let rangeEndExclusive = calendar.date(byAdding: .day, value: 1, to: rangeEnd) else {
            throw AppError.validation(L10n.tr("Invalid export date range."))
        }

        async let periodsTask = repository.listPeriods(timetableId: timetable.id)
        async let coursesTask = repository.listCourses(timetableId: timetable.id)
        let periods = try await periodsTask
        let courses = try await coursesTask
        let periodByIndex = Dictionary(uniqueKeysWithValues: periods.map { ($0.periodIndex, $0) })

        var skippedCount = 0
        var eventDrafts: [ExportEventDraft] = []

        for course in courses {
            for meeting in course.meetings {
                guard meeting.startWeek <= meeting.endWeek,
                      let startPeriod = periodByIndex[meeting.startPeriod],
                      let endPeriod = periodByIndex[meeting.endPeriod],
                      let startClock = timeClock(from: startPeriod.startTime),
                      let endClock = timeClock(from: endPeriod.endTime)
                else {
                    skippedCount += 1
                    continue
                }

                for week in meeting.startWeek ... meeting.endWeek {
                    guard weekMatchesType(week, weekType: meeting.weekType) else { continue }
                    guard let startDate = makeClassDate(
                        timetableStartDay: timetableStartDay,
                        week: week,
                        weekday: meeting.weekday,
                        hour: startClock.hour,
                        minute: startClock.minute
                    ),
                    let endDate = makeClassDate(
                        timetableStartDay: timetableStartDay,
                        week: week,
                        weekday: meeting.weekday,
                        hour: endClock.hour,
                        minute: endClock.minute
                    ),
                    endDate > startDate
                    else {
                        skippedCount += 1
                        continue
                    }

                    guard startDate >= rangeStart, startDate < rangeEndExclusive else { continue }

                    let location = normalizeOptionalText(meeting.location ?? course.location)
                    let notes = buildEventNotes(timetable: timetable, course: course, meeting: meeting, week: week)
                    let eventURL = buildExportEventURL(
                        timetableID: timetable.id,
                        courseID: course.id,
                        meetingID: meeting.id,
                        week: week
                    )

                    eventDrafts.append(
                        ExportEventDraft(
                            title: course.name,
                            startDate: startDate,
                            endDate: endDate,
                            location: location,
                            notes: notes,
                            url: eventURL
                        )
                    )
                }
            }
        }

        guard !eventDrafts.isEmpty else {
            throw AppError.validation(L10n.tr("There are no exportable courses in the selection."))
        }

        let predicate = eventStore.predicateForEvents(withStart: rangeStart, end: rangeEndExclusive, calendars: [targetCalendar])
        let existingEvents = eventStore.events(matching: predicate).filter { isExportedByCourseList($0, timetableID: timetable.id) }

        do {
            for event in existingEvents {
                try eventStore.remove(event, span: .thisEvent, commit: false)
            }

            for draft in eventDrafts {
                let event = EKEvent(eventStore: eventStore)
                event.calendar = targetCalendar
                event.title = draft.title
                event.startDate = draft.startDate
                event.endDate = draft.endDate
                event.location = draft.location
                event.notes = draft.notes
                event.url = draft.url
                try eventStore.save(event, span: .thisEvent, commit: false)
            }

            try eventStore.commit()
        } catch {
            eventStore.reset()
            throw error
        }

        return ExportSummary(
            createdCount: eventDrafts.count,
            removedCount: existingEvents.count,
            skippedCount: skippedCount
        )
    }

    private func presentTimetablePicker(from view: UIView) {
        guard !availableTimetables.isEmpty else { return }
        let options = availableTimetables.map(\.name)
        let selectedIndex = availableTimetables.firstIndex { $0.id == selectedTimetableID } ?? 0
        let picker = SettingsAlertOptionPickerViewController(
            title: L10n.tr("Select class schedule"),
            message: L10n.tr("Select the class schedule to export to the calendar."),
            options: options,
            selectedIndex: selectedIndex
        ) { [weak self] index in
            guard let self else { return }
            let selected = availableTimetables[index]
            selectedTimetableID = selected.id
            applyDateRange(from: selected)
            rebuildContent()
        }
        view.hostingViewController?.present(picker, animated: true)
    }

    private func presentCalendarPicker(from view: UIView) {
        guard !availableCalendars.isEmpty else { return }
        let options = availableCalendars.map(\.title)
        let selectedIndex = availableCalendars.firstIndex { $0.calendarIdentifier == selectedCalendarID } ?? 0
        let picker = SettingsAlertOptionPickerViewController(
            title: L10n.tr("Select target calendar"),
            message: L10n.tr("Select the target calendar from the system calendar."),
            options: options,
            selectedIndex: selectedIndex
        ) { [weak self] index in
            guard let self else { return }
            selectedCalendarID = availableCalendars[index].calendarIdentifier
            rebuildContent()
        }
        view.hostingViewController?.present(picker, animated: true)
    }

    private func presentDateEditor(from view: UIView, editingStart: Bool) {
        let selectedDate = editingStart ? rangeStartDate : rangeEndDate
        let picker = AlertDatePickerViewController(
            title: editingStart ? L10n.tr("start date") : L10n.tr("end date"),
            message: L10n.tr("Select the export date."),
            mode: .date,
            selectedDate: selectedDate
        ) { [weak self] date in
            guard let self else { return }
            let day = calendar.startOfDay(for: date)
            if editingStart {
                rangeStartDate = day
                if rangeEndDate < rangeStartDate {
                    rangeEndDate = rangeStartDate
                }
            } else {
                rangeEndDate = day
                if rangeEndDate < rangeStartDate {
                    rangeStartDate = rangeEndDate
                }
            }
            rebuildContent()
        }
        view.hostingViewController?.present(picker, animated: true)
    }

    private func makeClassDate(
        timetableStartDay: Date,
        week: Int,
        weekday: Int,
        hour: Int,
        minute: Int
    ) -> Date? {
        guard (1 ... 7).contains(weekday), week >= 1 else { return nil }
        guard let day = calendar.date(byAdding: .day, value: (week - 1) * 7 + (weekday - 1), to: timetableStartDay) else {
            return nil
        }

        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)
    }

    private func timeClock(from value: String) -> (hour: Int, minute: Int)? {
        guard let date = parseTimeInput(value) else { return nil }
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return (hour, minute)
    }

    private func buildEventNotes(timetable: Timetable, course: CourseWithMeetings, meeting: CourseMeeting, week: Int) -> String {
        var lines = ["来自课表：\(timetable.name)", "周次：第\(week)周"]
        if let teacher = normalizeOptionalText(course.teacher) {
            lines.append("教师：\(teacher)")
        }
        if let note = normalizeOptionalText(course.note) {
            lines.append("备注：\(note)")
        }
        if let meetingLocation = normalizeOptionalText(meeting.location) {
            lines.append("地点：\(meetingLocation)")
        }
        return lines.joined(separator: "\n")
    }

    private func buildExportEventURL(timetableID: String, courseID: String, meetingID: String, week: Int) -> URL? {
        var components = URLComponents()
        components.scheme = "courselist"
        components.host = "calendar-export"
        components.queryItems = [
            .init(name: "timetableId", value: timetableID),
            .init(name: "courseId", value: courseID),
            .init(name: "meetingId", value: meetingID),
            .init(name: "week", value: String(week)),
        ]
        return components.url
    }

    private func isExportedByCourseList(_ event: EKEvent, timetableID: String) -> Bool {
        guard let eventURL = event.url,
              let components = URLComponents(url: eventURL, resolvingAgainstBaseURL: false),
              components.scheme == "courselist",
              components.host == "calendar-export"
        else {
            return false
        }
        return components.queryItems?.first(where: { $0.name == "timetableId" })?.value == timetableID
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var calendarPermissionActionDescription: String {
        switch calendarAuthorizationStatus {
        case .notDetermined:
            return L10n.tr("Click Request calendar access.")
        case .restricted:
            return L10n.tr("System limit and cannot be modified.")
        case .denied:
            return L10n.tr("Rejected, click to go to system settings to turn it on.")
        case .authorized:
            return L10n.tr("Authorized to access the system calendar.")
        @unknown default:
            if #available(iOS 17.0, *) {
                if calendarAuthorizationStatus == .writeOnly {
                    return L10n.tr("Write permission only, click to upgrade to read and write.")
                }
                if calendarAuthorizationStatus == .fullAccess {
                    return L10n.tr("Authorized to read and write the system calendar.")
                }
            }
            return L10n.tr("Permission status is unknown.")
        }
    }

    private func presentMessage(title: String, message: String, completion: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.tr("knew"), style: .default) { _ in completion?() })
        present(alert, animated: true)
    }

    private func presentError(_ error: Error) {
        presentMessage(title: L10n.tr("Export failed"), message: error.localizedDescription)
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

private func hasCalendarReadPermission(status: EKAuthorizationStatus) -> Bool {
    if #available(iOS 17.0, *) {
        return status == .fullAccess || status == .authorized
    }
    return status == .authorized
}

private func calendarAuthorizationStatusLabel(_ status: EKAuthorizationStatus) -> String {
    if #available(iOS 17.0, *) {
        switch status {
        case .fullAccess:
            return L10n.tr("allowed")
        case .writeOnly:
            return L10n.tr("write only")
        case .notDetermined:
            return L10n.tr("Unauthorized")
        case .restricted:
            return L10n.tr("restricted")
        case .denied:
            return L10n.tr("Rejected")
        case .authorized:
            return L10n.tr("allowed")
        @unknown default:
            return L10n.tr("unknown")
        }
    } else {
        switch status {
        case .notDetermined:
            return L10n.tr("Unauthorized")
        case .restricted:
            return L10n.tr("restricted")
        case .denied:
            return L10n.tr("Rejected")
        case .authorized:
            return L10n.tr("allowed")
        @unknown default:
            return L10n.tr("unknown")
        }
    }
}

private func requestCalendarReadPermission(using eventStore: EKEventStore) async throws -> Bool {
    if #available(iOS 17.0, *) {
        return try await eventStore.requestFullAccessToEvents()
    }

    return try await withCheckedThrowingContinuation { continuation in
        eventStore.requestAccess(to: .event) { granted, error in
            if let error {
                continuation.resume(throwing: error)
                return
            }
            continuation.resume(returning: granted)
        }
    }
}

private final class SettingsSwitchFieldView: ConfigurableView {
    private var onToggle: ((Bool) -> Void)?
    private var isUpdatingProgrammatically = false

    private var switchView: UISwitch {
        contentView as! UISwitch
    }

    override init() {
        super.init()
        switchView.onTintColor = AlertControllerConfiguration.accentColor
        switchView.addTarget(self, action: #selector(switchValueChanged), for: .valueChanged)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override class func createContentView() -> UIView {
        UISwitch()
    }

    func configure(isOn: Bool, onToggle: @escaping (Bool) -> Void) {
        self.onToggle = onToggle
        isUpdatingProgrammatically = true
        switchView.setOn(isOn, animated: false)
        isUpdatingProgrammatically = false
    }

    @objc private func switchValueChanged() {
        guard !isUpdatingProgrammatically else { return }
        onToggle?(switchView.isOn)
    }
}

@MainActor
private final class PeriodTemplateManagementController: SettingsReloadableStackScrollController {
    private let repository: any TimetableRepositoryProtocol

    private var templates: [PeriodTemplate] = []
    private var loadError: Error?
    private var refreshError: Error?
    private var isLoading = true
    private var isRefreshing = false
    private var hasLoadedOnce = false

    init(repository: any TimetableRepositoryProtocol) {
        self.repository = repository
        super.init(nibName: nil, bundle: nil)
        title = L10n.tr("Section template")
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
                ConfigurableSectionFooterView().with(footer: L10n.tr("There is no section template yet, click + New in the upper right corner."))
            )
            stackView.addArrangedSubview(SeparatorView())
        } else {
            for template in templates {
                let action = ConfigurableActionView { [weak self] _ in
                    self?.presentEditor(templateId: template.id)
                }
                action.configure(icon: UIImage(systemName: template.isDefault ? "star.circle.fill" : "clock.badge"))
                action.configure(title: template.name)
                action.configure(description: template.isDefault ? L10n.tr("Default template · Click to edit") : L10n.tr("Click to edit section"))
                stackView.addArrangedSubviewWithMargin(action)
                stackView.addArrangedSubview(SeparatorView())
            }
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView().with(footer: statusFooterText)
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
            templates = try await repository.listPeriodTemplates()
            loadError = nil
            refreshError = nil
        } catch {
            if hasLoadedOnce && !templates.isEmpty {
                refreshError = error
            } else {
                templates = []
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
            return L10n.tr("Refreshing section template...")
        }
        if let refreshError {
            return "刷新失败：\(refreshError.localizedDescription)"
        }
        return L10n.tr("The default template will be used for the initial sections of the new class schedule; existing class schedules will not be automatically changed.")
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
        title = templateId == nil ? L10n.tr("Create new template") : L10n.tr("Edit template")
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
                ConfigurableSectionFooterView().with(footer: L10n.tr("Reading template…"))
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
            title: L10n.tr("Template name"),
            description: isDefaultTemplate ? L10n.tr("Current default template") : nil,
            value: templateName,
            placeholder: ""
        ) { [weak self] view in
            self?.presentNameEditor(from: view)
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: L10n.tr("section"))
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
                ConfigurableSectionFooterView().with(footer: L10n.tr("There is currently no section, please add a section first."))
            )
            stackView.addArrangedSubview(SeparatorView())
        }

        let addAction = ConfigurableActionView { [weak self] _ in
            self?.presentAddMenu()
        }
        addAction.configure(icon: UIImage(systemName: "plus.circle"))
        addAction.configure(title: L10n.tr("Add section"))
        stackView.addArrangedSubviewWithMargin(addAction)
        stackView.addArrangedSubview(SeparatorView())

        if templateId != nil {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView().with(header: L10n.tr("manage"))
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            if !isDefaultTemplate {
                let defaultAction = ConfigurableActionView { [weak self] _ in
                    self?.setAsDefaultTemplate()
                }
                defaultAction.configure(icon: UIImage(systemName: "star"))
                defaultAction.configure(title: L10n.tr("Set as default template"))
                defaultAction.configure(description: L10n.tr("This set of sections is used by default when creating a new class schedule."))
                stackView.addArrangedSubviewWithMargin(defaultAction)
                stackView.addArrangedSubview(SeparatorView())
            }

            let deleteAction = ConfigurableActionView { [weak self] _ in
                self?.promptDeleteTemplate()
            }
            deleteAction.configure(icon: UIImage(systemName: "trash"))
            deleteAction.configure(title: L10n.tr("Delete template"))
            deleteAction.configure(description: L10n.tr("Delete this section template."))
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
                    throw AppError.validation(L10n.tr("Template does not exist."))
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
            title: L10n.tr("Edit template name"),
            message: L10n.tr("Please enter a template name."),
            placeholder: "",
            text: templateName,
            cancelButtonText: L10n.tr("Cancel"),
            doneButtonText: L10n.tr("Sure")
        ) { [weak self] output in
            self?.templateName = output
            self?.rebuildContent()
        }
        view.hostingViewController?.present(input, animated: true)
    }

    private func presentAddMenu() {
        let alert = AlertViewController(title: L10n.tr("Add section"), message: L10n.tr("Please select how to add.")) { [weak self] context in
            context.addAction(title: L10n.tr("Cancel")) {
                context.dispose()
            }
            context.addAction(title: L10n.tr("Add single section"), attribute: .accent) {
                context.dispose {
                    self?.addSinglePeriod()
                }
            }
            context.addAction(title: L10n.tr("Add in batches")) {
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
            title: L10n.tr("Delete template"),
            message: L10n.tr("Are you sure you want to delete this section template?")
        ) { [weak self] context in
            context.addAction(title: L10n.tr("Cancel")) {
                context.dispose()
            }
            context.addAction(title: L10n.tr("delete"), attribute: .accent) {
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
        presentMessage(title: L10n.tr("Operation failed"), message: error.localizedDescription)
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
        cancelButtonText: String = L10n.tr("Cancel"),
        doneButtonText: String = L10n.tr("Sure"),
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
        title = L10n.tr("Add sections in batches")
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
            title: L10n.tr("Duration of each section"),
            description: nil,
            value: "\(durationMinutes) 分钟",
            placeholder: ""
        ) { [weak self] view in
            self?.presentDurationPicker(from: view)
        }

        appendEditableField(
            icon: "pause.circle",
            title: L10n.tr("break time"),
            description: nil,
            value: "\(breakMinutes) 分钟",
            placeholder: ""
        ) { [weak self] view in
            self?.presentBreakPicker(from: view)
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: L10n.tr("morning"))
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        appendEditableField(
            icon: "sun.max",
            title: L10n.tr("start time"),
            description: nil,
            value: morningStartTime.isEmpty ? L10n.tr("not set") : morningStartTime,
            placeholder: ""
        ) { [weak self] view in
            self?.presentTimePicker(from: view, title: L10n.tr("Start time of the first session in the morning"), currentValue: self?.morningStartTime ?? "") { newValue in
                self?.morningStartTime = newValue
                view.configure(value: newValue)
            }
        }

        appendEditableField(
            icon: "number",
            title: L10n.tr("several classes"),
            description: nil,
            value: "\(morningCount) 节",
            placeholder: ""
        ) { [weak self] view in
            self?.presentCountPicker(from: view, title: L10n.tr("How many classes are there in the morning?"), currentCount: self?.morningCount ?? 0) { count in
                self?.morningCount = count
                view.configure(value: "\(count) 节")
            }
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: L10n.tr("afternoon"))
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        appendEditableField(
            icon: "sunset",
            title: L10n.tr("First quarter time"),
            description: nil,
            value: afternoonStartTime.isEmpty ? L10n.tr("not set") : afternoonStartTime,
            placeholder: ""
        ) { [weak self] view in
            self?.presentTimePicker(from: view, title: L10n.tr("Starting time of the first period in the afternoon"), currentValue: self?.afternoonStartTime ?? "") { newValue in
                self?.afternoonStartTime = newValue
                view.configure(value: newValue)
            }
        }

        appendEditableField(
            icon: "number",
            title: L10n.tr("several classes"),
            description: nil,
            value: "\(afternoonCount) 节",
            placeholder: ""
        ) { [weak self] view in
            self?.presentCountPicker(from: view, title: L10n.tr("Afternoon classes"), currentCount: self?.afternoonCount ?? 0) { count in
                self?.afternoonCount = count
                view.configure(value: "\(count) 节")
            }
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView().with(footer: L10n.tr("Adjacent sections will be generated according to the set duration and inter-class time."))
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
            presentMessage(title: L10n.tr("Invalid parameter"), message: error.localizedDescription)
        }
    }

    private func buildPeriods() throws -> [TimetablePeriodInput] {
        if morningCount == 0 && afternoonCount == 0 {
            throw AppError.validation(L10n.tr("Fill out at least one session in the morning and afternoon."))
        }

        var generated: [TimetablePeriodInput] = []
        if morningCount > 0 {
            guard let start = parseTimeInput(morningStartTime) else {
                throw AppError.validation(L10n.tr("Please set a start time for the first period in the morning."))
            }
            generated.append(contentsOf: makePeriods(start: start, count: morningCount, startIndex: generated.count + 1))
        }

        if afternoonCount > 0 {
            guard let start = parseTimeInput(afternoonStartTime) else {
                throw AppError.validation(L10n.tr("Please set a start time for the first session in the afternoon."))
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
            title: L10n.tr("Duration of each section"),
            message: L10n.tr("Choose the length of each lesson."),
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
            title: L10n.tr("break time"),
            message: L10n.tr("Choose a break between each session."),
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
            message: L10n.tr("Select the number of sections."),
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
            context.addAction(title: L10n.tr("Sure"), attribute: .accent) {
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
            title: L10n.tr("start time"),
            description: nil,
            value: period.startTime,
            placeholder: ""
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
            placeholder: ""
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

        let deleteAction = ConfigurableActionView { [weak self] _ in
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
