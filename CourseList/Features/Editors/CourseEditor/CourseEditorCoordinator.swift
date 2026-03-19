import ConfigurableKit
import SwiftUI
import UIKit

@MainActor
final class CourseEditorCoordinator: NSObject {
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
    private let storage = MemoryKeyValueStorage()
    private var state: State
    private let onFinished: () -> Void
    private weak var rootController: ConfigurableViewController?

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
            meetings: [.init(weekday: 1, startWeek: 1, endWeek: 16, startPeriod: 1, endPeriod: 1, location: nil, weekType: .all)],
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
            meetings: [.init(weekday: 1, startWeek: 1, endWeek: 16, startPeriod: 1, endPeriod: min(2, max(1, loadedPeriods.count)), location: nil, weekType: .all)],
            periods: loadedPeriods
        )
    }

    private init(repository: TimetableRepositoryProtocol, state: State, onFinished: @escaping () -> Void) {
        self.repository = repository
        self.state = state
        self.onFinished = onFinished
        super.init()
        synchronizeStorage()
    }

    private func presentLoadedController(with state: State, in navigationController: UINavigationController) {
        self.state = state
        synchronizeStorage()

        let controller = ConfigurableViewController(manifest: makeManifest())
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(CourseEditorCoordinator.cancelTapped))
        controller.navigationItem.rightBarButtonItems = [UIBarButtonItem(title: "保存", style: .done, target: self, action: #selector(CourseEditorCoordinator.saveTapped))]
        if state.courseId != nil {
            controller.navigationItem.rightBarButtonItems?.append(UIBarButtonItem(title: "删除", style: .plain, target: self, action: #selector(CourseEditorCoordinator.deleteTapped)))
        }

        rootController = controller
        navigationController.setViewControllers([controller], animated: false)
    }

    private func synchronizeStorage() {
        ConfigurableKit.set(value: state.name, forKey: "course.name", storage: storage)
        ConfigurableKit.set(value: state.teacher, forKey: "course.teacher", storage: storage)
        ConfigurableKit.set(value: state.location, forKey: "course.location", storage: storage)
        ConfigurableKit.set(value: state.color, forKey: "course.color", storage: storage)
        ConfigurableKit.set(value: state.note, forKey: "course.note", storage: storage)
    }

    private func makeManifest() -> ConfigurableManifest {
        ConfigurableManifest(
            title: state.courseId == nil ? "新建课程" : "编辑课程",
            list: [
                ConfigurableObject(icon: "book", title: "课程名称", key: "course.name", defaultValue: state.name, annotation: TextInputAnnotation(placeholder: "例如：高等数学"), storage: storage),
                ConfigurableObject(icon: "person", title: "教师", key: "course.teacher", defaultValue: state.teacher, annotation: TextInputAnnotation(placeholder: "任课教师"), storage: storage),
                ConfigurableObject(icon: "mappin.and.ellipse", title: "地点", key: "course.location", defaultValue: state.location, annotation: TextInputAnnotation(placeholder: "上课地点"), storage: storage),
                ConfigurableObject(icon: "paintpalette", title: "颜色", explain: "可留空，例如 #5B8FF9", key: "course.color", defaultValue: state.color, annotation: TextInputAnnotation(placeholder: "#5B8FF9"), storage: storage),
                ConfigurableObject(icon: "note.text", title: "备注", key: "course.note", defaultValue: state.note, annotation: TextInputAnnotation(placeholder: "可选备注"), storage: storage),
                ConfigurableObject(icon: "clock", title: "上课时间", explain: "共 \(state.meetings.count) 条", ephemeralAnnotation: PageAnnotation(viewController: makeMeetingsController)),
            ],
            footer: "保存时会进行时间冲突检测。"
        )
    }

    private func makeMeetingsController() -> UIViewController {
        UIHostingController(rootView: MeetingsListEditorView(meetings: Binding(get: {
            self.state.meetings
        }, set: {
            self.state.meetings = $0
        }), periods: state.periods))
    }

    @MainActor
    func performDeleteAction(controller: UIViewController) async {
        await deleteCourse()
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
                state.name = ConfigurableKit.value(forKey: "course.name", defaultValue: state.name, storage: storage)
                state.teacher = ConfigurableKit.value(forKey: "course.teacher", defaultValue: state.teacher, storage: storage)
                state.location = ConfigurableKit.value(forKey: "course.location", defaultValue: state.location, storage: storage)
                state.color = ConfigurableKit.value(forKey: "course.color", defaultValue: state.color, storage: storage)
                state.note = ConfigurableKit.value(forKey: "course.note", defaultValue: state.note, storage: storage)

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
}

private struct MeetingsListEditorView: View {
    @Binding var meetings: [CourseMeetingInput]
    let periods: [TimetablePeriod]

    var body: some View {
        Form {
            Section("上课时间") {
                ForEach(Array(meetings.enumerated()), id: \.offset) { index, _ in
                    MeetingRowEditor(meeting: Binding(get: {
                        meetings[index]
                    }, set: {
                        meetings[index] = $0
                    }), periods: periods, onDelete: {
                        meetings.remove(at: index)
                    })
                }
                Button("添加时间") {
                    meetings.append(.init(weekday: 1, startWeek: 1, endWeek: 16, startPeriod: 1, endPeriod: min(2, max(1, periods.count)), location: nil, weekType: .all))
                }
            }
        }
        .navigationTitle("上课时间")
    }
}

private struct MeetingRowEditor: View {
    @Binding var meeting: CourseMeetingInput
    let periods: [TimetablePeriod]
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("星期", selection: $meeting.weekday) {
                ForEach(1 ..< 8) { day in
                    Text("周\(day)").tag(day)
                }
            }
            .pickerStyle(.segmented)
            HStack {
                TextField("起始周", value: $meeting.startWeek, format: .number)
                TextField("结束周", value: $meeting.endWeek, format: .number)
            }
            HStack {
                TextField("起始节", value: $meeting.startPeriod, format: .number)
                TextField("结束节", value: $meeting.endPeriod, format: .number)
            }
            TextField("地点", text: Binding(get: {
                meeting.location ?? ""
            }, set: {
                meeting.location = normalizeOptionalText($0)
            }))
            Picker("单双周", selection: $meeting.weekType) {
                ForEach(WeekType.allCases, id: \.self) { type in
                    Text(type.title).tag(type)
                }
            }
            Text("时间：\(buildPeriodTimeLabel(periods, startPeriod: meeting.startPeriod, endPeriod: meeting.endPeriod))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("删除本条", role: .destructive, action: onDelete)
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
