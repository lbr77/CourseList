import SwiftUI

struct SettingsView: View {
    let activeTimetable: Timetable?
    let bootstrapError: String?
    let onImportTap: () -> Void
    let onNewTimetableTap: () -> Void
    let onManageTimetableTap: () -> Void

    var body: some View {
        List {
            Section("当前课表") {
                if let activeTimetable {
                    LabeledContent("名称", value: activeTimetable.name)
                    LabeledContent("开学日期", value: activeTimetable.startDate)
                    LabeledContent("总周数", value: "\(activeTimetable.weeksCount)")
                    Button("编辑当前课表", action: onManageTimetableTap)
                } else {
                    Text("当前还没有激活课表")
                        .foregroundStyle(.secondary)
                    Button("新建课表", action: onNewTimetableTap)
                }
            }

            Section("数据与导入") {
                Button("学校导入", action: onImportTap)
                Button("新建课表", action: onNewTimetableTap)
            }

            Section("说明") {
                Text("页面 1 用来展示课表日历，页面 2 用来放设置与管理入口。")
                    .foregroundStyle(.secondary)
                if let bootstrapError {
                    Text(bootstrapError)
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("管理")
    }
}
