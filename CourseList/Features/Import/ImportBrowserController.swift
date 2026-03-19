import Combine
import ConfigurableKit
import UIKit
import WebKit

@MainActor
final class ImportBrowserController: UIViewController, WKNavigationDelegate {
    private let viewModel: ImportViewModel
    private let onImported: () -> Void
    private var cancellables: Set<AnyCancellable> = []

    private let headerView = UIView()
    private let closeButton = BrowserHeaderButton(systemName: "xmark", tintColor: .systemRed)
    private let titleBadgeView = UIView()
    private let titleLabel = UILabel()
    private let confirmButton = BrowserHeaderButton(systemName: "checkmark", tintColor: .systemGreen)

    private let controlsContainer = UIView()
    private let controlsStackView = UIStackView()

    private let webContainerView = UIView()
    private let webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        return WKWebView(frame: .zero, configuration: configuration)
    }()

    private let statusScrollView = UIScrollView()
    private let statusContentView = UIView()
    private let statusStackView = UIStackView()

    init(viewModel: ImportViewModel, onImported: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onImported = onImported
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupLayout()
        setupHeader()
        setupWebView()
        setupBindings()
        rebuildControls()
        rebuildStatus()
        updateConfirmButtonState()
    }

    private func setupLayout() {
        [headerView, controlsContainer, webContainerView, statusScrollView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        headerView.setContentHuggingPriority(.required, for: .vertical)
        controlsContainer.setContentHuggingPriority(.required, for: .vertical)
        statusScrollView.setContentHuggingPriority(.required, for: .vertical)
        statusScrollView.setContentCompressionResistancePriority(.required, for: .vertical)

        controlsStackView.axis = .vertical
        controlsStackView.spacing = 0
        controlsStackView.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(controlsStackView)

        webContainerView.backgroundColor = .secondarySystemBackground
        webContainerView.layer.cornerRadius = 20
        webContainerView.layer.cornerCurve = .continuous
        webContainerView.layer.borderWidth = 1
        webContainerView.layer.borderColor = UIColor.separator.cgColor
        webContainerView.clipsToBounds = true
        webContainerView.translatesAutoresizingMaskIntoConstraints = false
        webContainerView.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false

        statusScrollView.showsVerticalScrollIndicator = false
        statusScrollView.alwaysBounceVertical = false
        statusContentView.translatesAutoresizingMaskIntoConstraints = false
        statusStackView.axis = .vertical
        statusStackView.spacing = 0
        statusStackView.translatesAutoresizingMaskIntoConstraints = false
        statusScrollView.addSubview(statusContentView)
        statusContentView.addSubview(statusStackView)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            headerView.heightAnchor.constraint(equalToConstant: 40),

            controlsContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 8),
            controlsContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            controlsStackView.topAnchor.constraint(equalTo: controlsContainer.topAnchor),
            controlsStackView.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor),
            controlsStackView.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor),
            controlsStackView.bottomAnchor.constraint(equalTo: controlsContainer.bottomAnchor),

            webContainerView.topAnchor.constraint(equalTo: controlsContainer.bottomAnchor, constant: 8),
            webContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            webContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            webContainerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 300),

            webView.topAnchor.constraint(equalTo: webContainerView.topAnchor),
            webView.leadingAnchor.constraint(equalTo: webContainerView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: webContainerView.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: webContainerView.bottomAnchor),

            statusScrollView.topAnchor.constraint(equalTo: webContainerView.bottomAnchor, constant: 8),
            statusScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusScrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            statusScrollView.heightAnchor.constraint(lessThanOrEqualToConstant: 220),

            statusContentView.topAnchor.constraint(equalTo: statusScrollView.contentLayoutGuide.topAnchor),
            statusContentView.leadingAnchor.constraint(equalTo: statusScrollView.contentLayoutGuide.leadingAnchor),
            statusContentView.trailingAnchor.constraint(equalTo: statusScrollView.contentLayoutGuide.trailingAnchor),
            statusContentView.bottomAnchor.constraint(equalTo: statusScrollView.contentLayoutGuide.bottomAnchor),
            statusContentView.widthAnchor.constraint(equalTo: statusScrollView.frameLayoutGuide.widthAnchor),

            statusStackView.topAnchor.constraint(equalTo: statusContentView.topAnchor),
            statusStackView.leadingAnchor.constraint(equalTo: statusContentView.leadingAnchor),
            statusStackView.trailingAnchor.constraint(equalTo: statusContentView.trailingAnchor),
            statusStackView.bottomAnchor.constraint(equalTo: statusContentView.bottomAnchor),
        ])
    }

    private func setupHeader() {
        [closeButton, titleBadgeView, confirmButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview($0)
        }

        titleBadgeView.backgroundColor = .secondarySystemBackground
        titleBadgeView.layer.cornerRadius = 14
        titleBadgeView.layer.cornerCurve = .continuous
        titleBadgeView.layer.borderWidth = 1
        titleBadgeView.layer.borderColor = UIColor.separator.cgColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = viewModel.school.label
        titleLabel.textAlignment = .center
        titleLabel.font = .systemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .headline).pointSize,
            weight: .semibold
        )
        titleLabel.textColor = .label
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.75
        titleBadgeView.addSubview(titleLabel)

        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        confirmButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            confirmButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
            confirmButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            confirmButton.widthAnchor.constraint(equalToConstant: 36),
            confirmButton.heightAnchor.constraint(equalToConstant: 36),

            titleBadgeView.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 16),
            titleBadgeView.trailingAnchor.constraint(equalTo: confirmButton.leadingAnchor, constant: -16),
            titleBadgeView.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            titleBadgeView.heightAnchor.constraint(equalToConstant: 40),

            titleLabel.leadingAnchor.constraint(equalTo: titleBadgeView.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: titleBadgeView.trailingAnchor, constant: -14),
            titleLabel.centerYAnchor.constraint(equalTo: titleBadgeView.centerYAnchor),
        ])
    }

    private func setupWebView() {
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        viewModel.proxy.webView = webView
        if let url = URL(string: viewModel.school.defaultImportURL) {
            webView.load(URLRequest(url: url))
        }
    }

    private func setupBindings() {
        viewModel.$sourceURL
            .combineLatest(viewModel.$pageTitle, viewModel.$canGoBack)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                self?.rebuildControls()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4(viewModel.$phase, viewModel.$draft, viewModel.$errorMessage, viewModel.$unsupportedReason)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _, _ in
                self?.rebuildStatus()
                self?.updateConfirmButtonState()
            }
            .store(in: &cancellables)

        viewModel.$draftErrors
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildStatus()
                self?.updateConfirmButtonState()
            }
            .store(in: &cancellables)
    }

    private func rebuildControls() {
        clearArrangedSubviews(in: controlsStackView)

        controlsStackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: "浏览器")
        ) { $0.bottom /= 2 }
        controlsStackView.addArrangedSubview(SeparatorView())

        let pageTitleView = ConfigurableInfoView()
        pageTitleView.configure(icon: UIImage(systemName: "globe"))
        pageTitleView.configure(title: "页面标题")
        pageTitleView.configure(description: "当前浏览页面")
        pageTitleView.configure(value: viewModel.pageTitle.isEmpty ? "网页登录" : viewModel.pageTitle)
        controlsStackView.addArrangedSubviewWithMargin(pageTitleView)
        controlsStackView.addArrangedSubview(SeparatorView())

        let addressView = ConfigurableInfoView().setTapBlock { [weak self] view in
            guard let self else { return }
            let input = AlertInputViewController(
                title: "打开地址",
                message: "输入要访问的网址。",
                placeholder: "https://",
                text: self.viewModel.sourceURL,
                cancelButtonText: "取消",
                doneButtonText: "打开"
            ) { [weak self] output in
                guard let self else { return }
                self.viewModel.proxy.load(output)
                view.configure(value: output)
            }
            self.present(input, animated: true)
        }
        addressView.configure(icon: UIImage(systemName: "link"))
        addressView.configure(title: "当前地址")
        addressView.configure(description: "点击可输入新地址")
        addressView.configure(value: viewModel.sourceURL)
        controlsStackView.addArrangedSubviewWithMargin(addressView)
        controlsStackView.addArrangedSubview(SeparatorView())

        let backAction = ConfigurableActionView { [weak self] _ in
            self?.viewModel.proxy.goBack()
        }
        backAction.configure(icon: UIImage(systemName: "chevron.backward"))
        backAction.configure(title: "返回上一页")
        backAction.configure(description: viewModel.canGoBack ? "返回浏览器上一页。" : "当前没有可返回的页面。")
        backAction.isUserInteractionEnabled = viewModel.canGoBack
        backAction.alpha = viewModel.canGoBack ? 1 : 0.4
        controlsStackView.addArrangedSubviewWithMargin(backAction)
        controlsStackView.addArrangedSubview(SeparatorView())

        let reloadAction = ConfigurableActionView { [weak self] _ in
            self?.viewModel.proxy.reload()
        }
        reloadAction.configure(icon: UIImage(systemName: "arrow.clockwise"))
        reloadAction.configure(title: "刷新页面")
        reloadAction.configure(description: "重新加载当前网页。")
        controlsStackView.addArrangedSubviewWithMargin(reloadAction)
        controlsStackView.addArrangedSubview(SeparatorView())

        let captureAction = ConfigurableActionView { [weak self] _ in
            guard let self else { return }
            Task { await self.viewModel.inspectAndCapture() }
        }
        captureAction.configure(icon: UIImage(systemName: "viewfinder"))
        captureAction.configure(title: viewModel.phase == .preview ? "重新识别" : "识别页面")
        captureAction.configure(description: "登录后进入课表页面，再执行识别。")
        captureAction.isUserInteractionEnabled = !isBusy
        captureAction.alpha = isBusy ? 0.4 : 1
        controlsStackView.addArrangedSubviewWithMargin(captureAction)
        controlsStackView.addArrangedSubview(SeparatorView())
    }

    private func rebuildStatus() {
        clearArrangedSubviews(in: statusStackView)

        let headerTitle = viewModel.phase == .preview || viewModel.phase == .importing || viewModel.phase == .done ? "导入预览" : "状态"
        statusStackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: headerTitle)
        ) { $0.bottom /= 2 }
        statusStackView.addArrangedSubview(SeparatorView())

        switch viewModel.phase {
        case .browsing:
            appendFooter("请先登录学校系统并进入课表页面，然后点击右上角的确认按钮或“识别页面”。")
        case .capturing:
            appendFooter("正在识别并抓取当前页面…")
        case .unsupported:
            appendFooter(viewModel.unsupportedReason ?? "当前页面不支持导入。", color: .systemOrange)
        case .error:
            appendFooter(viewModel.errorMessage ?? "导入失败。", color: .systemRed)
        case .preview:
            appendPreview(draft: viewModel.draft, isImporting: false)
        case .importing:
            appendPreview(draft: viewModel.draft, isImporting: true)
        case .done:
            appendPreview(draft: viewModel.draft, isImporting: false)
            appendFooter("导入完成。")
        }

        statusStackView.addArrangedSubviewWithMargin(UIView())
    }

    private func appendPreview(draft: ImportedTimetableDraft?, isImporting: Bool) {
        guard let draft else {
            appendFooter("尚未生成导入预览。")
            return
        }

        let timetableView = ConfigurableInfoView()
        timetableView.configure(icon: UIImage(systemName: "calendar"))
        timetableView.configure(title: "课表")
        timetableView.configure(description: "导入后的课表名称")
        timetableView.configure(value: draft.name)
        statusStackView.addArrangedSubviewWithMargin(timetableView)
        statusStackView.addArrangedSubview(SeparatorView())

        let statsView = ConfigurableInfoView()
        statsView.configure(icon: UIImage(systemName: "square.stack.3d.up"))
        statsView.configure(title: "导入统计")
        statsView.configure(description: "开学日期：\(draft.startDate) · 周数：\(draft.weeksCount)")
        statsView.configure(value: "节次 \(draft.periods.count) · 课程 \(draft.courses.count)")
        statusStackView.addArrangedSubviewWithMargin(statsView)
        statusStackView.addArrangedSubview(SeparatorView())

        if isImporting {
            appendFooter("正在导入课表…")
        }

        for error in viewModel.draftErrors {
            appendFooter(error, color: .systemRed)
        }

        for warning in draft.warnings {
            appendFooter(
                warning.message,
                color: warning.severity == .warning ? .systemOrange : .secondaryLabel
            )
        }

        if viewModel.draftErrors.isEmpty {
            appendFooter("确认后将导入到本地课表。")
        }
    }

    private func appendFooter(_ text: String, color: UIColor = .secondaryLabel) {
        let footer = ConfigurableSectionFooterView().with(footer: text)
        footer.titleLabel.textColor = color
        statusStackView.addArrangedSubviewWithMargin(footer) { $0.top /= 2 }
        statusStackView.addArrangedSubview(SeparatorView())
    }

    private func updateConfirmButtonState() {
        let enabled: Bool
        switch viewModel.phase {
        case .preview:
            enabled = viewModel.draftErrors.isEmpty
        case .capturing, .importing:
            enabled = false
        default:
            enabled = true
        }
        confirmButton.isEnabled = enabled
        confirmButton.alpha = enabled ? 1 : 0.4
    }

    private var isBusy: Bool {
        switch viewModel.phase {
        case .capturing, .importing:
            return true
        default:
            return false
        }
    }

    private func clearArrangedSubviews(in stackView: UIStackView) {
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    @objc private func closeTapped() {
        if let navigationController, navigationController.viewControllers.count > 1 {
            navigationController.popViewController(animated: true)
        } else {
            navigationController?.dismiss(animated: true)
        }
    }

    @objc private func primaryTapped() {
        switch viewModel.phase {
        case .preview:
            guard viewModel.draftErrors.isEmpty else { return }
            Task {
                if await viewModel.importDraft() {
                    onImported()
                }
            }
        case .capturing, .importing:
            return
        default:
            Task { await viewModel.inspectAndCapture() }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        viewModel.navigationChanged(
            url: webView.url?.absoluteString ?? "",
            title: webView.title,
            canGoBack: webView.canGoBack
        )
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        viewModel.navigationChanged(
            url: webView.url?.absoluteString ?? "",
            title: webView.title,
            canGoBack: webView.canGoBack
        )
    }
}

private final class BrowserHeaderButton: UIControl {
    private let imageView = UIImageView()
    private let symbolName: String
    private let baseTintColor: UIColor

    init(systemName: String, tintColor: UIColor) {
        symbolName = systemName
        baseTintColor = tintColor
        super.init(frame: .zero)

        backgroundColor = .secondarySystemBackground
        layer.borderWidth = 1.5
        layer.borderColor = tintColor.cgColor

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = tintColor
        imageView.image = UIImage(
            systemName: systemName,
            withConfiguration: UIImage.SymbolConfiguration(weight: .semibold)
        )
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isEnabled: Bool {
        didSet {
            imageView.tintColor = isEnabled ? baseTintColor : .systemGray3
            layer.borderColor = (isEnabled ? baseTintColor : UIColor.systemGray3).cgColor
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }
}
