import UIKit

open class WeekViewController: UIViewController, EventDataSource, WeekViewDelegate {
    public lazy var weekView: WeekView = WeekView()
    public var dataSource: EventDataSource? {
        get { weekView.dataSource }
        set { weekView.dataSource = newValue }
    }

    public var delegate: WeekViewDelegate? {
        get { weekView.delegate }
        set { weekView.delegate = newValue }
    }

    public var calendar = Calendar.autoupdatingCurrent {
        didSet { weekView.calendar = calendar }
    }

    public var eventEditingSnappingBehavior: EventEditingSnappingBehavior {
        get { weekView.eventEditingSnappingBehavior }
        set { weekView.eventEditingSnappingBehavior = newValue }
    }

    open override func loadView() {
        view = weekView
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        edgesForExtendedLayout = []
        view.tintColor = SystemColors.systemRed
        dataSource = self
        delegate = self
        weekView.reloadData()

        let sizeClass = traitCollection.horizontalSizeClass
        configureWeekViewLayoutForHorizontalSizeClass(sizeClass)
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        weekView.scrollToFirstEventIfNeeded()
    }

    open override func willTransition(to newCollection: UITraitCollection, with coordinator: UIViewControllerTransitionCoordinator) {
        super.willTransition(to: newCollection, with: coordinator)
        configureWeekViewLayoutForHorizontalSizeClass(newCollection.horizontalSizeClass)
    }

    open func configureWeekViewLayoutForHorizontalSizeClass(_ sizeClass: UIUserInterfaceSizeClass) {
        weekView.transitionToHorizontalSizeClass(sizeClass)
    }

    open func move(to date: Date) {
        weekView.move(to: date)
    }

    open func reloadData() {
        weekView.reloadData()
    }

    open func updateStyle(_ newStyle: CalendarStyle) {
        weekView.updateStyle(newStyle)
    }

    open func eventsForDate(_ date: Date) -> [EventDescriptor] {
        [Event]()
    }

    open func dayViewDidSelectEventView(_ eventView: EventView) {}
    open func dayViewDidLongPressEventView(_ eventView: EventView) {}

    open func weekView(weekView: WeekView, didTapTimelineAt date: Date) {}
    open func weekViewDidBeginDragging(weekView: WeekView) {}
    open func weekViewDidTransitionCancel(weekView: WeekView) {}

    open func weekView(weekView: WeekView, willMoveTo date: Date) {}
    open func weekView(weekView: WeekView, didMoveTo date: Date) {}

    open func weekView(weekView: WeekView, didLongPressTimelineAt date: Date) {}
    open func weekView(weekView: WeekView, didUpdate event: EventDescriptor) {}

    open func create(event: EventDescriptor, animated: Bool = false) {
        weekView.create(event: event, animated: animated)
    }

    open func beginEditing(event: EventDescriptor, animated: Bool = false) {
        weekView.beginEditing(event: event, animated: animated)
    }

    open func endEventEditing() {
        weekView.endEventEditing()
    }
}
