import Foundation

enum TimetablePhase {
    case current
    case upcoming
    case past
    case unknown
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
    components.timeZone = .gmt
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
        status = timetable.termName.isEmpty ? "日期异常" : timetable.termName
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
