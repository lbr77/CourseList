import Foundation

enum CourseWidgetSnapshotBuilder {
    static func make(repository: any TimetableRepositoryProtocol, now: Date = Date()) async -> CourseWidgetSnapshot {
        let today = emptyDaySummary(now: now)

        do {
            let timetables = try await repository.listTimetables()
            guard let timetable = resolveCurrentTimetable(on: now, timetables: timetables)
                ?? resolvePreferredTimetable(on: now, timetables: timetables)
            else {
                return CourseWidgetSnapshot(
                    state: .noTimetable,
                    generatedAt: nowISO8601String(),
                    timetable: nil,
                    today: today,
                    nextCourse: nil,
                    errorMessage: nil
                )
            }

            let currentWeek = clampWeek(getCurrentWeek(startDate: timetable.startDate, today: now), timetable: timetable)
            let weekSnapshot = try await repository.getWeekCourses(timetableId: timetable.id, week: currentWeek)
            let todayWeekday = mondayFirstWeekday(for: now)
            let timetableStartDay = parseDateInput(timetable.startDate).map { Calendar(identifier: .gregorian).startOfDay(for: $0) }

            let occurrences = weekSnapshot.items.compactMap {
                mapCourseSummary(
                    info: $0,
                    timetableStartDay: timetableStartDay,
                    now: now
                )
            }

            let todayCourses = occurrences
                .filter { $0.weekday == todayWeekday }
                .sorted(by: compareCourseSummary)
                .map(\.summary)

            let nextCourse = occurrences
                .filter { $0.startDate > now }
                .sorted { $0.startDate < $1.startDate }
                .first?
                .summary

            let state: CourseWidgetSnapshotState = weekSnapshot.items.isEmpty ? .noCourses : .ready

            return CourseWidgetSnapshot(
                state: state,
                generatedAt: nowISO8601String(),
                timetable: .init(
                    id: timetable.id,
                    name: timetable.name,
                    startDate: timetable.startDate,
                    weeksCount: timetable.weeksCount,
                    currentWeek: currentWeek
                ),
                today: .init(
                    weekday: todayWeekday,
                    date: formatDateInput(now),
                    courses: todayCourses
                ),
                nextCourse: nextCourse,
                errorMessage: nil
            )
        } catch {
            return CourseWidgetSnapshot(
                state: .unavailable,
                generatedAt: nowISO8601String(),
                timetable: nil,
                today: today,
                nextCourse: nil,
                errorMessage: error.localizedDescription
            )
        }
    }

    private struct MappedCourseSummary {
        let weekday: Int
        let startDate: Date
        let summary: CourseWidgetSnapshot.CourseSummary
    }

    private static func mapCourseSummary(
        info: WeekCourseInfo,
        timetableStartDay: Date?,
        now: Date
    ) -> MappedCourseSummary? {
        guard let timetableStartDay,
              let startDate = courseDate(
                  timetableStartDay: timetableStartDay,
                  week: info.week,
                  weekday: info.weekday,
                  time: info.startTime
              )
        else {
            return nil
        }

        let endDate = courseDate(
            timetableStartDay: timetableStartDay,
            week: info.week,
            weekday: info.weekday,
            time: info.endTime
        )
        let isOngoing = endDate.map { now >= startDate && now < $0 } ?? false

        let summary = CourseWidgetSnapshot.CourseSummary(
            id: info.id,
            courseId: info.courseId,
            name: info.courseName,
            location: normalizeOptionalText(info.location),
            color: info.color,
            startPeriod: info.startPeriod,
            endPeriod: info.endPeriod,
            startTime: info.startTime,
            endTime: info.endTime,
            date: formatDateInput(startDate),
            isOngoing: isOngoing
        )

        return MappedCourseSummary(
            weekday: info.weekday,
            startDate: startDate,
            summary: summary
        )
    }

    private static func courseDate(timetableStartDay: Date, week: Int, weekday: Int, time: String?) -> Date? {
        guard week >= 1, (1 ... 7).contains(weekday), let time else {
            return nil
        }

        let calendar = Calendar(identifier: .gregorian)
        guard let timeDate = parseTimeInput(time),
              let baseDate = calendar.date(byAdding: .day, value: (week - 1) * 7 + (weekday - 1), to: timetableStartDay)
        else {
            return nil
        }

        let timeComponents = calendar.dateComponents([.hour, .minute], from: timeDate)
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: baseDate)
        dateComponents.hour = timeComponents.hour
        dateComponents.minute = timeComponents.minute
        dateComponents.second = 0
        return calendar.date(from: dateComponents)
    }

    private static func mondayFirstWeekday(for date: Date) -> Int {
        let weekday = Calendar(identifier: .gregorian).component(.weekday, from: date)
        return ((weekday + 5) % 7) + 1
    }

    private static func compareCourseSummary(
        _ lhs: MappedCourseSummary,
        _ rhs: MappedCourseSummary
    ) -> Bool {
        if lhs.summary.startPeriod != rhs.summary.startPeriod {
            return lhs.summary.startPeriod < rhs.summary.startPeriod
        }
        if lhs.summary.endPeriod != rhs.summary.endPeriod {
            return lhs.summary.endPeriod < rhs.summary.endPeriod
        }
        return lhs.summary.name < rhs.summary.name
    }

    private static func emptyDaySummary(now: Date) -> CourseWidgetSnapshot.DaySummary {
        CourseWidgetSnapshot.DaySummary(
            weekday: mondayFirstWeekday(for: now),
            date: formatDateInput(now),
            courses: []
        )
    }
}
