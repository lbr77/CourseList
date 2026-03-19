import SwiftUI

enum SheetRoute: Identifiable {
    case settings
    case schoolPicker
    case importFlow(TimetableImportSchool)
    case timetableEditor(String?)
    case coursePreview(courseId: String, selection: CoursePreviewSelectionContext)
    case courseEditor(courseId: String?, timetableId: String?)

    var id: String {
        switch self {
        case .settings: return "settings"
        case .schoolPicker: return "school-picker"
        case .importFlow(let school): return "import-\(school.id)"
        case .timetableEditor(let id): return "timetable-editor-\(id ?? "new")"
        case .coursePreview(let courseId, let selection):
            return "course-preview-\(courseId)-\(selection.week)-\(selection.weekday)-\(selection.startPeriod)-\(selection.endPeriod)"
        case .courseEditor(let courseId, let timetableId): return "course-editor-\(courseId ?? timetableId ?? "new")"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @StateObject private var viewModel = TimetableHomeViewModel()
    @State private var sheetRoute: SheetRoute?

    var body: some View {
        Group {
            if container.isBootstrapping {
                bootstrappingView
            } else if let repository = container.repository {
                NavigationStack {
                    TimetableHomeView(
                        viewModel: viewModel,
                        onSettingsTap: { sheetRoute = .settings },
                        onImportTap: { sheetRoute = .schoolPicker },
                        onNewTimetableTap: { sheetRoute = .timetableEditor(nil) },
                        onManageTimetableTap: { sheetRoute = .timetableEditor(viewModel.currentTimetable?.id) },
                        onNewCourseTap: { sheetRoute = .courseEditor(courseId: nil, timetableId: viewModel.currentTimetable?.id) },
                        onEditCourseTap: { course, selection in
                            sheetRoute = .coursePreview(courseId: course.id, selection: selection)
                        }
                    )
                }
            } else {
                startupErrorView
            }
        }
        .task(id: container.repository == nil ? "booting" : "ready") {
            guard let repository = container.repository else { return }
            viewModel.bind(repository: repository)
            await viewModel.reload()
        }
        .sheet(item: $sheetRoute, onDismiss: {
            NotificationCenter.default.post(name: .timetableRepositoryDidChange, object: nil)
            Task { await viewModel.reload() }
        }) { route in
            if let repository = container.repository {
                switch route {
                case .settings:
                    SettingsConfigurableView(
                        repository: repository,
                        currentTimetable: viewModel.currentTimetable,
                        bootstrapError: container.bootstrapError,
                        onImportTap: { sheetRoute = .schoolPicker },
                        onNewTimetableTap: { sheetRoute = .timetableEditor(nil) },
                        onEditTimetableTap: { timetableId in sheetRoute = .timetableEditor(timetableId) },
                        onRepositoryChanged: {
                            Task { await viewModel.reload() }
                        },
                        embedInNavigationController: true,
                        onCloseTap: { sheetRoute = nil }
                    )
                case .schoolPicker:
                    ConfigurableSheetContainer(
                        rootController: SchoolPickerController.makeController(
                            onSelect: { school in
                                sheetRoute = .importFlow(school)
                            },
                            onCreateTimetable: {
                                sheetRoute = .timetableEditor(nil)
                            },
                            onCancel: {
                                sheetRoute = nil
                            }
                        )
                    )
                    .ignoresSafeArea()
                case .importFlow(let school):
                    ConfigurableSheetContainer(
                        rootController: UINavigationController(
                            rootViewController: ImportBrowserController(
                                viewModel: ImportViewModel(repository: repository, school: school),
                                onImported: {
                                    sheetRoute = nil
                                }
                            )
                        )
                    )
                    .ignoresSafeArea()
                case .timetableEditor(let timetableId):
                    ConfigurableSheetContainer(
                        rootController: TimetableEditorCoordinator.makeController(
                            repository: repository,
                            timetableId: timetableId,
                            onFinished: { sheetRoute = nil }
                        )
                    )
                    .ignoresSafeArea()
                case .coursePreview(let courseId, let selection):
                    ConfigurableSheetContainer(
                        rootController: CoursePreviewCoordinator.makeController(
                            repository: repository,
                            courseId: courseId,
                            selection: selection,
                            onFinished: { sheetRoute = nil },
                            onEditCourse: { course in
                                sheetRoute = .courseEditor(courseId: course.id, timetableId: course.timetableId)
                            }
                        )
                    )
                    .ignoresSafeArea()
                case .courseEditor(let courseId, let timetableId):
                    ConfigurableSheetContainer(
                        rootController: CourseEditorCoordinator.makeController(
                            repository: repository,
                            courseId: courseId,
                            timetableId: timetableId,
                            onFinished: { sheetRoute = nil }
                        )
                    )
                    .ignoresSafeArea()
                }
            }
        }
    }

    private var startupErrorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("数据库初始化失败")
                .font(.headline)
            Text(container.bootstrapError ?? "应用无法继续启动，请检查存储权限或重启应用。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bootstrappingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("正在初始化数据库…")
                .font(.headline)
            if let error = container.bootstrapError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
