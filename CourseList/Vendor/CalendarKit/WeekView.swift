import UIKit

public protocol WeekViewDelegate: AnyObject {
    func dayViewDidSelectEventView(_ eventView: EventView)
    func dayViewDidLongPressEventView(_ eventView: EventView)
    func weekView(weekView: WeekView, didTapTimelineAt date: Date)
    func weekView(weekView: WeekView, didLongPressTimelineAt date: Date)
    func weekViewDidBeginDragging(weekView: WeekView)
    func weekViewDidTransitionCancel(weekView: WeekView)
    func weekView(weekView: WeekView, willMoveTo date: Date)
    func weekView(weekView: WeekView, didMoveTo date: Date)
    func weekView(weekView: WeekView, didUpdate event: EventDescriptor)
}

public class WeekView: UIView, WeekTimelinePagerViewDelegate {
    public weak var dataSource: EventDataSource? {
        get { weekTimelinePagerView.dataSource }
        set { weekTimelinePagerView.dataSource = newValue }
    }

    public weak var delegate: WeekViewDelegate?

    public var isHeaderViewVisible = true {
        didSet {
            headerHeight = isHeaderViewVisible ? WeekView.headerVisibleHeight : 0
            weekTimelinePagerView.headerHeight = headerHeight
            setNeedsLayout()
            configureLayout()
        }
    }

    public var timelineScrollOffset: CGPoint {
        weekTimelinePagerView.timelineScrollOffset
    }

    private static let headerVisibleHeight: Double = 64
    public var headerHeight: Double = headerVisibleHeight

    public var autoScrollToFirstEvent: Bool {
        get { weekTimelinePagerView.autoScrollToFirstEvent }
        set { weekTimelinePagerView.autoScrollToFirstEvent = newValue }
    }

    public let dayHeaderView: DayHeaderView
    public let weekTimelinePagerView: WeekTimelinePagerView

    public var state: DayViewState? {
        didSet {
            weekTimelinePagerView.state = state
        }
    }

    public var calendar: Calendar = Calendar.autoupdatingCurrent

    public var eventEditingSnappingBehavior: EventEditingSnappingBehavior {
        get { weekTimelinePagerView.eventEditingSnappingBehavior }
        set { weekTimelinePagerView.eventEditingSnappingBehavior = newValue }
    }

    private var style = CalendarStyle()

    public init(calendar: Calendar = Calendar.autoupdatingCurrent) {
        self.calendar = calendar
        self.dayHeaderView = DayHeaderView(calendar: calendar)
        self.weekTimelinePagerView = WeekTimelinePagerView(calendar: calendar)
        super.init(frame: .zero)
        configure()
    }

    override public init(frame: CGRect) {
        self.dayHeaderView = DayHeaderView(calendar: calendar)
        self.weekTimelinePagerView = WeekTimelinePagerView(calendar: calendar)
        super.init(frame: frame)
        configure()
    }

    required public init?(coder: NSCoder) {
        self.dayHeaderView = DayHeaderView(calendar: calendar)
        self.weekTimelinePagerView = WeekTimelinePagerView(calendar: calendar)
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        addSubview(weekTimelinePagerView)
        configureLayout()
        weekTimelinePagerView.headerHeight = headerHeight
        weekTimelinePagerView.delegate = self

        if state == nil {
            let newState = DayViewState(date: Date(), calendar: calendar)
            newState.move(to: Date())
            state = newState
        }
    }

    private func configureLayout() {
        weekTimelinePagerView.translatesAutoresizingMaskIntoConstraints = false

        weekTimelinePagerView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor).isActive = true
        weekTimelinePagerView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor).isActive = true
        weekTimelinePagerView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor).isActive = true
        weekTimelinePagerView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
    }

    public func updateStyle(_ newStyle: CalendarStyle) {
        style = newStyle
        weekTimelinePagerView.updateStyle(style)
    }

    public func timelinePanGestureRequire(toFail gesture: UIGestureRecognizer) {
        weekTimelinePagerView.timelinePanGestureRequire(toFail: gesture)
    }

    public func scrollTo(hour24: Float, animated: Bool = true) {
        weekTimelinePagerView.scrollTo(hour24: hour24, animated: animated)
    }

    public func scrollToFirstEventIfNeeded(animated: Bool = true) {
        weekTimelinePagerView.scrollToFirstEventIfNeeded(animated: animated)
    }

    public func reloadData() {
        weekTimelinePagerView.reloadData()
    }

    public func move(to date: Date) {
        state?.move(to: date)
    }

    public func transitionToHorizontalSizeClass(_ sizeClass: UIUserInterfaceSizeClass) {
        weekTimelinePagerView.transitionToHorizontalSizeClass(sizeClass)
        updateStyle(style)
    }

    public func create(event: EventDescriptor, animated: Bool = false) {
        weekTimelinePagerView.create(event: event, animated: animated)
    }

    public func beginEditing(event: EventDescriptor, animated: Bool = false) {
        weekTimelinePagerView.beginEditing(event: event, animated: animated)
    }

    public func endEventEditing() {
        weekTimelinePagerView.endEventEditing()
    }

    public func weekTimelinePagerDidSelectEventView(_ eventView: EventView) {
        delegate?.dayViewDidSelectEventView(eventView)
    }
    public func weekTimelinePagerDidLongPressEventView(_ eventView: EventView) {
        delegate?.dayViewDidLongPressEventView(eventView)
    }
    public func weekTimelinePagerDidBeginDragging(weekTimelinePager: WeekTimelinePagerView) {
        delegate?.weekViewDidBeginDragging(weekView: self)
    }
    public func weekTimelinePagerDidTransitionCancel(weekTimelinePager: WeekTimelinePagerView) {
        delegate?.weekViewDidTransitionCancel(weekView: self)
    }
    public func weekTimelinePager(weekTimelinePager: WeekTimelinePagerView, willMoveTo date: Date) {
        delegate?.weekView(weekView: self, willMoveTo: date)
    }
    public func weekTimelinePager(weekTimelinePager: WeekTimelinePagerView, didMoveTo date: Date) {
        delegate?.weekView(weekView: self, didMoveTo: date)
    }
    public func weekTimelinePager(weekTimelinePager: WeekTimelinePagerView, didLongPressTimelineAt date: Date) {
        delegate?.weekView(weekView: self, didLongPressTimelineAt: date)
    }
    public func weekTimelinePager(weekTimelinePager: WeekTimelinePagerView, didTapTimelineAt date: Date) {
        delegate?.weekView(weekView: self, didTapTimelineAt: date)
    }
    public func weekTimelinePager(weekTimelinePager: WeekTimelinePagerView, didUpdate event: EventDescriptor) {
        delegate?.weekView(weekView: self, didUpdate: event)
    }
}
