import Foundation

enum TimetablePhase {
    case current
    case upcoming
    case past
    case unknown
}

struct TimetableVisibleHourRange: Equatable {
    static let `default` = TimetableVisibleHourRange(startHour: 0, endHour: 24)

    let startHour: Int
    let endHour: Int

    var span: Int {
        endHour - startHour
    }

    init(startHour: Int, endHour: Int) {
        let clampedStart = max(0, min(23, startHour))
        let clampedEnd = max(clampedStart + 1, min(24, endHour))
        self.startHour = clampedStart
        self.endHour = clampedEnd
    }
}

enum TimetableWeekStart: Int, CaseIterable {
    case sunday = 1
    case monday = 2

    static var `default`: TimetableWeekStart {
        Calendar.autoupdatingCurrent.firstWeekday == 1 ? .sunday : .monday
    }

    var label: String {
        switch self {
        case .sunday: "周天开始"
        case .monday: "周一开始"
        }
    }
}

extension Notification.Name {
    static let timetableAppearanceDidChange = Notification.Name("CourseList.timetableAppearanceDidChange")
}

func loadTimetableVisibleHourRange(defaults: UserDefaults = .standard) -> TimetableVisibleHourRange {
    let startKey = "timetable.visibleHourRange.startHour"
    let endKey = "timetable.visibleHourRange.endHour"

    let start = defaults.object(forKey: startKey) as? Int ?? TimetableVisibleHourRange.default.startHour
    let end = defaults.object(forKey: endKey) as? Int ?? TimetableVisibleHourRange.default.endHour
    return TimetableVisibleHourRange(startHour: start, endHour: end)
}

func saveTimetableVisibleHourRange(_ range: TimetableVisibleHourRange, defaults: UserDefaults = .standard) {
    let normalized = TimetableVisibleHourRange(startHour: range.startHour, endHour: range.endHour)
    defaults.set(normalized.startHour, forKey: "timetable.visibleHourRange.startHour")
    defaults.set(normalized.endHour, forKey: "timetable.visibleHourRange.endHour")
}

func loadTimetableWeekStart(defaults: UserDefaults = .standard) -> TimetableWeekStart {
    let key = "timetable.weekStart"
    guard let rawValue = defaults.object(forKey: key) as? Int else {
        return TimetableWeekStart.default
    }
    return TimetableWeekStart(rawValue: rawValue) ?? TimetableWeekStart.default
}

func saveTimetableWeekStart(_ weekStart: TimetableWeekStart, defaults: UserDefaults = .standard) {
    defaults.set(weekStart.rawValue, forKey: "timetable.weekStart")
}

func makeTimetableDisplayCalendar(weekStart: TimetableWeekStart = loadTimetableWeekStart()) -> Calendar {
    var calendar = Calendar.autoupdatingCurrent
    calendar.firstWeekday = weekStart.rawValue
    return calendar
}

func createIdentifier(prefix: String) -> String {
    let raw = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    return "\(prefix)_\(raw)"
}

func nowISO8601String() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: Date())
}

func formatDateInput(_ value: Date) -> String {
    let calendar = Calendar(identifier: .gregorian)
    let year = calendar.component(.year, from: value)
    let month = calendar.component(.month, from: value)
    let day = calendar.component(.day, from: value)
    return String(format: "%04d-%02d-%02d", year, month, day)
}

func formatTimeInput(_ value: Date) -> String {
    let calendar = Calendar(identifier: .gregorian)
    let hour = calendar.component(.hour, from: value)
    let minute = calendar.component(.minute, from: value)
    return String(format: "%02d:%02d", hour, minute)
}

func defaultTimetablePeriods() -> [TimetablePeriodInput] {
    [
        .init(periodIndex: 1, startTime: "08:00", endTime: "08:45"),
        .init(periodIndex: 2, startTime: "08:55", endTime: "09:40"),
    ]
}

func makeNextTimetablePeriodInput(after periods: [TimetablePeriodInput]) -> TimetablePeriodInput {
    let nextIndex = periods.count + 1

    guard let lastPeriod = periods.last,
          let lastStart = parseTimeInput(lastPeriod.startTime),
          let lastEnd = parseTimeInput(lastPeriod.endTime)
    else {
        return defaultTimetablePeriods().first ?? .init(periodIndex: nextIndex, startTime: "08:00", endTime: "08:45")
    }

    let defaultDuration: TimeInterval = 45 * 60
    let defaultBreak: TimeInterval = 10 * 60
    let measuredDuration = lastEnd.timeIntervalSince(lastStart)
    let lastDuration = measuredDuration > 0 ? measuredDuration : defaultDuration

    let breakDuration: TimeInterval
    if periods.count >= 2,
       let previousEnd = periods.dropLast().last.flatMap({ parseTimeInput($0.endTime) }) {
        breakDuration = max(0, lastStart.timeIntervalSince(previousEnd))
    } else {
        breakDuration = defaultBreak
    }

    let newStart = lastEnd.addingTimeInterval(breakDuration)
    let newEnd = newStart.addingTimeInterval(lastDuration)
    return .init(
        periodIndex: nextIndex,
        startTime: formatTimeInput(newStart),
        endTime: formatTimeInput(newEnd)
    )
}

func parseDateInput(_ value: String) -> Date? {
    guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
        return nil
    }

    let parts = value.split(separator: "-")
    guard parts.count == 3,
          let year = Int(parts[0]),
          let month = Int(parts[1]),
          let day = Int(parts[2])
    else {
        return nil
    }

    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = .gmt
    components.year = year
    components.month = month
    components.day = day
    components.hour = 12
    return components.date
}

func parseTimeInput(_ value: String) -> Date? {
    guard value.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil else {
        return nil
    }

    let parts = value.split(separator: ":")
    guard parts.count == 2,
          let hour = Int(parts[0]),
          let minute = Int(parts[1]),
          (0 ... 23).contains(hour),
          (0 ... 59).contains(minute)
    else {
        return nil
    }

    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = .current
    components.year = 2001
    components.month = 1
    components.day = 1
    components.hour = hour
    components.minute = minute
    return components.date
}

func normalizeOptionalText(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

func normalizeWhitespace(_ value: String?) -> String {
    value?.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

func getCurrentWeek(startDate: String, today: Date = Date()) -> Int {
    guard let start = parseDateInput(startDate) else { return 1 }
    let calendar = Calendar(identifier: .gregorian)
    let current = calendar.date(from: calendar.dateComponents([.year, .month, .day], from: today)) ?? today
    let diff = current.timeIntervalSince(start)
    return Int(floor(diff / (7 * 24 * 60 * 60))) + 1
}

func clampWeek(_ week: Int, timetable: Timetable) -> Int {
    max(1, min(week, timetable.weeksCount))
}

func timetableWeek(for date: Date, timetable: Timetable) -> Int? {
    guard let startDate = parseDateInput(timetable.startDate) else { return nil }
    let calendar = Calendar(identifier: .gregorian)
    let startDay = calendar.startOfDay(for: startDate)
    let targetDay = calendar.startOfDay(for: date)
    let diffDays = calendar.dateComponents([.day], from: startDay, to: targetDay).day ?? 0
    let week = Int(floor(Double(diffDays) / 7.0)) + 1
    guard week >= 1, week <= timetable.weeksCount else { return nil }
    return week
}

func weekMatchesType(_ week: Int, weekType: WeekType) -> Bool {
    switch weekType {
    case .all: true
    case .odd: week % 2 == 1
    case .even: week % 2 == 0
    }
}

func periodsOverlap(_ lhsStart: Int, _ lhsEnd: Int, _ rhsStart: Int, _ rhsEnd: Int) -> Bool {
    lhsStart <= rhsEnd && rhsStart <= lhsEnd
}

func weekRangesOverlap(
    firstStart: Int,
    firstEnd: Int,
    firstType: WeekType,
    secondStart: Int,
    secondEnd: Int,
    secondType: WeekType
) -> Bool {
    let start = max(firstStart, secondStart)
    let end = min(firstEnd, secondEnd)
    guard start <= end else { return false }

    for week in start ... end {
        if weekMatchesType(week, weekType: firstType) && weekMatchesType(week, weekType: secondType) {
            return true
        }
    }
    return false
}

func buildPeriodTimeLabel(_ periods: [TimetablePeriod], startPeriod: Int, endPeriod: Int) -> String {
    let start = periods.first(where: { $0.periodIndex == startPeriod })?.startTime
    let end = periods.first(where: { $0.periodIndex == endPeriod })?.endTime
    switch (start, end) {
    case let (start?, end?): return "\(start)-\(end)"
    case let (start?, nil): return start
    case let (nil, end?): return end
    default: return ""
    }
}

func resolveTimetablePhase(_ timetable: Timetable, on date: Date = Date()) -> TimetablePhase {
    guard let startDay = timetableStartDay(timetable) else { return .unknown }
    let calendar = Calendar(identifier: .gregorian)
    let targetDay = calendar.startOfDay(for: date)
    let endExclusiveDay = calendar.date(byAdding: .day, value: max(0, timetable.weeksCount) * 7, to: startDay) ?? startDay

    if targetDay < startDay {
        return .upcoming
    }
    if targetDay >= endExclusiveDay {
        return .past
    }
    return .current
}

func resolveCurrentTimetable(on date: Date = Date(), timetables: [Timetable]) -> Timetable? {
    timetables
        .filter { resolveTimetablePhase($0, on: date) == .current }
        .sorted { shouldDisplayTimetableBefore($0, $1, on: date) }
        .first
}

func resolvePreferredTimetable(on date: Date = Date(), timetables: [Timetable]) -> Timetable? {
    timetables
        .sorted { shouldDisplayTimetableBefore($0, $1, on: date) }
        .first
}

func shouldDisplayTimetableBefore(_ lhs: Timetable, _ rhs: Timetable, on date: Date = Date()) -> Bool {
    let lhsPhase = resolveTimetablePhase(lhs, on: date)
    let rhsPhase = resolveTimetablePhase(rhs, on: date)
    let lhsRank = timetablePhaseRank(lhsPhase)
    let rhsRank = timetablePhaseRank(rhsPhase)

    if lhsRank != rhsRank {
        return lhsRank < rhsRank
    }

    let lhsStart = timetableStartDay(lhs)
    let rhsStart = timetableStartDay(rhs)

    switch lhsPhase {
    case .current, .past:
        if let lhsStart, let rhsStart, lhsStart != rhsStart {
            return lhsStart > rhsStart
        }
    case .upcoming:
        if let lhsStart, let rhsStart, lhsStart != rhsStart {
            return lhsStart < rhsStart
        }
    case .unknown:
        break
    }

    if lhs.updatedAt != rhs.updatedAt {
        return lhs.updatedAt > rhs.updatedAt
    }
    return lhs.createdAt > rhs.createdAt
}

func buildTimetableSummary(_ timetable: Timetable, on date: Date = Date()) -> String {
    let status: String
    switch resolveTimetablePhase(timetable, on: date) {
    case .current:
        status = "进行中"
    case .upcoming:
        status = "未开始"
    case .past:
        status = "已结束"
    case .unknown:
        status = "日期异常"
    }

    return "\(status) · \(timetable.startDate) 开学 · \(timetable.weeksCount) 周"
}

private func timetablePhaseRank(_ phase: TimetablePhase) -> Int {
    switch phase {
    case .current:
        return 0
    case .upcoming:
        return 1
    case .past:
        return 2
    case .unknown:
        return 3
    }
}

private func timetableStartDay(_ timetable: Timetable) -> Date? {
    guard let startDate = parseDateInput(timetable.startDate) else { return nil }
    return Calendar(identifier: .gregorian).startOfDay(for: startDate)
}
