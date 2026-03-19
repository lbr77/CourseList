import UIKit

public final class DayHeaderView: UIView, DaySelectorDelegate, DayViewStateUpdating {
    public private(set) var daysInWeek = 7
    public let calendar: Calendar

    private var style = DayHeaderStyle()
    private var currentSizeClass = UIUserInterfaceSizeClass.compact
    public var onSelectDate: ((Date) -> Void)?

    public weak var state: DayViewState? {
        willSet {
            state?.unsubscribe(client: self)
        }
        didSet {
            state?.subscribe(client: self)
            syncSelector(with: state?.selectedDate ?? Date())
        }
    }

    private var daySymbolsViewHeight: Double = 20
    private var pagingScrollViewHeight: Double = 40

    private let daySymbolsView: DaySymbolsView
    private let daySelector: DaySelector
    private let monthLabel = UILabel()
    private lazy var separator: UIView = {
        let separator = UIView()
        separator.backgroundColor = SystemColors.systemSeparator
        return separator
    }()

    public init(calendar: Calendar) {
        self.calendar = calendar
        self.daySymbolsView = DaySymbolsView(calendar: calendar)
        self.daySelector = DaySelector()
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        daySelector.calendar = calendar
        daySelector.delegate = self
        daySelector.transitionToHorizontalSizeClass(currentSizeClass)
        monthLabel.textAlignment = .center
        [monthLabel, daySymbolsView, daySelector, separator].forEach(addSubview)
        backgroundColor = style.backgroundColor
        syncSelector(with: Date())
    }

    private func beginningOfWeek(_ date: Date) -> Date {
        let weekOfYear = calendar.component(.weekOfYear, from: date)
        let yearForWeekOfYear = calendar.component(.yearForWeekOfYear, from: date)
        return calendar.date(from: DateComponents(calendar: calendar,
                                                  weekday: calendar.firstWeekday,
                                                  weekOfYear: weekOfYear,
                                                  yearForWeekOfYear: yearForWeekOfYear))!
    }

    public func setDisplayedDate(_ date: Date) {
        syncSelector(with: date)
    }

    private func syncSelector(with date: Date) {
        let normalizedDate = date.dateOnly(calendar: calendar)
        let weekStartDate = beginningOfWeek(normalizedDate)
        daySelector.startDate = weekStartDate

        if weekContainsToday(weekStartDate) {
            daySelector.selectedDate = normalizedDate
        } else {
            daySelector.selectedIndex = -1
        }

        monthLabel.text = monthString(for: normalizedDate)
    }

    private func weekContainsToday(_ weekStartDate: Date) -> Bool {
        let todayWeekStart = beginningOfWeek(Date()).dateOnly(calendar: calendar)
        return calendar.isDate(weekStartDate.dateOnly(calendar: calendar), inSameDayAs: todayWeekStart)
    }

    private func monthString(for date: Date) -> String {
        "\(calendar.component(.month, from: date))月"
    }

    public func updateStyle(_ newStyle: DayHeaderStyle) {
        style = newStyle
        daySymbolsView.updateStyle(style.daySymbols)
        daySelector.updateStyle(style.daySelector)
        monthLabel.font = style.swipeLabel.font
        monthLabel.textColor = style.swipeLabel.textColor
        backgroundColor = style.backgroundColor
        separator.backgroundColor = style.separatorColor
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        let gridX = style.leadingInset
        let gridWidth = max(0, bounds.width - style.leadingInset - style.trailingInset)
        let monthHeight = daySymbolsViewHeight + pagingScrollViewHeight

        monthLabel.frame = CGRect(x: 0,
                                  y: 0,
                                  width: gridX,
                                  height: monthHeight)

        daySymbolsView.frame = CGRect(x: gridX,
                                      y: 0,
                                      width: gridWidth,
                                      height: daySymbolsViewHeight)
        daySelector.frame = CGRect(x: gridX,
                                   y: daySymbolsViewHeight,
                                   width: gridWidth,
                                   height: pagingScrollViewHeight)

        let separatorHeight = 1 / UIScreen.main.scale
        separator.frame = CGRect(x: 0,
                                 y: bounds.height - separatorHeight,
                                 width: bounds.width,
                                 height: separatorHeight)
    }

    public func transitionToHorizontalSizeClass(_ sizeClass: UIUserInterfaceSizeClass) {
        currentSizeClass = sizeClass
        daySymbolsView.isHidden = sizeClass == .regular
        daySelector.transitionToHorizontalSizeClass(sizeClass)
    }

    public func dateSelectorDidSelectDate(_ date: Date) {
        if let onSelectDate {
            onSelectDate(date)
        } else {
            state?.move(to: date)
        }
    }

    public func move(from oldDate: Date, to newDate: Date) {
        guard oldDate.dateOnly(calendar: calendar) != newDate.dateOnly(calendar: calendar) else { return }
        syncSelector(with: newDate)
    }
}
