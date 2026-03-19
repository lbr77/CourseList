import SwiftUI
import UIKit

struct CalendarKitTimetableView: UIViewControllerRepresentable {
    let timetable: Timetable?
    let periods: [TimetablePeriod]
    let courses: [CourseWithMeetings]
    let schedule: WeekSchedule
    let scheduleCache: [Int: WeekSchedule]
    let onSelectCourse: (CourseWithMeetings, CoursePreviewSelectionContext) -> Void
    let onVisibleDateChange: (Date) -> Void
    let scrollToCurrentWeekToken: Int

    func makeUIViewController(context: Context) -> TimetableWeekViewController {
        let controller = TimetableWeekViewController()
        controller.onSelectCourseSelection = { selection in
            guard let course = courses.first(where: { $0.id == selection.courseId }) else { return }
            onSelectCourse(course, selection)
        }
        controller.onVisibleDateChange = onVisibleDateChange
        controller.scrollToCurrentWeekToken = scrollToCurrentWeekToken
        controller.apply(
            timetable: timetable,
            periods: periods,
            courses: courses,
            schedule: schedule,
            scheduleCache: scheduleCache
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: TimetableWeekViewController, context: Context) {
        uiViewController.onSelectCourseSelection = { selection in
            guard let course = courses.first(where: { $0.id == selection.courseId }) else { return }
            onSelectCourse(course, selection)
        }
        uiViewController.onVisibleDateChange = onVisibleDateChange
        uiViewController.scrollToCurrentWeekToken = scrollToCurrentWeekToken
        uiViewController.apply(
            timetable: timetable,
            periods: periods,
            courses: courses,
            schedule: schedule,
            scheduleCache: scheduleCache
        )
    }
}

final class TimetableWeekViewController: WeekViewController {
    var onSelectCourseSelection: ((CoursePreviewSelectionContext) -> Void)?
    var onVisibleDateChange: ((Date) -> Void)?
    var scrollToCurrentWeekToken: Int = 0 {
        didSet {
            guard scrollToCurrentWeekToken != lastHandledScrollToCurrentWeekToken else { return }
            lastHandledScrollToCurrentWeekToken = scrollToCurrentWeekToken
            guard isViewLoaded else { return }
            move(to: resolvedDisplayDate(preferred: Date()))
        }
    }

    private var timetable: Timetable?
    private var periods: [TimetablePeriod] = []
    private var courses: [CourseWithMeetings] = []
    private var schedule = WeekSchedule(week: 1, days: (1 ... 7).map { WeekScheduleDay(weekday: $0) })
    private var scheduleCache: [Int: WeekSchedule] = [:]
    private var lastAppliedSignature = ""
    private var lastResolvedHeight: CGFloat = 0
    private var lastResolvedVisibleHourRange = TimetableVisibleHourRange.default
    private var lastResolvedWeekStart = TimetableWeekStart.default
    private var lastHandledScrollToCurrentWeekToken = 0

    override func loadView() {
        let weekStart = loadTimetableWeekStart()
        lastResolvedWeekStart = weekStart
        weekView = WeekView(calendar: makeTimetableDisplayCalendar(weekStart: weekStart))
        view = weekView
    }

    func apply(
        timetable: Timetable?,
        periods: [TimetablePeriod],
        courses: [CourseWithMeetings],
        schedule: WeekSchedule,
        scheduleCache: [Int: WeekSchedule]
    ) {
        let previousTimetableId = self.timetable?.id
        let selectedDate = isViewLoaded ? weekView.state?.selectedDate : nil

        self.timetable = timetable
        self.periods = periods.sorted { $0.periodIndex < $1.periodIndex }
        self.courses = courses
        self.schedule = schedule
        self.scheduleCache = scheduleCache

        let signature = [
            timetable?.id ?? "no-timetable",
            timetable?.updatedAt ?? "no-updated-at",
            periodsSignature(self.periods),
            scheduleSignature(schedule),
            scheduleCacheSignature(scheduleCache)
        ].joined(separator: "|")

        guard signature != lastAppliedSignature else { return }
        lastAppliedSignature = signature

        if isViewLoaded {
            reloadData()

            if shouldResetVisibleDate(previousTimetableId: previousTimetableId, selectedDate: selectedDate) {
                move(to: resolvedDisplayDate(preferred: selectedDate))
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceDidChange),
            name: .timetableAppearanceDidChange,
            object: nil
        )

        applyResponsiveStyle(for: view.bounds.height)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyResponsiveStyle(for: view.bounds.height)
    }

    private func applyResponsiveStyle(for availableHeight: CGFloat) {
        guard availableHeight > 0 else { return }
        let visibleHourRange = loadTimetableVisibleHourRange()
        let didHeightChange = abs(availableHeight - lastResolvedHeight) > 0.5
        let didVisibleRangeChange = visibleHourRange != lastResolvedVisibleHourRange
        guard didHeightChange || didVisibleRangeChange else { return }

        lastResolvedHeight = availableHeight
        lastResolvedVisibleHourRange = visibleHourRange

        let timelineHeight = max(0, Double(availableHeight) - weekView.headerHeight)
        let verticalInset = TimetableCalendarLayout.timelineVerticalInset
        let verticalDiff = max(
            TimetableCalendarLayout.minimumVerticalDiff,
            (timelineHeight - verticalInset * 2) / Double(visibleHourRange.span)
        )

        var style = CalendarStyle()
        style.timeline.leadingInset = TimetableCalendarLayout.timeAxisLeadingInset
        style.timeline.verticalInset = verticalInset
        style.timeline.verticalDiff = verticalDiff
        style.timeline.visibleStartHour = visibleHourRange.startHour
        style.timeline.visibleEndHour = visibleHourRange.endHour
        style.timeline.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        style.timeline.timeIndicator.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        updateStyle(style)
    }

    @objc private func appearanceDidChange() {
        updateDisplayCalendarIfNeeded()
        applyResponsiveStyle(for: view.bounds.height)
    }

    private func updateDisplayCalendarIfNeeded() {
        let weekStart = loadTimetableWeekStart()
        guard weekStart != lastResolvedWeekStart else { return }
        lastResolvedWeekStart = weekStart

        guard isViewLoaded else { return }
        let selectedDate = weekView.state?.selectedDate ?? Date()

        weekView = WeekView(calendar: makeTimetableDisplayCalendar(weekStart: weekStart))
        view = weekView
        view.backgroundColor = .clear
        dataSource = self
        delegate = self
        lastResolvedHeight = 0
        lastResolvedVisibleHourRange = TimetableVisibleHourRange.default
        reloadData()
        move(to: resolvedDisplayDate(preferred: selectedDate))
        onVisibleDateChange?(weekView.state?.selectedDate ?? Date())
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyResponsiveStyle(for: view.bounds.height)
        move(to: resolvedDisplayDate(preferred: weekView.state?.selectedDate ?? Date()))
        onVisibleDateChange?(weekView.state?.selectedDate ?? Date())
    }

    override func weekView(weekView: WeekView, didMoveTo date: Date) {
        onVisibleDateChange?(date)
    }

    override func eventsForDate(_ date: Date) -> [EventDescriptor] {
        guard timetable != nil else { return [] }

        let weekSchedule = scheduleForDate(date)
        let weekday = weekdayIndex(for: date)
        let dayOnly = startOfDay(for: date)
        let items = weekSchedule.days.first(where: { $0.weekday == weekday })?.items ?? []

        return items.compactMap { item in
            let interval = meetingDateInterval(startPeriod: item.startPeriod, endPeriod: item.endPeriod, on: dayOnly)
            let event = Event()
            event.dateInterval = interval
            event.userInfo = CoursePreviewSelectionContext(
                courseId: item.courseId,
                week: weekSchedule.week,
                weekday: weekday,
                startPeriod: item.startPeriod,
                endPeriod: item.endPeriod,
                startTime: periods.first(where: { $0.periodIndex == item.startPeriod })?.startTime,
                endTime: periods.first(where: { $0.periodIndex == item.endPeriod })?.endTime,
                location: item.location
            )
            if let color = UIColor(hex: item.color) {
                event.color = color
            }
            event.text = eventText(for: item, interval: interval)
            return event
        }
    }

    override func dayViewDidSelectEventView(_ eventView: EventView) {
        guard let event = eventView.descriptor as? Event,
              let selection = event.userInfo as? CoursePreviewSelectionContext else { return }
        onSelectCourseSelection?(selection)
    }

    private func shouldResetVisibleDate(previousTimetableId: String?, selectedDate: Date?) -> Bool {
        guard let timetable else { return false }
        guard previousTimetableId == timetable.id else { return true }
        guard let selectedDate else { return true }
        return timetableWeek(for: selectedDate, timetable: timetable) == nil
    }

    private func resolvedDisplayDate(preferred date: Date?) -> Date {
        guard let timetable else { return date ?? Date() }

        if let date, timetableWeek(for: date, timetable: timetable) != nil {
            return date
        }

        let today = Date()
        if timetableWeek(for: today, timetable: timetable) != nil {
            return today
        }

        if let startDate = parseDateInput(timetable.startDate) {
            return startDate
        }

        return date ?? today
    }

    private func periodsSignature(_ periods: [TimetablePeriod]) -> String {
        periods
            .map { "\($0.id):\($0.periodIndex):\($0.startTime):\($0.endTime)" }
            .joined(separator: ",")
    }

    private func scheduleSignature(_ schedule: WeekSchedule) -> String {
        let daysSignature = schedule.days
            .map { day in
                let items = day.items
                    .map {
                        "\($0.id):\($0.courseId):\($0.startPeriod):\($0.endPeriod):\($0.location ?? "")"
                    }
                    .joined(separator: ";")
                return "\(day.weekday)[\(items)]"
            }
            .joined(separator: "|")
        return "\(schedule.week){\(daysSignature)}"
    }

    private func scheduleCacheSignature(_ cache: [Int: WeekSchedule]) -> String {
        cache.keys
            .sorted()
            .compactMap { week in
                guard let schedule = cache[week] else { return nil }
                return scheduleSignature(schedule)
            }
            .joined(separator: "#")
    }

    private func scheduleForDate(_ date: Date) -> WeekSchedule {
        guard let timetable,
              let week = timetableWeek(for: date, timetable: timetable)
        else {
            return schedule
        }
        if let cached = scheduleCache[week] {
            return cached
        }
        if schedule.week == week {
            return schedule
        }
        return emptySchedule(week: week)
    }

    private func emptySchedule(week: Int) -> WeekSchedule {
        WeekSchedule(week: week, days: (1 ... 7).map { WeekScheduleDay(weekday: $0) })
    }

    private func weekdayIndex(for date: Date) -> Int {
        let weekday = displayCalendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    private func startOfDay(for date: Date) -> Date {
        displayCalendar.startOfDay(for: date)
    }

    private func meetingDateInterval(startPeriod: Int, endPeriod: Int, on day: Date) -> DateInterval {
        let start = dayTime(for: day, periodIndex: startPeriod, useEndTime: false, fallbackHour: 8 + max(0, startPeriod - 1))
        let end = dayTime(for: day, periodIndex: endPeriod, useEndTime: true, fallbackHour: 9 + max(0, endPeriod - 1))
        let safeEnd = end > start ? end : start.addingTimeInterval(45 * 60)
        return DateInterval(start: start, end: safeEnd)
    }

    private func dayTime(for day: Date, periodIndex: Int, useEndTime: Bool, fallbackHour: Int) -> Date {
        let timeString = periods.first(where: { $0.periodIndex == periodIndex }).map { useEndTime ? $0.endTime : $0.startTime }
        if let timeString, let resolved = combine(day: day, timeString: timeString) {
            return resolved
        }
        var components = displayCalendar.dateComponents([.year, .month, .day], from: day)
        components.timeZone = displayCalendar.timeZone
        components.hour = fallbackHour
        components.minute = 0
        return displayCalendar.date(from: components) ?? day
    }

    private func combine(day: Date, timeString: String) -> Date? {
        let parts = timeString.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        var components = displayCalendar.dateComponents([.year, .month, .day], from: day)
        components.timeZone = displayCalendar.timeZone
        components.hour = hour
        components.minute = minute
        return displayCalendar.date(from: components)
    }

    private func eventText(for item: DayScheduleItem, interval: DateInterval) -> String {
        var lines = [item.name]
        if let location = item.location, !location.isEmpty {
            lines.append(location)
        }
        lines.append("\(timeString(from: interval.start)) - \(timeString(from: interval.end))")
        return lines.joined(separator: "\n")
    }

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = displayCalendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private var displayCalendar: Calendar {
        weekView.calendar
    }
}

private extension UIColor {
    convenience init?(hex: String?) {
        guard let hex else { return nil }
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6 || cleaned.count == 8, let value = UInt64(cleaned, radix: 16) else { return nil }
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
        if cleaned.count == 8 {
            red = CGFloat((value & 0xFF00_0000) >> 24) / 255
            green = CGFloat((value & 0x00FF_0000) >> 16) / 255
            blue = CGFloat((value & 0x0000_FF00) >> 8) / 255
            alpha = CGFloat(value & 0x0000_00FF) / 255
        } else {
            red = CGFloat((value & 0xFF0000) >> 16) / 255
            green = CGFloat((value & 0x00FF00) >> 8) / 255
            blue = CGFloat(value & 0x0000FF) / 255
            alpha = 1
        }
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
