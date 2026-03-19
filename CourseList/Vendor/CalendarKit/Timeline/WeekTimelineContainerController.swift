import UIKit

public final class WeekTimelineContainerController: UIViewController {
    public var pendingContentOffset: CGPoint?
    public var onSelectDate: ((Date) -> Void)? {
        didSet { dayHeaderView.onSelectDate = onSelectDate }
    }
    public var headerHeight: Double {
        didSet { view.setNeedsLayout() }
    }

    public private(set) lazy var dayHeaderView = DayHeaderView(calendar: calendar)
    public private(set) lazy var timeline = WeekTimelineView()
    public private(set) lazy var container: WeekTimelineContainer = {
        let view = WeekTimelineContainer(timeline)
        view.addSubview(timeline)
        return view
    }()
    private let calendar: Calendar
    private let rootView = UIView()

    public init(calendar: Calendar, headerHeight: Double) {
        self.calendar = calendar
        self.headerHeight = headerHeight
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        rootView.addSubview(dayHeaderView)
        rootView.addSubview(container)
        view = rootView
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        dayHeaderView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: headerHeight)
        container.frame = CGRect(x: 0, y: headerHeight, width: view.bounds.width, height: max(0, view.bounds.height - headerHeight))
        container.contentSize = timeline.frame.size
        if let newOffset = pendingContentOffset, view.bounds != .zero {
            container.setContentOffset(newOffset, animated: false)
            container.setNeedsLayout()
            pendingContentOffset = nil
        }
    }

    public func updateHeaderStyle(_ style: DayHeaderStyle) {
        dayHeaderView.updateStyle(style)
    }

    public func setDisplayedDate(_ date: Date) {
        dayHeaderView.setDisplayedDate(date)
    }

    public func transitionToHorizontalSizeClass(_ sizeClass: UIUserInterfaceSizeClass) {
        dayHeaderView.transitionToHorizontalSizeClass(sizeClass)
    }
}
