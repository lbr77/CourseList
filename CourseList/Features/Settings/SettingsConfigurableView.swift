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
        let controller = ConfigurableViewController(manifest: makeManifest())
        controller.title = "设置"
        controller.navigationItem.title = "设置"
        controller.navigationItem.largeTitleDisplayMode = .always

        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.navigationBar.prefersLargeTitles = true
        return navigationController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    private func makeManifest() -> ConfigurableManifest {
        ConfigurableManifest(
            title: "设置",
            list: [
                ConfigurableObject(
                    icon: "calendar",
                    title: "课表管理",
                    explain: currentTimetableSummary,
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

    private var currentTimetableSummary: String {
        guard let currentTimetable else {
            return "今天没有生效中的课表"
        }
        return "\(currentTimetable.name) · 自动匹配"
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
                LabeledContent("数据库", value: bootstrapError == nil ? "正常" : "内存模式")
                if let currentTimetable {
                    LabeledContent("当前学期课表", value: currentTimetable.name)
                } else {
                    LabeledContent("当前学期课表", value: "无")
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
