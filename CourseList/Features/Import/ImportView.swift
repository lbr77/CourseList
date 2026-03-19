import SwiftUI

struct ImportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ImportViewModel
    @State private var addressInput = ""
    let onImported: () -> Void
    let showsNavigationChrome: Bool

    init(viewModel: ImportViewModel, onImported: @escaping () -> Void, showsNavigationChrome: Bool = true) {
        self.viewModel = viewModel
        self.onImported = onImported
        self.showsNavigationChrome = showsNavigationChrome
    }

    var body: some View {
        VStack(spacing: 0) {
            addressBar
            ImportWebView(proxy: viewModel.proxy, initialURL: viewModel.school.defaultImportURL) { url, title, canGoBack in
                viewModel.navigationChanged(url: url, title: title, canGoBack: canGoBack)
                addressInput = url
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            statusPanel
        }
        .if(showsNavigationChrome) { view in
            view
                .navigationTitle(viewModel.school.label)
                .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            addressInput = viewModel.sourceURL
        }
    }

    private var addressBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    viewModel.proxy.goBack()
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .disabled(!viewModel.canGoBack)

                TextField("输入地址", text: $addressInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        viewModel.proxy.load(addressInput)
                    }

                Button {
                    viewModel.proxy.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.pageTitle.isEmpty ? "网页登录" : viewModel.pageTitle)
                        .font(.subheadline.bold())
                    Text(viewModel.sourceURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("识别页面") {
                    Task { await viewModel.inspectAndCapture() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder
    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch viewModel.phase {
            case .browsing:
                Text("请先登录学校系统并进入课表页面，然后点击“识别页面”。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .capturing:
                HStack {
                    ProgressView()
                    Text("正在识别并抓取当前页面…")
                }
            case .unsupported:
                Text(viewModel.unsupportedReason ?? "当前页面不支持导入。")
                    .foregroundStyle(.orange)
            case .preview, .importing, .done:
                previewPanel
            case .error:
                Text(viewModel.errorMessage ?? "导入失败。")
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var previewPanel: some View {
        if let draft = viewModel.draft {
            VStack(alignment: .leading, spacing: 8) {
                Text("导入预览")
                    .font(.headline)
                Text("课表：\(draft.name)")
                Text("学期：\(draft.termName)")
                Text("开学日期：\(draft.startDate) · 周数：\(draft.weeksCount)")
                Text("节次：\(draft.periods.count) · 课程：\(draft.courses.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !viewModel.draftErrors.isEmpty {
                    ForEach(viewModel.draftErrors, id: \.self) { error in
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                ForEach(draft.warnings) { warning in
                    Text(warning.message)
                        .font(.caption)
                        .foregroundStyle(warning.severity == .warning ? .orange : .secondary)
                }
                HStack {
                    Button("关闭") { dismiss() }
                        .buttonStyle(.bordered)
                    Button(viewModel.phase == .importing ? "导入中…" : "确认导入") {
                        Task {
                            if await viewModel.importDraft() {
                                onImported()
                            }
                        }
                    }
                    .disabled(!viewModel.draftErrors.isEmpty || viewModel.phase == .importing)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
