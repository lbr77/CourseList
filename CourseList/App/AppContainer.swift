import Combine
import Foundation

@MainActor
final class AppContainer: ObservableObject {
    @Published private(set) var repository: TimetableRepositoryProtocol?
    @Published private(set) var isBootstrapping = true
    @Published private(set) var bootstrapError: String?

    init(repository: TimetableRepositoryProtocol? = nil) {
        if let repository {
            self.repository = repository
            isBootstrapping = false
        } else {
            Task {
                await bootstrapRepository()
            }
        }
    }

    private func bootstrapRepository() async {
        do {
            let repository = try await Task.detached(priority: .userInitiated) { () -> TimetableRepositoryProtocol in
                let manager = try DatabaseManager()
                return TimetableRepository(manager: manager)
            }.value
            self.repository = repository
            bootstrapError = nil
        } catch {
            repository = InMemoryFallbackRepository()
            bootstrapError = "数据库初始化失败，已切换到内存模式：\(error.localizedDescription)"
        }
        isBootstrapping = false
    }
}

final class InMemoryFallbackRepository: TimetableRepositoryProtocol {
    private var timetables: [Timetable] = []
    private var periods: [String: [TimetablePeriod]] = [:]
    private var courses: [String: [CourseWithMeetings]] = [:]

    func listTimetables() async throws -> [Timetable] {
        timetables.sorted { shouldDisplayTimetableBefore($0, $1) }
    }

    func getActiveTimetable() async throws -> Timetable? {
        resolveCurrentTimetable(timetables: timetables)
    }

    func setActiveTimetable(id: String) async throws {
        for index in timetables.indices {
            timetables[index].isActive = timetables[index].id == id
        }
    }

    func createTimetable(input: CreateTimetableInput) async throws -> String {
        let id = createIdentifier(prefix: "timetable")
        let now = nowISO8601String()
        timetables.append(
            Timetable(
                id: id,
                name: input.name,
                termName: input.termName,
                startDate: input.startDate,
                weeksCount: input.weeksCount,
                isActive: false,
                createdAt: now,
                updatedAt: now
            )
        )
        periods[id] = input.periods.map {
            TimetablePeriod(
                id: createIdentifier(prefix: "period"),
                timetableId: id,
                periodIndex: $0.periodIndex,
                startTime: $0.startTime,
                endTime: $0.endTime
            )
        }
        courses[id] = []
        return id
    }

    func updateTimetable(input: UpdateTimetableInput) async throws {
        guard let index = timetables.firstIndex(where: { $0.id == input.id }) else { return }
        timetables[index].name = input.name
        timetables[index].termName = input.termName
        timetables[index].startDate = input.startDate
        timetables[index].weeksCount = input.weeksCount
        timetables[index].updatedAt = nowISO8601String()
    }

    func deleteTimetable(id: String) async throws {
        timetables.removeAll { $0.id == id }
        periods[id] = nil
        courses[id] = nil
    }

    func listPeriods(timetableId: String) async throws -> [TimetablePeriod] { periods[timetableId] ?? [] }

    func replacePeriods(timetableId: String, periods: [TimetablePeriodInput]) async throws {
        self.periods[timetableId] = periods.map {
            TimetablePeriod(
                id: createIdentifier(prefix: "period"),
                timetableId: timetableId,
                periodIndex: $0.periodIndex,
                startTime: $0.startTime,
                endTime: $0.endTime
            )
        }
    }

    func listCourses(timetableId: String) async throws -> [CourseWithMeetings] { courses[timetableId] ?? [] }

    func getCourse(courseId: String) async throws -> CourseWithMeetings? {
        courses.values.flatMap { $0 }.first(where: { $0.id == courseId })
    }

    func saveCourse(input: SaveCourseInput) async throws -> String {
        let courseId = input.id ?? createIdentifier(prefix: "course")
        let now = nowISO8601String()
        let meetings = input.meetings.map {
            CourseMeeting(
                id: createIdentifier(prefix: "meeting"),
                courseId: courseId,
                weekday: $0.weekday,
                startWeek: $0.startWeek,
                endWeek: $0.endWeek,
                startPeriod: $0.startPeriod,
                endPeriod: $0.endPeriod,
                location: $0.location,
                weekType: $0.weekType,
                createdAt: now
            )
        }
        var list = courses[input.timetableId] ?? []
        list.removeAll { $0.id == courseId }
        list.append(
            CourseWithMeetings(
                id: courseId,
                timetableId: input.timetableId,
                name: input.name,
                teacher: input.teacher,
                location: input.location,
                color: input.color,
                note: input.note,
                createdAt: now,
                updatedAt: now,
                meetings: meetings
            )
        )
        courses[input.timetableId] = list
        return courseId
    }

    func deleteCourse(courseId: String) async throws {
        for key in courses.keys {
            courses[key]?.removeAll { $0.id == courseId }
        }
    }

    func getWeekSchedule(timetableId: String, week: Int) async throws -> WeekSchedule {
        WeekScheduleBuilder.build(week: week, courses: courses[timetableId] ?? [])
    }

    func findCourseConflicts(input: SaveCourseInput) async throws -> [CourseConflictWarning] {
        ConflictDetector.findConflicts(input: input, courses: courses[input.timetableId] ?? [])
    }

    func importTimetableDraft(_ draft: ImportedTimetableDraft) async throws -> String {
        let id = try await createTimetable(
            input: .init(
                name: draft.name,
                termName: draft.termName,
                startDate: draft.startDate,
                weeksCount: draft.weeksCount,
                periods: draft.periods.map { .init(periodIndex: $0.periodIndex, startTime: $0.startTime, endTime: $0.endTime) }
            )
        )
        for course in draft.courses {
            _ = try await saveCourse(
                input: .init(
                    timetableId: id,
                    name: course.name,
                    teacher: course.teacher,
                    location: course.location,
                    color: course.color,
                    note: course.note,
                    meetings: course.meetings.map {
                        .init(
                            weekday: $0.weekday,
                            startWeek: $0.startWeek,
                            endWeek: $0.endWeek,
                            startPeriod: $0.startPeriod,
                            endPeriod: $0.endPeriod,
                            location: $0.location,
                            weekType: $0.weekType
                        )
                    }
                )
            )
        }
        return id
    }
}
