import UIKit

public protocol WeekTimelinePagerViewDelegate: AnyObject {
    func weekTimelinePagerDidSelectEventView(_ eventView: EventView)
    func weekTimelinePagerDidLongPressEventView(_ eventView: EventView)
    func weekTimelinePager(weekTimelinePager: WeekTimelinePagerView, didTapTimelineAt date: Date)
    func weekTimelinePagerDidBeginDragging(weekTimelinePager: WeekTimelinePagerView)
    func weekTimelinePagerDidTransitionCancel(weekTimelinePager: WeekTimelinePagerView)
    func weekTimelinePager(weekTimelinePager: WeekTimelinePagerView, willMoveTo date: Date)
    func weekTimelinePager(weekTimelinePager: WeekTimelinePagerView, didMoveTo date: Date)
    func weekTimelinePager(weekTimelinePager: WeekTimelinePagerView, didLongPressTimelineAt date: Date)
    func weekTimelinePager(weekTimelinePager: WeekTimelinePagerView, didUpdate event: EventDescriptor)
}

public final class WeekTimelinePagerView: UIView, UIScrollViewDelegate, DayViewStateUpdating, UIPageViewControllerDataSource, UIPageViewControllerDelegate, WeekTimelineViewDelegate {
    public weak var dataSource: EventDataSource?
    public weak var delegate: WeekTimelinePagerViewDelegate?

    public private(set) var calendar: Calendar = Calendar.autoupdatingCurrent
    public var eventEditingSnappingBehavior: EventEditingSnappingBehavior {
        didSet { updateEventEditingSnappingBehavior() }
    }

    public var timelineScrollOffset: CGPoint {
        currentTimeline?.container.contentOffset ?? .zero
    }

    private var currentTimeline: WeekTimelineContainerController? {
        pagingViewController.viewControllers?.first as? WeekTimelineContainerController
    }

    public var autoScrollToFirstEvent = false
    public var headerHeight: Double = 64 {
        didSet {
            pagingViewController.viewControllers?.forEach {
                if let controller = $0 as? WeekTimelineContainerController {
                    controller.headerHeight = headerHeight
                }
            }
        }
    }
    private var pagingViewController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)
    private var style = CalendarStyle()
    private var currentSizeClass = UIUserInterfaceSizeClass.compact

    public weak var state: DayViewState? {
        willSet { state?.unsubscribe(client: self) }
        didSet { state?.subscribe(client: self) }
    }

    public init(calendar: Calendar) {
        self.calendar = calendar
        self.eventEditingSnappingBehavior = SnapTo15MinuteIntervals(calendar)
        super.init(frame: .zero)
        configure()
    }

    override public init(frame: CGRect) {
        self.eventEditingSnappingBehavior = SnapTo15MinuteIntervals(calendar)
        super.init(frame: frame)
        configure()
    }

    required public init?(coder: NSCoder) {
        self.eventEditingSnappingBehavior = SnapTo15MinuteIntervals(calendar)
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        let viewController = configureTimelineController(date: Date())
        pagingViewController.setViewControllers([viewController], direction: .forward, animated: false)
        pagingViewController.dataSource = self
        pagingViewController.delegate = self
        addSubview(pagingViewController.view!)
    }

    public func updateStyle(_ newStyle: CalendarStyle) {
        style = newStyle
        pagingViewController.viewControllers?.forEach {
            if let controller = $0 as? WeekTimelineContainerController {
                updateStyleOfTimelineContainer(controller: controller)
            }
        }
        pagingViewController.view.backgroundColor = style.timeline.backgroundColor
    }

    private func updateStyleOfTimelineContainer(controller: WeekTimelineContainerController) {
        var headerStyle = style.header
        headerStyle.leadingInset = style.timeline.leadingInset
        headerStyle.trailingInset = style.timeline.trailingInset
        controller.updateHeaderStyle(headerStyle)
        controller.timeline.updateStyle(style.timeline)
        controller.container.backgroundColor = style.timeline.backgroundColor
        controller.view.backgroundColor = style.timeline.backgroundColor
        controller.transitionToHorizontalSizeClass(currentSizeClass)
    }

    private func updateEventEditingSnappingBehavior() {
        pagingViewController.viewControllers?.forEach {
            if let controller = $0 as? WeekTimelineContainerController {
                controller.timeline.eventEditingSnappingBehavior = eventEditingSnappingBehavior
            }
        }
    }

    public func timelinePanGestureRequire(toFail gesture: UIGestureRecognizer) {
    }

    public func scrollTo(hour24: Float, animated: Bool = true) {
        currentTimeline?.container.scrollTo(hour24: hour24, animated: animated)
    }

    private func configureTimelineController(date: Date) -> WeekTimelineContainerController {
        let controller = WeekTimelineContainerController(calendar: calendar, headerHeight: headerHeight)
        controller.onSelectDate = { [weak self] date in
            self?.state?.move(to: date)
        }
        updateStyleOfTimelineContainer(controller: controller)
        let timeline = controller.timeline
        timeline.longPressGestureRecognizer.addTarget(self, action: #selector(timelineDidLongPress(_:)))
        timeline.delegate = self
        timeline.calendar = calendar
        timeline.eventEditingSnappingBehavior = eventEditingSnappingBehavior
        timeline.selectedDate = date.dateOnly(calendar: calendar)
        timeline.weekStartDate = beginningOfWeek(date)
        controller.setDisplayedDate(date)
        controller.container.delegate = self
        updateTimeline(timeline)
        return controller
    }

    private var initialContentOffset = CGPoint.zero
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        initialContentOffset = scrollView.contentOffset
        delegate?.weekTimelinePagerDidBeginDragging(weekTimelinePager: self)
    }

    public func reloadData() {
        pagingViewController.children.forEach {
            if let controller = $0 as? WeekTimelineContainerController {
                updateTimeline(controller.timeline)
                controller.setDisplayedDate(controller.timeline.selectedDate)
            }
        }
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        pagingViewController.view.frame = bounds
    }

    private func updateTimeline(_ timeline: WeekTimelineView) {
        guard let dataSource else { return }
        let weekDates = datesForWeek(containing: timeline.selectedDate)
        timeline.weekStartDate = weekDates.first ?? timeline.selectedDate
        timeline.selectedDate = timeline.selectedDate.dateOnly(calendar: calendar)
        var validEvents = [EventDescriptor]()
        for date in weekDates {
            let events = dataSource.eventsForDate(date.dateOnly(calendar: calendar))
            let end = calendar.date(byAdding: .day, value: 1, to: date.dateOnly(calendar: calendar))!
            let day = DateInterval(start: date.dateOnly(calendar: calendar), end: end)
            validEvents.append(contentsOf: events.filter { $0.dateInterval.intersects(day) })
        }
        timeline.layoutAttributes = validEvents.map(EventLayoutAttributes.init)
    }

    public func scrollToFirstEventIfNeeded(animated: Bool) {
        if autoScrollToFirstEvent {
            currentTimeline?.container.scrollToFirstEvent(animated: animated)
        }
    }

    public func move(from oldDate: Date, to newDate: Date) {
        let oldWeek = beginningOfWeek(oldDate)
        let newWeek = beginningOfWeek(newDate)
        if calendar.isDate(oldWeek, inSameDayAs: newWeek) {
            currentTimeline?.timeline.selectedDate = newDate.dateOnly(calendar: calendar)
            currentTimeline?.setDisplayedDate(newDate)
            currentTimeline?.timeline.setNeedsDisplay()
            currentTimeline?.timeline.setNeedsLayout()
        } else {
            let controller = configureTimelineController(date: newDate)
            controller.pendingContentOffset = currentTimeline?.container.contentOffset
            let direction: UIPageViewController.NavigationDirection = newDate > oldDate ? .forward : .reverse
            delegate?.weekTimelinePager(weekTimelinePager: self, willMoveTo: newDate)
            pagingViewController.setViewControllers([controller], direction: direction, animated: true)
            delegate?.weekTimelinePager(weekTimelinePager: self, didMoveTo: newDate)
        }
    }

    private func beginningOfWeek(_ date: Date) -> Date {
        let weekOfYear = calendar.component(.weekOfYear, from: date)
        let yearForWeekOfYear = calendar.component(.yearForWeekOfYear, from: date)
        return calendar.date(from: DateComponents(calendar: calendar, weekday: calendar.firstWeekday, weekOfYear: weekOfYear, yearForWeekOfYear: yearForWeekOfYear))!
    }

    private func datesForWeek(containing date: Date) -> [Date] {
        let start = beginningOfWeek(date).dateOnly(calendar: calendar)
        return (0 ..< 7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    public func transitionToHorizontalSizeClass(_ sizeClass: UIUserInterfaceSizeClass) {
        currentSizeClass = sizeClass
        pagingViewController.viewControllers?.forEach {
            if let controller = $0 as? WeekTimelineContainerController {
                controller.transitionToHorizontalSizeClass(sizeClass)
            }
        }
    }

    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let controller = viewController as? WeekTimelineContainerController else { return nil }
        let previousDate = calendar.date(byAdding: .weekOfYear, value: -1, to: controller.timeline.selectedDate)!
        let newController = configureTimelineController(date: previousDate)
        newController.pendingContentOffset = currentTimeline?.container.contentOffset
        return newController
    }

    public func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let controller = viewController as? WeekTimelineContainerController else { return nil }
        let nextDate = calendar.date(byAdding: .weekOfYear, value: 1, to: controller.timeline.selectedDate)!
        let newController = configureTimelineController(date: nextDate)
        newController.pendingContentOffset = currentTimeline?.container.contentOffset
        return newController
    }

    public func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        if let controller = pendingViewControllers.first as? WeekTimelineContainerController {
            delegate?.weekTimelinePager(weekTimelinePager: self, willMoveTo: controller.timeline.selectedDate)
        }
    }

    public func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let controller = pageViewController.viewControllers?.first as? WeekTimelineContainerController else {
            delegate?.weekTimelinePagerDidTransitionCancel(weekTimelinePager: self)
            return
        }
        state?.client(client: self, didMoveTo: controller.timeline.selectedDate)
        delegate?.weekTimelinePager(weekTimelinePager: self, didMoveTo: controller.timeline.selectedDate)
    }

    public func create(event: EventDescriptor, animated: Bool) {}
    public func beginEditing(event: EventDescriptor, animated: Bool) {}
    public func endEventEditing() {}

    public func weekTimelineView(_ timelineView: WeekTimelineView, didTapAt date: Date) {
        delegate?.weekTimelinePager(weekTimelinePager: self, didTapTimelineAt: date)
    }
    public func weekTimelineView(_ timelineView: WeekTimelineView, didLongPressAt date: Date) {
        delegate?.weekTimelinePager(weekTimelinePager: self, didLongPressTimelineAt: date)
    }
    public func weekTimelineView(_ timelineView: WeekTimelineView, didTap event: EventView) {
        delegate?.weekTimelinePagerDidSelectEventView(event)
    }
    public func weekTimelineView(_ timelineView: WeekTimelineView, didLongPress event: EventView) {
        delegate?.weekTimelinePagerDidLongPressEventView(event)
    }

    @objc private func timelineDidLongPress(_ sender: UILongPressGestureRecognizer) {}
}
