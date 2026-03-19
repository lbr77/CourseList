import ConfigurableKit
import UIKit

final class TextInputAnnotation: ConfigurableObject.AnnotationProtocol {
    private let placeholder: String

    init(placeholder: String = "") {
        self.placeholder = placeholder
    }

    @MainActor
    func createView(fromObject object: ConfigurableObject) -> ConfigurableView {
        TextInputConfigurableView(storage: object.__value, placeholder: placeholder)
    }
}

final class TextInputConfigurableView: ConfigurableValueView {
    private let placeholderText: String

    private var valueButton: EasyHitButton {
        contentView as! EasyHitButton
    }

    init(storage: CodableStorage, placeholder: String) {
        placeholderText = placeholder
        super.init(storage: storage)

        valueButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        valueButton.titleLabel?.numberOfLines = 3
        valueButton.titleLabel?.lineBreakMode = .byTruncatingMiddle
        valueButton.titleLabel?.textAlignment = .right
        valueButton.contentHorizontalAlignment = .right
        valueButton.addTarget(self, action: #selector(openEditor), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override class func createContentView() -> UIView {
        let button = EasyHitButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        return button
    }

    override func updateValue() {
        super.updateValue()

        let text = value.decodingValue(defaultValue: "")
        let displayText = text.isEmpty ? placeholderText : text
        let attrString = NSAttributedString(string: displayText, attributes: [
            .foregroundColor: text.isEmpty ? AlertControllerConfiguration.accentColor.withAlphaComponent(0.5) : AlertControllerConfiguration.accentColor,
            .font: UIFont.systemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize,
                weight: .semibold
            ),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
        valueButton.setAttributedTitle(attrString, for: .normal)
    }

    @objc private func openEditor() {
        guard let hostViewController else { return }

        let input = AlertInputViewController(
            title: titleLabel.text ?? "Edit",
            message: descriptionLabel.isHidden ? "" : (descriptionLabel.text ?? ""),
            placeholder: placeholderText,
            text: value.decodingValue(defaultValue: ""),
            cancelButtonText: "取消",
            doneButtonText: "确定"
        ) { [weak self] output in
            guard let self else { return }
            value = .init(output)
            updateValue()
        }
        hostViewController.present(input, animated: true)
    }

    private var hostViewController: UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController
            }
            responder = current.next
        }
        return nil
    }
}

public enum AlertControllerConfiguration {
    public static var alertImage: UIImage?
    public static var accentColor: UIColor = UIButton(type: .system).tintColor
    public static var separatorColor: UIColor = .separator
    public static var backgroundColor: UIColor = .systemBackground
}

open class ActionContext {
    public typealias ActionBlock = () -> Void
    public typealias DismissBlock = () -> Void
    public typealias DismissHandler = (@escaping DismissBlock) -> Void

    var actions = [Action]()
    var dismissHandler: DismissHandler?
    var userObject: Any?
    var simpleDisposeRequested = false

    let spacing: CGFloat = 16

    init() {}

    func bind(to viewController: UIViewController) {
        dismissHandler = { [weak viewController, self] completionBlock in
            dismissHandler = nil
            viewController?.dismiss(animated: true) {
                completionBlock()
            }
        }
    }

    open func addAction(
        title: String.LocalizationValue,
        attribute: Action.Attribute = .normal,
        block: @escaping () -> Void
    ) {
        actions.append(.init(
            title: String(localized: title),
            attribute: attribute,
            block: block
        ))
    }

    @_disfavoredOverload
    open func addAction(
        title: String,
        attribute: Action.Attribute = .normal,
        block: @escaping () -> Void
    ) {
        addAction(
            title: String.LocalizationValue(title),
            attribute: attribute,
            block: block
        )
    }

    open func dispose(_ completion: @escaping @MainActor () async -> Void = {}) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        dismissHandler? {
            Task { @MainActor in
                await completion()
            }
        }
    }
}

public extension ActionContext {
    struct Action {
        let title: String
        let attribute: Attribute
        let block: ActionBlock
    }
}

public extension ActionContext.Action {
    enum Attribute {
        case normal
        case accent
    }
}

public extension ActionContext {
    func allowSimpleDispose() {
        simpleDisposeRequested = true
    }
}

public typealias AlertControllerObject = UIViewController & UIViewControllerTransitioningDelegate

open class AlertBaseController: AlertControllerObject {
    public let dimmingView: UIView = .init()
    public let contentView: UIView = .init()
    public let contentLayoutGuide = UILayoutGuide()
    public let contentBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))

    open var shouldDismissWhenTappedAround = false
    open var shouldDismissWhenEscapeKeyPressed = false

    public init() {
        super.init(nibName: nil, bundle: nil)
        transitioningDelegate = self
        modalPresentationStyle = .custom
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override open func viewDidLoad() {
        super.viewDidLoad()
        defer { contentView.sendSubviewToBack(contentBackgroundView) }
        defer { contentView.layoutIfNeeded() }
        defer { contentViewDidLoad() }

        dimmingView.backgroundColor = .black
        view.addSubview(dimmingView)
        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dimmingView.topAnchor.constraint(equalTo: view.topAnchor),
            dimmingView.leftAnchor.constraint(equalTo: view.leftAnchor),
            dimmingView.rightAnchor.constraint(equalTo: view.rightAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        view.addLayoutGuide(contentLayoutGuide)
        if #available(iOS 15.0, *) {
            NSLayoutConstraint.activate([
                contentLayoutGuide.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
                contentLayoutGuide.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor, constant: 16),
                contentLayoutGuide.rightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.rightAnchor, constant: -16),
                contentLayoutGuide.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -16),
            ])
        } else {
            NSLayoutConstraint.activate([
                contentLayoutGuide.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
                contentLayoutGuide.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor, constant: 16),
                contentLayoutGuide.rightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.rightAnchor, constant: -16),
                contentLayoutGuide.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            ])
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        }

        contentView.backgroundColor = .clear
        contentView.clipsToBounds = true
        contentView.layer.cornerRadius = 16
        contentView.layer.cornerCurve = .continuous
        view.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.centerXAnchor.constraint(equalTo: contentLayoutGuide.centerXAnchor),
            contentView.centerYAnchor.constraint(equalTo: contentLayoutGuide.centerYAnchor),
            contentView.leadingAnchor.constraint(greaterThanOrEqualTo: contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(lessThanOrEqualTo: contentLayoutGuide.trailingAnchor),
        ])

        contentBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentBackgroundView)
        NSLayoutConstraint.activate([
            contentBackgroundView.topAnchor.constraint(equalTo: contentView.topAnchor),
            contentBackgroundView.leftAnchor.constraint(equalTo: contentView.leftAnchor),
            contentBackgroundView.rightAnchor.constraint(equalTo: contentView.rightAnchor),
            contentBackgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dimmingViewTapped))
        dimmingView.addGestureRecognizer(tapGesture)
    }

    @objc func contentBackgroundViewTapped() {}

    open func contentViewDidLoad() {}

    override open func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        contentViewLayout(in: contentView.bounds)
    }

    open func contentViewLayout(in bounds: CGRect) {
        _ = bounds
    }

    @objc func keyboardWillShow(_ notification: Notification) {
        let keyboardRect = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        let keyboardHeightValue = keyboardRect?.height ?? 0
        let keyboardHeight = keyboardHeightValue > 0 ? keyboardHeightValue : 0
        let animation = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
        let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval
        UIView.animate(withDuration: animationDuration ?? 0.25, delay: 0, options: UIView.AnimationOptions(rawValue: animation ?? 0)) {
            self.contentLayoutGuide.owningView?.bounds.origin.y += keyboardHeight / 2
            self.view.layoutIfNeeded()
        }
    }

    @objc func keyboardWillHide(_ notification: Notification) {
        let animation = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
        let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval
        UIView.animate(withDuration: animationDuration ?? 0.25, delay: 0, options: UIView.AnimationOptions(rawValue: animation ?? 0)) {
            self.contentLayoutGuide.owningView?.bounds.origin.y = 0
            self.view.layoutIfNeeded()
        }
    }

    func contentViewBounce() {
        UIView.animate(withDuration: 0.05) {
            self.contentView.transform = CGAffineTransform(scaleX: 0.995, y: 0.995)
        } completion: { _ in
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0.8) {
                self.contentView.transform = .identity
            }
        }
    }

    @objc open func dimmingViewTapped() {
        if shouldDismissWhenTappedAround {
            presentingViewController?.dismiss(animated: true)
        } else {
            contentViewBounce()
        }
    }

    override open func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            guard let key = press.key else { continue }
            if key.keyCode == .keyboardEscape {
                escapePressed()
                return
            }
        }
        super.pressesBegan(presses, with: event)
    }

    @objc open func escapePressed() {
        if shouldDismissWhenEscapeKeyPressed {
            presentingViewController?.dismiss(animated: true)
        } else {
            contentViewBounce()
        }
    }

    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if shouldDismissWhenEscapeKeyPressed, let firstResponder = view.window?.firstResponder() {
            firstResponder.resignFirstResponder()
            view.becomeFirstResponder()
        }
    }

    open func animationController(forPresented _: UIViewController, presenting _: UIViewController, source _: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        AlertTransitionAnimator(isPresenting: true)
    }

    open func animationController(forDismissed _: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        AlertTransitionAnimator(isPresenting: false)
    }

    open func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source _: UIViewController) -> UIPresentationController? {
        AlertPresentationController(presentedViewController: presented, presenting: presenting)
    }
}

private extension UIView {
    func firstResponder() -> UIView? {
        var views = [UIView](arrayLiteral: self)
        var index = 0
        repeat {
            let view = views[index]
            if view.isFirstResponder {
                return view
            }
            views.append(contentsOf: view.subviews)
            index += 1
        } while index < views.count
        return nil
    }
}

public final class AlertPresentationController: UIPresentationController {
    override public func presentationTransitionWillBegin() {
        guard let alertController = presentedViewController as? AlertBaseController else { return }
        alertController.dimmingView.alpha = 0
        alertController.contentView.alpha = 0
        alertController.contentView.transform = .init(scaleX: 1.1, y: 1.1)
        containerView?.addSubview(alertController.view)
    }

    override public func presentationTransitionDidEnd(_ completed: Bool) {
        if !completed {
            presentedViewController.view.removeFromSuperview()
        }
    }
}

public final class AlertTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let isPresenting: Bool

    public init(isPresenting: Bool) {
        self.isPresenting = isPresenting
    }

    public func transitionDuration(using _: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        0.24
    }

    public func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) {
        let alertController = if isPresenting {
            transitionContext.viewController(forKey: .to)
        } else {
            transitionContext.viewController(forKey: .from)
        }
        guard let alertController = alertController as? AlertBaseController else {
            transitionContext.completeTransition(false)
            return
        }

        let dimmingView = alertController.dimmingView
        let alertView = alertController.contentView

        if isPresenting {
            dimmingView.alpha = 0
            alertView.alpha = 0
            alertView.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
        }
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.8) {
            if self.isPresenting {
                dimmingView.alpha = 0.25
                alertView.alpha = 1
                alertView.transform = .identity
            } else {
                dimmingView.alpha = 0
                alertView.alpha = 0
                alertView.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
            }
        } completion: {
            transitionContext.completeTransition($0)
        }
    }
}

class HorizontalSeprator: UIView {
    init() {
        super.init(frame: .zero)
        backgroundColor = AlertControllerConfiguration.separatorColor
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class AlertButton: UIView {
    let action: ActionContext.Action
    let label = UILabel()

    init(action: ActionContext.Action) {
        self.action = action
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        label.text = action.title
        label.textColor = action.foregroundColor
        label.textAlignment = .center
        label.font = action.font

        layer.borderWidth = 1
        layer.borderColor = action.borderColor.cgColor
        backgroundColor = action.backgroundColor
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous

        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])

        isUserInteractionEnabled = true
        let gesture = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(gesture)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func tapped() {
        alpha = 0.75
        UIView.animate(withDuration: 0.25) {
            self.alpha = 1
        }
        Task { @MainActor in
            self.action.block()
        }
    }
}

extension ActionContext.Action {
    var foregroundColor: UIColor {
        switch attribute {
        case .accent:
            .white
        case .normal:
            AlertControllerConfiguration.accentColor
        }
    }

    var backgroundColor: UIColor {
        switch attribute {
        case .accent:
            AlertControllerConfiguration.accentColor
        case .normal:
            .clear
        }
    }

    var borderColor: UIColor {
        AlertControllerConfiguration.accentColor
    }

    var font: UIFont {
        switch attribute {
        case .accent:
            .systemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .semibold)
        case .normal:
            .systemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        }
    }
}

class AlertContentController: UIViewController {
    let context: ActionContext = .init()
    let messageTitle: String
    let messageContent: String
    let stackView = UIStackView()
    let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    var customViews: [UIView] = []

    init(title: String = "", message: String = "", setupActions: @escaping (ActionContext) -> Void) {
        messageTitle = title
        messageContent = message
        super.init(nibName: nil, bundle: nil)
        context.bind(to: self)
        setupActions(context)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AlertControllerConfiguration.backgroundColor.withAlphaComponent(0.5)

        view.addSubview(backgroundView)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        view.addSubview(stackView)
        stackView.axis = .vertical
        stackView.spacing = context.spacing
        stackView.distribution = .equalSpacing
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: context.spacing),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -context.spacing),
        ])

        if let image = AlertControllerConfiguration.alertImage {
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.image = image
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.layer.cornerRadius = 12
            imageView.layer.cornerCurve = .continuous
            imageView.layer.masksToBounds = true
            imageView.heightAnchor.constraint(equalToConstant: 64).isActive = true
            imageView.widthAnchor.constraint(equalToConstant: 64).isActive = true
            stackView.addArrangedSubview(imageView)
        }

        if !messageTitle.isEmpty {
            let titleLabel = UILabel()
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.text = messageTitle
            titleLabel.font = .systemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .semibold)
            titleLabel.textColor = .label
            titleLabel.textAlignment = .center
            titleLabel.numberOfLines = 0
            stackView.addArrangedSubview(titleLabel)
            NSLayoutConstraint.activate([
                titleLabel.leadingAnchor.constraint(equalTo: stackView.leadingAnchor, constant: 16),
                titleLabel.trailingAnchor.constraint(equalTo: stackView.trailingAnchor, constant: -16),
            ])
            let heightConstraint = titleLabel.heightAnchor.constraint(lessThanOrEqualToConstant: 80)
            heightConstraint.priority = .required
            NSLayoutConstraint.activate([heightConstraint])
        }

        if !messageContent.isEmpty {
            let messageLabel = UILabel()
            messageLabel.translatesAutoresizingMaskIntoConstraints = false
            messageLabel.text = messageContent
            messageLabel.font = .systemFont(ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize)
            messageLabel.textColor = .label
            messageLabel.textAlignment = .center
            messageLabel.numberOfLines = 0
            stackView.addArrangedSubview(messageLabel)
            NSLayoutConstraint.activate([
                messageLabel.leadingAnchor.constraint(equalTo: stackView.leadingAnchor, constant: 16),
                messageLabel.trailingAnchor.constraint(equalTo: stackView.trailingAnchor, constant: -16),
            ])
            let heightConstraint = messageLabel.heightAnchor.constraint(lessThanOrEqualToConstant: 300)
            heightConstraint.priority = .required
            NSLayoutConstraint.activate([heightConstraint])
        }

        for customView in customViews {
            stackView.addArrangedSubview(customView)
            customView.translatesAutoresizingMaskIntoConstraints = false
            let spacing: CGFloat = customView is HorizontalSeprator ? 0 : 16
            customView.leadingAnchor.constraint(equalTo: stackView.leadingAnchor, constant: spacing).isActive = true
            customView.trailingAnchor.constraint(equalTo: stackView.trailingAnchor, constant: -spacing).isActive = true
        }

        switch context.actions.count {
        case 2:
            let horizonStack = UIStackView()
            horizonStack.axis = .horizontal
            horizonStack.spacing = 8
            horizonStack.distribution = .fillEqually
            horizonStack.alignment = .center
            horizonStack.translatesAutoresizingMaskIntoConstraints = false
            stackView.addArrangedSubview(horizonStack)
            horizonStack.leadingAnchor.constraint(equalTo: stackView.leadingAnchor, constant: 16).isActive = true
            horizonStack.trailingAnchor.constraint(equalTo: stackView.trailingAnchor, constant: -16).isActive = true
            for action in context.actions {
                horizonStack.addArrangedSubview(AlertButton(action: action))
            }
        default:
            for action in context.actions {
                let button = AlertButton(action: action)
                stackView.addArrangedSubview(button)
                button.leadingAnchor.constraint(equalTo: stackView.leadingAnchor, constant: 16).isActive = true
                button.trailingAnchor.constraint(equalTo: stackView.trailingAnchor, constant: -16).isActive = true
            }
        }
    }
}

open class AlertViewController: AlertBaseController {
    let contentViewController: UIViewController

    public convenience init(title: String.LocalizationValue = "", message: String.LocalizationValue = "", setupActions: @escaping (ActionContext) -> Void) {
        let controller = AlertContentController(title: String(localized: title), message: String(localized: message), setupActions: setupActions)
        self.init(contentViewController: controller)
    }

    @_disfavoredOverload
    public convenience init(title: String = "", message: String = "", setupActions: @escaping (ActionContext) -> Void) {
        self.init(title: String.LocalizationValue(title), message: String.LocalizationValue(message), setupActions: setupActions)
    }

    public required init(contentViewController: UIViewController) {
        self.contentViewController = contentViewController
        super.init()

        var enableEscapeDismiss = false
        if let content = contentViewController as? AlertContentController {
            content.context.bind(to: self)
            enableEscapeDismiss = content.context.simpleDisposeRequested
        }

        transitioningDelegate = self
        modalPresentationStyle = .custom
        shouldDismissWhenTappedAround = false
        shouldDismissWhenEscapeKeyPressed = enableEscapeDismiss
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override open func viewDidLoad() {
        super.viewDidLoad()
        contentView.layer.cornerRadius = 20
    }

    override open func contentViewDidLoad() {
        super.contentViewDidLoad()
        addChild(contentViewController)
        contentView.addSubview(contentViewController.view)
        contentViewController.view.translatesAutoresizingMaskIntoConstraints = false
        contentViewController.didMove(toParent: self)
        NSLayoutConstraint.activate([
            contentViewController.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            contentViewController.view.leftAnchor.constraint(equalTo: contentView.leftAnchor),
            contentViewController.view.rightAnchor.constraint(equalTo: contentView.rightAnchor),
            contentViewController.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            contentView.widthAnchor.constraint(equalToConstant: 350),
        ])
    }
}

class AlertInputContentController: AlertContentController {
    let field = InputField()
    private var submitAction: (ActionContext) -> Void = { _ in }

    init(
        title: String = "",
        message: String = "",
        originalText: String,
        placeholder: String,
        setupActions: @escaping (ActionContext) -> Void,
        onSubmit: @escaping (ActionContext) -> Void
    ) {
        super.init(title: title, message: message, setupActions: setupActions)
        context.userObject = originalText
        field.textField.placeholder = placeholder
        field.textField.text = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        field.textPublisher = { [weak self] text in
            self?.context.userObject = text
        }
        field.textReturnAction = { [weak self] in
            self?.callSubmit()
        }
        customViews.append(field)
        submitAction = onSubmit
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        field.textField.becomeFirstResponder()
        field.updateQuickOptionImage()
    }

    private func callSubmit() {
        submitAction(context)
        submitAction = { _ in }
    }
}

private class UITextFieldWithoutEscapeToClear: UITextField {
    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(stub))]
    }

    @objc func stub() {}
}

class InputField: UIView, UITextFieldDelegate {
    fileprivate let textField = UITextFieldWithoutEscapeToClear(frame: .zero)
    var textPublisher: (String) -> Void = { _ in }
    var textReturnAction: () -> Void = {}
    let quickOptionButton = UIButton()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 32).isActive = true

        backgroundColor = AlertControllerConfiguration.accentColor.withAlphaComponent(0.1)
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous

        textField.textColor = .label.withAlphaComponent(0.9)
        textField.font = .preferredFont(forTextStyle: .footnote)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.borderStyle = .none
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.allowsEditingTextAttributes = false

        quickOptionButton.translatesAutoresizingMaskIntoConstraints = false
        quickOptionButton.imageView?.contentMode = .scaleAspectFit
        quickOptionButton.tintColor = AlertControllerConfiguration.accentColor
        quickOptionButton.addTarget(self, action: #selector(tappedOptionButton), for: .touchUpInside)
        updateQuickOptionImage()

        addSubview(textField)
        addSubview(quickOptionButton)

        NSLayoutConstraint.activate([
            textField.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            quickOptionButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            quickOptionButton.leadingAnchor.constraint(equalTo: textField.trailingAnchor, constant: 8),
            quickOptionButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            quickOptionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            quickOptionButton.widthAnchor.constraint(equalTo: quickOptionButton.heightAnchor),
        ])

        textField.delegate = self
        textField.addTarget(self, action: #selector(valueChanged), for: .valueChanged)
        textField.addTarget(self, action: #selector(valueChanged), for: .editingChanged)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateQuickOptionImage() {
        if (textField.text ?? "").isEmpty {
            quickOptionButton.setImage(UIImage(systemName: "doc.on.clipboard"), for: .normal)
        } else {
            quickOptionButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        }
    }

    @objc func tappedOptionButton() {
        if (textField.text ?? "").isEmpty {
            textField.text = UIPasteboard.general.string
        } else {
            textField.text = ""
        }
        valueChanged()
    }

    @objc func valueChanged() {
        updateQuickOptionImage()
        textPublisher(textField.text ?? "")
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        textReturnAction()
        textReturnAction = {}
        return true
    }
}

open class AlertInputViewController: AlertViewController {
    public convenience init(
        title: String.LocalizationValue = "",
        message: String.LocalizationValue = "",
        placeholder: String.LocalizationValue,
        text: String,
        cancelButtonText: String.LocalizationValue = "Cancel",
        doneButtonText: String.LocalizationValue = "Done",
        onConfirm: @escaping (String) -> Void
    ) {
        let controller = AlertInputContentController(
            title: String(localized: title),
            message: String(localized: message),
            originalText: text,
            placeholder: String(localized: placeholder)
        ) { context in
            context.addAction(title: cancelButtonText) {
                context.dispose()
            }
            context.addAction(title: doneButtonText, attribute: .accent) {
                context.dispose {
                    let text = context.userObject as! String
                    onConfirm(text)
                }
            }
        } onSubmit: { context in
            context.dispose {
                let text = context.userObject as! String
                onConfirm(text)
            }
        }
        self.init(contentViewController: controller)
    }

    @_disfavoredOverload
    public convenience init(
        title: String = "",
        message: String = "",
        placeholder: String,
        text: String,
        cancelButtonText: String = "Cancel",
        doneButtonText: String = "Done",
        onConfirm: @escaping (String) -> Void
    ) {
        self.init(
            title: String.LocalizationValue(title),
            message: String.LocalizationValue(message),
            placeholder: String.LocalizationValue(placeholder),
            text: text,
            cancelButtonText: String.LocalizationValue(cancelButtonText),
            doneButtonText: String.LocalizationValue(doneButtonText),
            onConfirm: onConfirm
        )
    }

    public required init(contentViewController: UIViewController) {
        super.init(contentViewController: contentViewController)
    }
}

final class AlertDatePickerContentController: AlertContentController {
    let picker = UIDatePicker()

    init(
        title: String = "",
        message: String = "",
        mode: UIDatePicker.Mode,
        selectedDate: Date,
        setupActions: @escaping (ActionContext) -> Void
    ) {
        super.init(title: title, message: message, setupActions: setupActions)

        let preferredStyle: UIDatePickerStyle = if mode == .date {
            .inline
        } else {
            .wheels
        }

        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.datePickerMode = mode
        picker.date = selectedDate
        picker.preferredDatePickerStyle = preferredStyle

        if mode == .time {
            picker.locale = Locale(identifier: "zh_CN")
        }

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(picker)

        var constraints = [
            picker.topAnchor.constraint(equalTo: container.topAnchor),
            picker.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            picker.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ]

        if preferredStyle == .wheels {
            constraints.append(container.heightAnchor.constraint(equalToConstant: 216))
        }

        NSLayoutConstraint.activate(constraints)

        customViews.append(container)
    }
}

open class AlertDatePickerViewController: AlertViewController {
    public convenience init(
        title: String,
        message: String = "",
        mode: UIDatePicker.Mode,
        selectedDate: Date,
        cancelButtonText: String = "取消",
        doneButtonText: String = "确定",
        onConfirm: @escaping (Date) -> Void
    ) {
        var controller: AlertDatePickerContentController!
        controller = AlertDatePickerContentController(
            title: title,
            message: message,
            mode: mode,
            selectedDate: selectedDate
        ) { context in
            context.addAction(title: cancelButtonText) {
                context.dispose()
            }
            context.addAction(title: doneButtonText, attribute: .accent) {
                context.dispose {
                    onConfirm(controller.picker.date)
                }
            }
        }

        self.init(contentViewController: controller)
    }

    public required init(contentViewController: UIViewController) {
        super.init(contentViewController: contentViewController)
    }
}
