import Combine
import ConfigurableKit
import UIKit
import WebKit

@MainActor
final class ImportBrowserController: UIViewController, WKNavigationDelegate, WKUIDelegate, UITextFieldDelegate {
    private let viewModel: ImportViewModel
    private let onImported: () -> Void
    private var cancellables: Set<AnyCancellable> = []

    private lazy var closeItem = UIBarButtonItem(
        barButtonSystemItem: .close,
        target: self,
        action: #selector(closeTapped)
    )
    private lazy var primaryItem = UIBarButtonItem(
        title: L10n.tr("identify"),
        style: .done,
        target: self,
        action: #selector(primaryTapped)
    )
    private lazy var backItem = UIBarButtonItem(
        image: UIImage(systemName: "chevron.backward"),
        style: .plain,
        target: self,
        action: #selector(backTapped)
    )
    private lazy var reloadItem = UIBarButtonItem(
        barButtonSystemItem: .refresh,
        target: self,
        action: #selector(reloadTapped)
    )
    private let addressHostView = UIView()
    private let addressDisplayButton = UIButton(type: .system)
    private let addressDisplayLabel = UILabel()
    private let addressInputField = UITextField()
    private lazy var addressItem = UIBarButtonItem(customView: addressHostView)
    private var addressWidthConstraint: NSLayoutConstraint?
    private var isAddressEditing = false

    private let webContainerView = UIView()
    private let webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
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
        setupNavigation()
        setupLayout()
        setupToolbar()
        setupWebView()
        setupBindings()
        rebuildStatus()
        updateNavigationState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if navigationController?.viewControllers.first != self {
            navigationController?.setToolbarHidden(true, animated: animated)
        }
    }

    private func setupLayout() {
        [webContainerView, statusScrollView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        statusScrollView.setContentHuggingPriority(.required, for: .vertical)
        statusScrollView.setContentCompressionResistancePriority(.required, for: .vertical)

        webContainerView.backgroundColor = .secondarySystemBackground
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
            webContainerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webContainerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 300),

            webView.topAnchor.constraint(equalTo: webContainerView.topAnchor),
            webView.leadingAnchor.constraint(equalTo: webContainerView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: webContainerView.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: webContainerView.bottomAnchor),

            statusScrollView.topAnchor.constraint(equalTo: webContainerView.bottomAnchor),
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

    private func setupNavigation() {
        navigationItem.title = viewModel.school.label
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = closeItem
        navigationItem.rightBarButtonItem = primaryItem
    }

    private func setupToolbar() {
        addressHostView.backgroundColor = .secondarySystemBackground
        addressHostView.layer.cornerRadius = 16
        addressHostView.layer.cornerCurve = .continuous
        addressHostView.layer.borderWidth = 1
        addressHostView.layer.borderColor = UIColor.separator.cgColor
        addressHostView.translatesAutoresizingMaskIntoConstraints = false
        addressWidthConstraint = addressHostView.widthAnchor.constraint(equalToConstant: 230)
        addressWidthConstraint?.isActive = true

        addressDisplayButton.translatesAutoresizingMaskIntoConstraints = false
        addressDisplayButton.addTarget(self, action: #selector(beginAddressEditing), for: .touchUpInside)
        addressHostView.addSubview(addressDisplayButton)

        addressDisplayLabel.translatesAutoresizingMaskIntoConstraints = false
        addressDisplayLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        addressDisplayLabel.textColor = .label
        addressDisplayLabel.textAlignment = .center
        addressDisplayLabel.lineBreakMode = .byTruncatingTail
        addressDisplayButton.addSubview(addressDisplayLabel)

        addressInputField.translatesAutoresizingMaskIntoConstraints = false
        addressInputField.placeholder = "https://"
        addressInputField.returnKeyType = .go
        addressInputField.clearButtonMode = .whileEditing
        addressInputField.keyboardType = .URL
        addressInputField.autocapitalizationType = .none
        addressInputField.autocorrectionType = .no
        addressInputField.delegate = self
        addressInputField.text = viewModel.sourceURL
        addressInputField.isHidden = true
        addressHostView.addSubview(addressInputField)

        NSLayoutConstraint.activate([
            addressHostView.heightAnchor.constraint(equalToConstant: 36),

            addressDisplayButton.topAnchor.constraint(equalTo: addressHostView.topAnchor),
            addressDisplayButton.leadingAnchor.constraint(equalTo: addressHostView.leadingAnchor),
            addressDisplayButton.trailingAnchor.constraint(equalTo: addressHostView.trailingAnchor),
            addressDisplayButton.bottomAnchor.constraint(equalTo: addressHostView.bottomAnchor),

            addressDisplayLabel.leadingAnchor.constraint(equalTo: addressDisplayButton.leadingAnchor, constant: 12),
            addressDisplayLabel.trailingAnchor.constraint(equalTo: addressDisplayButton.trailingAnchor, constant: -12),
            addressDisplayLabel.centerYAnchor.constraint(equalTo: addressDisplayButton.centerYAnchor),

            addressInputField.topAnchor.constraint(equalTo: addressHostView.topAnchor),
            addressInputField.leadingAnchor.constraint(equalTo: addressHostView.leadingAnchor, constant: 12),
            addressInputField.trailingAnchor.constraint(equalTo: addressHostView.trailingAnchor, constant: -12),
            addressInputField.bottomAnchor.constraint(equalTo: addressHostView.bottomAnchor),
        ])

        toolbarItems = [
            backItem,
            UIBarButtonItem.flexibleSpace(),
            addressItem,
            UIBarButtonItem.flexibleSpace(),
            reloadItem,
        ]
    }

    private func setupWebView() {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        installWindowOpenHijackScriptIfNeeded()
        viewModel.proxy.webView = webView
        if let url = URL(string: viewModel.school.defaultImportURL) {
            webView.load(URLRequest(url: url))
        }
    }

    private func installWindowOpenHijackScriptIfNeeded() {
        let source = """
        (() => {
          if (window.__courseListOpenHijackInstalled) return;
          window.__courseListOpenHijackInstalled = true;
          window.open = function(url) {
            if (typeof url === 'string' && url.trim().length > 0 && url !== 'about:blank') {
              try {
                window.location.href = new URL(url, window.location.href).toString();
              } catch (_) {
                window.location.href = url;
              }
            }
            return window;
          };
        })();
        """
        let script = WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        webView.configuration.userContentController.addUserScript(script)
    }

    private func setupBindings() {
        viewModel.$sourceURL
            .combineLatest(viewModel.$pageTitle, viewModel.$canGoBack)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                self?.updateNavigationState()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4(viewModel.$phase, viewModel.$draft, viewModel.$errorMessage, viewModel.$unsupportedReason)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _, _ in
                self?.rebuildStatus()
                self?.updateNavigationState()
            }
            .store(in: &cancellables)

        viewModel.$draftErrors
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildStatus()
                self?.updateNavigationState()
            }
            .store(in: &cancellables)
    }

    private func rebuildStatus() {
        clearArrangedSubviews(in: statusStackView)

        let headerTitle = viewModel.phase == .preview || viewModel.phase == .importing || viewModel.phase == .done ? L10n.tr("Import preview") : L10n.tr("state")
        statusStackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: headerTitle)
        ) { $0.bottom /= 2 }
        statusStackView.addArrangedSubview(SeparatorView())

        switch viewModel.phase {
        case .browsing:
            appendFooter(L10n.tr("Please log in to the school system first and enter the class schedule page, then click \"Identify\" in the upper right corner."))
        case .capturing:
            appendFooter(L10n.tr("Recognizing and crawling the current page..."))
        case .unsupported:
            appendFooter(viewModel.unsupportedReason ?? L10n.tr("The current page does not support import."), color: .systemOrange)
        case .error:
            appendFooter(viewModel.errorMessage ?? L10n.tr("Import failed."), color: .systemRed)
        case .preview:
            appendPreview(draft: viewModel.draft, isImporting: false)
        case .importing:
            appendPreview(draft: viewModel.draft, isImporting: true)
        case .done:
            appendPreview(draft: viewModel.draft, isImporting: false)
            appendFooter(L10n.tr("The import is complete."))
        }

        statusStackView.addArrangedSubviewWithMargin(UIView())
    }

    private func appendPreview(draft: ImportedTimetableDraft?, isImporting: Bool) {
        guard let draft else {
            appendFooter(L10n.tr("The import preview has not been generated yet."))
            return
        }

        let timetableView = ConfigurableInfoView()
        timetableView.configure(icon: UIImage(systemName: "calendar"))
        timetableView.configure(title: L10n.tr("curriculum"))
        timetableView.configure(description: L10n.tr("Imported class schedule name"))
        timetableView.configure(value: draft.name)
        statusStackView.addArrangedSubviewWithMargin(timetableView)
        statusStackView.addArrangedSubview(SeparatorView())

        let statsView = ConfigurableInfoView()
        statsView.configure(icon: UIImage(systemName: "square.stack.3d.up"))
        statsView.configure(title: L10n.tr("Import statistics"))
        statsView.configure(description: L10n.tr("Start date: %@ · Week number: %d", draft.startDate, draft.weeksCount))
        statsView.configure(value: L10n.tr("Section %d · Course %d", draft.periods.count, draft.courses.count))
        statusStackView.addArrangedSubviewWithMargin(statsView)
        statusStackView.addArrangedSubview(SeparatorView())

        if isImporting {
            appendFooter(L10n.tr("Importing class schedule..."))
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
            appendFooter(L10n.tr("After confirmation, it will be imported into the local class schedule."))
        }
    }

    private func appendFooter(_ text: String, color: UIColor = .secondaryLabel) {
        let footer = ConfigurableSectionFooterView().with(footer: text)
        footer.titleLabel.textColor = color
        statusStackView.addArrangedSubviewWithMargin(footer) { $0.top /= 2 }
        statusStackView.addArrangedSubview(SeparatorView())
    }

    private func updateNavigationState() {
        backItem.isEnabled = viewModel.canGoBack

        navigationItem.prompt = nil
        addressDisplayLabel.text = compactAddressTitle()
        if !isAddressEditing {
            addressInputField.text = viewModel.sourceURL
        }

        let title: String
        let enabled: Bool
        if isAddressEditing {
            title = L10n.tr("Go to")
            enabled = true
        } else {
            switch viewModel.phase {
            case .preview:
                title = L10n.tr("import")
                enabled = viewModel.draftErrors.isEmpty
            case .capturing:
                title = L10n.tr("Recognizing")
                enabled = false
            case .importing:
                title = L10n.tr("Importing")
                enabled = false
            case .done:
                title = L10n.tr("Finish")
                enabled = true
            default:
                title = L10n.tr("identify")
                enabled = true
            }
        }
        primaryItem.title = title
        primaryItem.isEnabled = enabled
    }

    private func clearArrangedSubviews(in stackView: UIStackView) {
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    @objc private func backTapped() {
        viewModel.proxy.goBack()
    }

    @objc private func reloadTapped() {
        viewModel.proxy.reload()
    }

    @objc private func beginAddressEditing() {
        guard !isAddressEditing else { return }
        isAddressEditing = true
        addressInputField.text = viewModel.sourceURL
        addressDisplayButton.isHidden = true
        addressInputField.isHidden = false
        addressInputField.becomeFirstResponder()
        DispatchQueue.main.async { [weak self] in
            self?.addressInputField.selectAll(nil)
        }
        updateNavigationState()
    }

    private func normalizeInputURL(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }

        let hasScheme = trimmed.range(of: #"^[a-zA-Z][a-zA-Z\d+.-]*:"#, options: .regularExpression) != nil
        let candidate = hasScheme ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate), url.scheme != nil else {
            return nil
        }
        return url.absoluteString
    }

    @discardableResult
    private func commitAddressInput() -> Bool {
        guard isAddressEditing else { return false }

        isAddressEditing = false
        addressDisplayButton.isHidden = false
        addressInputField.isHidden = true
        addressInputField.resignFirstResponder()

        guard let nextURL = normalizeInputURL(addressInputField.text) else {
            addressInputField.text = viewModel.sourceURL
            updateNavigationState()
            return false
        }

        addressInputField.text = nextURL
        if nextURL != viewModel.sourceURL {
            viewModel.proxy.load(nextURL)
        }
        updateNavigationState()
        return true
    }

    private func compactAddressTitle() -> String {
        if !viewModel.pageTitle.isEmpty {
            return viewModel.pageTitle
        }
        if let host = URL(string: viewModel.sourceURL)?.host, !host.isEmpty {
            return host
        }
        return viewModel.school.label
    }

    @objc private func closeTapped() {
        if let navigationController, navigationController.viewControllers.count > 1 {
            navigationController.popViewController(animated: true)
        } else {
            navigationController?.dismiss(animated: true)
        }
    }

    @objc private func primaryTapped() {
        if isAddressEditing {
            commitAddressInput()
            return
        }
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

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }

        if let url = navigationAction.request.url {
            let raw = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !raw.isEmpty, raw != "about:blank" {
                webView.load(navigationAction.request)
                return nil
            }
        }

        // Some sites call `window.open('', '_blank')` first, then set location on returned window.
        // Returning current webView lets subsequent location assignment stay in this window.
        return webView
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        commitAddressInput()
        return false
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        if isAddressEditing {
            commitAddressInput()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = max(160, min(360, view.bounds.width - 196))
        addressWidthConstraint?.constant = width
    }
}
