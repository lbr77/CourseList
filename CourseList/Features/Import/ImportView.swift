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

                TextField(L10n.tr("Enter address"), text: $addressInput)
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
                    Text(viewModel.pageTitle.isEmpty ? L10n.tr("Web login") : viewModel.pageTitle)
                        .font(.subheadline.bold())
                    Text(viewModel.sourceURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(L10n.tr("Identify page")) {
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
                Text(L10n.tr("Please log in to the school system first and enter the class schedule page, then click \"Identify Page\"."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .capturing:
                HStack {
                    ProgressView()
                    Text(L10n.tr("Recognizing and crawling the current page..."))
                }
            case .unsupported:
                Text(viewModel.unsupportedReason ?? L10n.tr("The current page does not support import."))
                    .foregroundStyle(.orange)
            case .preview, .importing, .done:
                previewPanel
            case .error:
                Text(viewModel.errorMessage ?? L10n.tr("Import failed."))
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
                Text(L10n.tr("Import preview"))
                    .font(.headline)
                Text(L10n.tr("Class schedule: %@", draft.name))
                Text(L10n.tr("Start date: %@ · Week number: %d", draft.startDate, draft.weeksCount))
                Text(L10n.tr("Section: %d · Course: %d", draft.periods.count, draft.courses.count))
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
                    Button(L10n.tr("closure")) { dismiss() }
                        .buttonStyle(.bordered)
                    Button(viewModel.phase == .importing ? L10n.tr("Importing…") : L10n.tr("Confirm import")) {
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
