import UIKit

@objc public final class CurrentTimeIndicator: UIView {
    private let padding : Double = 3
    public var leadingInset: Double = 53 {
        didSet {
            timeLabelWidthConstraint?.constant = max(0, leadingInset)
            setNeedsLayout()
        }
    }

    public var trailingInset: Double = 0 {
        didSet {
            setNeedsLayout()
        }
    }

    public var calendar: Calendar = Calendar.autoupdatingCurrent {
        didSet {
            updateDate()
        }
    }

    /// Determines if times should be displayed in a 24 hour format. Defaults to the current locale's setting
    public var is24hClock : Bool = true {
        didSet {
            updateDate()
        }
    }

    public var date = Date() {
        didSet {
            updateDate()
        }
    }

    private var timeLabel = UILabel()
    private var circle = UIView()
    private var line = UIView()
    private var timeLabelWidthConstraint: NSLayoutConstraint?

    private var style = CurrentTimeIndicatorStyle()

    private lazy var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = calendar.locale
        dateFormatter.timeZone = calendar.timeZone
        return dateFormatter
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        configure()
    }

    private func configure() {
        [timeLabel, circle, line].forEach {
            addSubview($0)
        }

        //Allow label to adjust so that am/pm can be displayed if format is changed.
        timeLabel.numberOfLines = 1
        timeLabel.textAlignment = .center
        timeLabel.adjustsFontSizeToFitWidth = true
        timeLabel.minimumScaleFactor = 0.5

        //The width of the label is determined by leftInset and padding.
        //The y position is determined by the line's middle.
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        let widthConstraint = timeLabel.widthAnchor.constraint(equalToConstant: leadingInset)
        widthConstraint.isActive = true
        timeLabelWidthConstraint = widthConstraint
        timeLabel.trailingAnchor.constraint(equalTo: line.leadingAnchor).isActive = true
        timeLabel.centerYAnchor.constraint(equalTo: line.centerYAnchor).isActive = true
        timeLabel.baselineAdjustment = .alignCenters

        updateStyle(style)
        isUserInteractionEnabled = false
    }
    
    private func updateDate() {
        dateFormatter.dateFormat = is24hClock ? "HH:mm" : "h:mm a"
        dateFormatter.calendar = calendar
        dateFormatter.timeZone = calendar.timeZone
        timeLabel.text = dateFormatter.string(from: date)
        timeLabel.sizeToFit()
        setNeedsLayout()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        line.frame = {

            let x: Double
            let rightToLeft = UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .rightToLeft
            if rightToLeft {
                x = trailingInset
            } else {
                x = leadingInset - padding
            }

            return CGRect(x: x,
                          y: bounds.height / 2,
                          width: max(0, bounds.width - leadingInset - trailingInset),
                          height: 1)
        }()

        circle.frame = {

            let x: Double
            if UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .rightToLeft {
                x = bounds.width - leadingInset - 10
            } else {
                x = leadingInset + 1
            }

            return CGRect(x: x, y: 0, width: 6, height: 6)
        }()
        circle.center.y = line.center.y
        circle.layer.cornerRadius = circle.bounds.height / 2
    }

    func updateStyle(_ newStyle: CurrentTimeIndicatorStyle) {
        style = newStyle
        timeLabel.textColor = style.color
        timeLabel.font = style.font
        circle.backgroundColor = style.color
        line.backgroundColor = style.color

        switch style.dateStyle {
        case .twelveHour:
            is24hClock = false
            break
        case .twentyFourHour:
            is24hClock = true
            break
        default:
            is24hClock = Locale.autoupdatingCurrent.uses24hClock
            break
        }
    }
}
