import UIKit

public protocol WeekTimelineViewDelegate: AnyObject {
    func weekTimelineView(_ timelineView: WeekTimelineView, didTapAt date: Date)
    func weekTimelineView(_ timelineView: WeekTimelineView, didLongPressAt date: Date)
    func weekTimelineView(_ timelineView: WeekTimelineView, didTap event: EventView)
    func weekTimelineView(_ timelineView: WeekTimelineView, didLongPress event: EventView)
}

public final class WeekTimelineView: UIView {
    public weak var delegate: WeekTimelineViewDelegate?

    public var weekStartDate = Date().dateOnly(calendar: .autoupdatingCurrent) {
        didSet { setNeedsLayout(); setNeedsDisplay() }
    }

    public var selectedDate = Date().dateOnly(calendar: .autoupdatingCurrent) {
        didSet { setNeedsDisplay() }
    }

    private var currentTime: Date { Date() }
    private var removedHourIndex: Int = -1
    private var eventViews = [EventView]()
    public private(set) var regularLayoutAttributes = [EventLayoutAttributes]()
    public var layoutAttributes: [EventLayoutAttributes] = [] {
        didSet {
            regularLayoutAttributes = layoutAttributes.filter { !$0.descriptor.isAllDay }
            recalculateEventLayout()
            prepareEventViews()
            setNeedsLayout()
            setNeedsDisplay()
        }
    }

    private var pool = ReusePool<EventView>()
    public var firstEventYPosition: Double? {
        let first = regularLayoutAttributes.sorted { $0.frame.origin.y < $1.frame.origin.y }.first
        guard let firstEvent = first else { return nil }
        return max(firstEvent.frame.origin.y, style.verticalInset)
    }

    private lazy var nowLine: CurrentTimeIndicator = CurrentTimeIndicator()
    public var style = TimelineStyle()
    public var calendar: Calendar = Calendar.autoupdatingCurrent {
        didSet {
            eventEditingSnappingBehavior.calendar = calendar
            nowLine.calendar = calendar
            regenerateTimeStrings()
            setNeedsLayout()
            setNeedsDisplay()
        }
    }

    public var fullHeight: Double {
        style.verticalInset * 2 + style.verticalDiff * 24
    }

    public var columnWidth: Double {
        max(0, bounds.width - style.leadingInset - style.trailingInset) / 7
    }

    public private(set) var is24hClock = true {
        didSet { setNeedsDisplay() }
    }

    public var eventEditingSnappingBehavior: EventEditingSnappingBehavior = SnapTo15MinuteIntervals() {
        didSet { eventEditingSnappingBehavior.calendar = calendar }
    }

    private var times: [String] { is24hClock ? _24hTimes : _12hTimes }
    private lazy var _12hTimes: [String] = TimeStringsFactory(calendar).make12hStrings()
    private lazy var _24hTimes: [String] = TimeStringsFactory(calendar).make24hStrings()

    public lazy private(set) var longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPress(_:)))
    public lazy private(set) var tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))

    private weak var timer: Timer?

    public init() {
        super.init(frame: .zero)
        frame.size.height = fullHeight
        configure()
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required public init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        contentScaleFactor = 1
        layer.contentsScale = 1
        contentMode = .redraw
        backgroundColor = .white
        addSubview(nowLine)
        configureTimer()
        addGestureRecognizer(longPressGestureRecognizer)
        addGestureRecognizer(tapGestureRecognizer)
    }

    private func configureTimer() {
        invalidateTimer()
        let date = Date()
        var components = calendar.dateComponents(Set([.era, .year, .month, .day, .hour, .minute]), from: date)
        components.minute! += 1
        let timerDate = calendar.date(from: components)!
        let newTimer = Timer(fireAt: timerDate, interval: 60, target: self, selector: #selector(timerDidFire(_:)), userInfo: nil, repeats: true)
        RunLoop.current.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func invalidateTimer() {
        timer?.invalidate()
    }

    @objc private func timerDidFire(_ sender: Timer) {
        layoutNowLine()
        if containsToday {
            var hourToRemoveIndex = -1
            let minute = component(.minute, from: currentTime)
            let hour = component(.hour, from: currentTime)
            if minute > 39 {
                hourToRemoveIndex = hour + 1
            } else if minute < 21 {
                hourToRemoveIndex = hour
            }
            if hourToRemoveIndex != removedHourIndex { setNeedsDisplay() }
        }
    }

    private var containsToday: Bool {
        weekDates().contains { calendar.isDate($0, inSameDayAs: Date()) }
    }

    private func regenerateTimeStrings() {
        let factory = TimeStringsFactory(calendar)
        _12hTimes = factory.make12hStrings()
        _24hTimes = factory.make24hStrings()
    }

    @objc private func longPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
        if gestureRecognizer.state == .began {
            let pressedLocation = gestureRecognizer.location(in: self)
            if let eventView = findEventView(at: pressedLocation) {
                delegate?.weekTimelineView(self, didLongPress: eventView)
            } else {
                delegate?.weekTimelineView(self, didLongPressAt: pointToDate(pressedLocation))
            }
        }
    }

    @objc private func tap(_ sender: UITapGestureRecognizer) {
        let pressedLocation = sender.location(in: self)
        if let eventView = findEventView(at: pressedLocation) {
            delegate?.weekTimelineView(self, didTap: eventView)
        } else {
            delegate?.weekTimelineView(self, didTapAt: pointToDate(pressedLocation))
        }
    }

    private func findEventView(at point: CGPoint) -> EventView? {
        for eventView in eventViews where eventView.frame.contains(point) {
            return eventView
        }
        return nil
    }

    public func updateStyle(_ newStyle: TimelineStyle) {
        style = newStyle
        nowLine.leadingInset = style.leadingInset
        nowLine.trailingInset = style.trailingInset
        nowLine.updateStyle(style.timeIndicator)
        switch style.dateStyle {
        case .twelveHour: is24hClock = false
        case .twentyFourHour: is24hClock = true
        default: is24hClock = calendar.locale?.uses24hClock ?? Locale.autoupdatingCurrent.uses24hClock
        }
        backgroundColor = style.backgroundColor
        setNeedsDisplay()
    }

    private func timeLabelRect(centeredAt lineY: Double, font: UIFont) -> CGRect {
        let horizontalPadding: Double = 0
        let labelWidth = max(0, style.leadingInset)
        let labelHeight = ceil(font.lineHeight)

        return CGRect(
            x: horizontalPadding,
            y: lineY - labelHeight / 2,
            width: labelWidth,
            height: labelHeight
        )
    }

    public var accentedDate: Date?

    override public func draw(_ rect: CGRect) {
        super.draw(rect)
        removedHourIndex = -1
        var accentedHour = -1
        var accentedMinute = -1
        if let accentedDate {
            accentedHour = eventEditingSnappingBehavior.accentedHour(for: accentedDate)
            accentedMinute = eventEditingSnappingBehavior.accentedMinute(for: accentedDate)
        }
        if containsToday {
            let minute = component(.minute, from: currentTime)
            let hour = component(.hour, from: currentTime)
            if minute > 39 { removedHourIndex = hour + 1 }
            else if minute < 21 { removedHourIndex = hour }
        }

        drawSelectedDayBackground()

        let mutableParagraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        mutableParagraphStyle.lineBreakMode = .byWordWrapping
        mutableParagraphStyle.alignment = .center
        let paragraphStyle = mutableParagraphStyle.copy() as! NSParagraphStyle
        let attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle,
            .foregroundColor: style.timeColor,
            .font: style.font
        ]
        let scale = UIScreen.main.scale
        let lineHeight = 1 / scale
        let center: Double = Int(scale) % 2 == 0 ? 1 / (scale * 2) : 0
        let offset = 0.5 - center
        let context = UIGraphicsGetCurrentContext()

        for (hour, time) in times.enumerated() {
            let hourFloat = Double(hour)
            context?.saveGState()
            context?.setStrokeColor(style.separatorColor.cgColor)
            context?.setLineWidth(lineHeight)
            let y = style.verticalInset + hourFloat * style.verticalDiff + offset
            context?.beginPath()
            context?.move(to: CGPoint(x: style.leadingInset, y: y))
            context?.addLine(to: CGPoint(x: bounds.width - style.trailingInset, y: y))
            context?.strokePath()
            context?.restoreGState()

            if hour == removedHourIndex { continue }
            let timeRect = timeLabelRect(centeredAt: y, font: style.font)
            NSString(string: time).draw(in: timeRect, withAttributes: attributes)

            if accentedMinute != 0, hour == accentedHour {
                let accentedY = y + style.verticalDiff * (Double(accentedMinute) / 60)
                let timeRect = timeLabelRect(centeredAt: accentedY, font: style.font)
                NSString(string: ":\(accentedMinute)").draw(in: timeRect, withAttributes: attributes)
            }
        }

        drawVerticalSeparators()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        recalculateEventLayout()
        layoutEvents()
        layoutNowLine()
    }

    private func drawSelectedDayBackground() {
        guard containsToday else { return }
        let dates = weekDates()
        guard let selectedIndex = dates.firstIndex(where: { calendar.isDate($0, inSameDayAs: selectedDate) }) else { return }
        let rect = CGRect(x: style.leadingInset + Double(selectedIndex) * columnWidth, y: 0, width: columnWidth, height: bounds.height)
        UIColor.systemFill.withAlphaComponent(0.35).setFill()
        UIBezierPath(rect: rect).fill()
    }

    private func drawVerticalSeparators() {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.setStrokeColor(style.separatorColor.cgColor)
        context.setLineWidth(1 / UIScreen.main.scale)
        for index in 0 ... 7 {
            let x = style.leadingInset + Double(index) * columnWidth
            context.beginPath()
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: bounds.height))
            context.strokePath()
        }
        context.restoreGState()
    }

    private func layoutNowLine() {
        let today = Date()
        guard datesContain(today) else {
            nowLine.alpha = 0
            return
        }
        bringSubviewToFront(nowLine)
        nowLine.alpha = 1
        let size = CGSize(width: bounds.size.width, height: 20)
        nowLine.date = currentTime
        nowLine.frame = CGRect(origin: .zero, size: size)
        nowLine.center.y = dateToY(currentTime)
    }

    private func layoutEvents() {
        guard !eventViews.isEmpty else { return }
        for (idx, attributes) in regularLayoutAttributes.enumerated() {
            let descriptor = attributes.descriptor
            let eventView = eventViews[idx]
            eventView.frame = CGRect(x: attributes.frame.minX, y: attributes.frame.minY, width: attributes.frame.width - style.eventGap, height: attributes.frame.height - style.eventGap)
            eventView.updateWithDescriptor(event: descriptor)
        }
    }

    private func recalculateEventLayout() {
        let dates = weekDates()
        var frames: [EventLayoutAttributes] = []
        for (dayIndex, day) in dates.enumerated() {
            let dayEvents = regularLayoutAttributes.filter { calendar.isDate($0.descriptor.dateInterval.start, inSameDayAs: day) || dayInterval(for: day).intersects($0.descriptor.dateInterval) }
            let sortedEvents = dayEvents.sorted { $0.descriptor.dateInterval.start < $1.descriptor.dateInterval.start }
            var groups = [[EventLayoutAttributes]]()
            var overlapping = [EventLayoutAttributes]()
            for event in sortedEvents {
                if overlapping.isEmpty {
                    overlapping.append(event)
                    continue
                }
                let longestEvent = overlapping.max { lhs, rhs in
                    lhs.descriptor.dateInterval.duration < rhs.descriptor.dateInterval.duration
                }!
                let lastEvent = overlapping.last!
                if (longestEvent.descriptor.dateInterval.intersects(event.descriptor.dateInterval) && (longestEvent.descriptor.dateInterval.end != event.descriptor.dateInterval.start || style.eventGap <= 0.0)) ||
                    (lastEvent.descriptor.dateInterval.intersects(event.descriptor.dateInterval) && (lastEvent.descriptor.dateInterval.end != event.descriptor.dateInterval.start || style.eventGap <= 0.0)) {
                    overlapping.append(event)
                    continue
                }
                groups.append(overlapping)
                overlapping = [event]
            }
            groups.append(overlapping)
            overlapping.removeAll()

            for group in groups where !group.isEmpty {
                let totalCount = Double(group.count)
                for (index, event) in group.enumerated() {
                    let startY = dateToY(event.descriptor.dateInterval.start)
                    let endY = dateToY(event.descriptor.dateInterval.end)
                    let x = style.leadingInset + Double(dayIndex) * columnWidth + Double(index) / totalCount * columnWidth
                    let equalWidth = columnWidth / totalCount
                    event.frame = CGRect(x: x, y: startY, width: equalWidth, height: endY - startY)
                    frames.append(event)
                }
            }
        }
        regularLayoutAttributes = frames
    }

    private func prepareEventViews() {
        pool.enqueue(views: eventViews)
        eventViews.removeAll()
        for _ in regularLayoutAttributes {
            let newView = pool.dequeue()
            if newView.superview == nil { addSubview(newView) }
            eventViews.append(newView)
        }
    }

    public func prepareForReuse() {
        pool.enqueue(views: eventViews)
        eventViews.removeAll()
        setNeedsDisplay()
    }

    public func dateToY(_ date: Date) -> Double {
        let provisionedDate = date.dateOnly(calendar: calendar)
        let timelineDate = selectedDate.dateOnly(calendar: calendar)
        var dayOffset: Double = 0
        if provisionedDate > timelineDate { dayOffset += 1 }
        else if provisionedDate < timelineDate { dayOffset -= 1 }
        let fullTimelineHeight = 24 * style.verticalDiff
        let hour = component(.hour, from: date)
        let minute = component(.minute, from: date)
        let hourY = Double(hour) * style.verticalDiff + style.verticalInset
        let minuteY = Double(minute) * style.verticalDiff / 60
        return hourY + minuteY + fullTimelineHeight * dayOffset
    }

    public func yToDate(_ y: Double, for date: Date) -> Date {
        let timeValue = y - style.verticalInset
        var hour = Int(timeValue / style.verticalDiff)
        let fullHourPoints = Double(hour) * style.verticalDiff
        let minuteDiff = timeValue - fullHourPoints
        let minute = Int(minuteDiff / style.verticalDiff * 60)
        var dayOffset = 0
        if hour > 23 { dayOffset += 1; hour -= 24 }
        else if hour < 0 { dayOffset -= 1; hour += 24 }
        let offsetDate = calendar.date(byAdding: DateComponents(day: dayOffset), to: date)!
        return calendar.date(bySettingHour: hour, minute: minute.clamped(to: 0...59), second: 0, of: offsetDate)!
    }

    private func pointToDate(_ point: CGPoint) -> Date {
        let column = max(0, min(6, Int((point.x - style.leadingInset) / columnWidth)))
        let date = weekDates()[column]
        return yToDate(Double(point.y), for: date)
    }

    private func weekDates() -> [Date] {
        (0 ..< 7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStartDate.dateOnly(calendar: calendar)) }
    }

    private func dayInterval(for day: Date) -> DateInterval {
        let start = day.dateOnly(calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return DateInterval(start: start, end: end)
    }

    private func datesContain(_ date: Date) -> Bool {
        weekDates().contains { calendar.isDate($0, inSameDayAs: date) }
    }

    private func component(_ component: Calendar.Component, from date: Date) -> Int {
        calendar.component(component, from: date)
    }

    public override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)
        if newSuperview != nil { configureTimer() } else { invalidateTimer() }
    }
}
