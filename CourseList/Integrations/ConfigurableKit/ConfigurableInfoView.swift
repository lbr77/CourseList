import ConfigurableKit
import UIKit

final class ConfigurableInfoView: ConfigurableView {
    var valueLabel: EasyHitButton { contentView as! EasyHitButton }

    private var onTapBlock: ((ConfigurableInfoView) -> Void) = { _ in }

    override init() {
        super.init()
        valueLabel.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        valueLabel.titleLabel?.numberOfLines = 3
        valueLabel.titleLabel?.lineBreakMode = .byTruncatingMiddle
        valueLabel.titleLabel?.textAlignment = .right
        valueLabel.contentHorizontalAlignment = .right
        valueLabel.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            valueLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.5),
            valueLabel.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            valueLabel.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            valueLabel.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(value: String, isDestructive: Bool = false) {
        let attrString = NSAttributedString(string: value, attributes: [
            .foregroundColor: isDestructive ? UIColor.systemRed : AlertControllerConfiguration.accentColor,
            .font: UIFont.systemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize,
                weight: .semibold
            ),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
        valueLabel.setAttributedTitle(attrString, for: .normal)
    }

    func configure(menu: UIMenu?) {
        valueLabel.menu = menu
        valueLabel.showsMenuAsPrimaryAction = menu != nil
    }

    @discardableResult
    func setTapBlock(_ block: @escaping (ConfigurableInfoView) -> Void) -> Self {
        onTapBlock = block
        return self
    }

    @objc private func tapped() {
        guard valueLabel.menu == nil else { return }
        onTapBlock(self)
    }

    override class func createContentView() -> UIView {
        EasyHitButton()
    }
}

extension UIView {
    var hostingViewController: UIViewController? {
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
