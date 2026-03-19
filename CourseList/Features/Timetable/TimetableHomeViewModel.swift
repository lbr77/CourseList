import Combine
import Foundation

@MainActor
final class TimetableHomeViewModel: ObservableObject {
    @Published var currentTimetable: Timetable?
    @Published var periods: [TimetablePeriod] = []
    @Published var courses: [CourseWithMeetings] = []
    @Published var schedule: WeekSchedule = WeekSchedule(week: 1, days: (1 ... 7).map { WeekScheduleDay(weekday: $0) })
    @Published private(set) var scheduleCache: [Int: WeekSchedule] = [:]
    @Published var currentWeek = 1
    @Published var errorMessage: String?
    @Published var isLoading = false

    private var repository: TimetableRepositoryProtocol?

    func bind(repository: TimetableRepositoryProtocol) {
        self.repository = repository
    }

    func reload() async {
        guard let repository else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            errorMessage = nil
            let timetables = try await repository.listTimetables()
            let timetable = resolveCurrentTimetable(timetables: timetables)
            currentTimetable = timetable

            guard let timetable else {
                periods = []
                courses = []
                scheduleCache = [:]
                schedule = emptySchedule(week: 1)
                return
            }

            currentWeek = clampWeek(getCurrentWeek(startDate: timetable.startDate), timetable: timetable)
            async let periodsTask = repository.listPeriods(timetableId: timetable.id)
            async let coursesTask = repository.listCourses(timetableId: timetable.id)
            periods = try await periodsTask
            courses = try await coursesTask
            scheduleCache = [:]
            await preloadWeeks(around: currentWeek)
            schedule = weekSchedule(for: currentWeek)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func changeWeek(delta: Int) async {
        guard let currentTimetable else { return }
        let targetWeek = clampWeek(currentWeek + delta, timetable: currentTimetable)
        await goToWeek(targetWeek)
    }

    func weekSchedule(for week: Int) -> WeekSchedule {
        scheduleCache[week] ?? emptySchedule(week: week)
    }

    func goToWeek(_ week: Int) async {
        guard let currentTimetable else { return }
        let targetWeek = clampWeek(week, timetable: currentTimetable)
        currentWeek = targetWeek
        await ensureWeekLoaded(targetWeek)
        schedule = weekSchedule(for: targetWeek)
        await preloadWeeks(around: targetWeek)
    }

    func goToDate(_ date: Date) async {
        guard let currentTimetable,
              let week = timetableWeek(for: date, timetable: currentTimetable)
        else {
            return
        }
        if week == currentWeek, schedule.week == week {
            return
        }

        await goToWeek(week)
    }

    private func ensureWeekLoaded(_ week: Int) async {
        guard scheduleCache[week] == nil,
              let repository,
              let currentTimetable
        else {
            return
        }

        do {
            let loaded = try await repository.getWeekSchedule(timetableId: currentTimetable.id, week: week)
            scheduleCache[week] = loaded
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func preloadWeeks(around centerWeek: Int) async {
        guard let currentTimetable else { return }
        let targetWeeks = [centerWeek - 1, centerWeek, centerWeek + 1]
            .map { clampWeek($0, timetable: currentTimetable) }

        for week in Array(Set(targetWeeks)).sorted() {
            await ensureWeekLoaded(week)
        }
    }

    private func emptySchedule(week: Int) -> WeekSchedule {
        WeekSchedule(week: week, days: (1 ... 7).map { WeekScheduleDay(weekday: $0) })
    }
}
