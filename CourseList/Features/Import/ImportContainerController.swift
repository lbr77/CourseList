import UIKit

@MainActor
final class ImportContainerController: UIViewController {
    private let viewModel: ImportViewModel
    private let onImported: () -> Void
    private lazy var browserController = ImportBrowserController(viewModel: viewModel, onImported: onImported)

    init(viewModel: ImportViewModel, onImported: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onImported = onImported
        super.init(nibName: nil, bundle: nil)
        title = viewModel.school.label
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        addChild(browserController)
        view.addSubview(browserController.view)
        browserController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            browserController.view.topAnchor.constraint(equalTo: view.topAnchor),
            browserController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            browserController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            browserController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        browserController.didMove(toParent: self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let navigationController, navigationController.viewControllers.count > 1 {
            navigationController.setNavigationBarHidden(false, animated: animated)
        }
    }
}
