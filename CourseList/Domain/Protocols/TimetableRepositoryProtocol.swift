import Foundation

protocol TimetableRepositoryProtocol: Sendable {
    func listTimetables() async throws -> [Timetable]
    func getActiveTimetable() async throws -> Timetable?
    func setActiveTimetable(id: String) async throws
    func createTimetable(input: CreateTimetableInput) async throws -> String
    func updateTimetable(input: UpdateTimetableInput) async throws
    func deleteTimetable(id: String) async throws
    func listPeriods(timetableId: String) async throws -> [TimetablePeriod]
    func replacePeriods(timetableId: String, periods: [TimetablePeriodInput]) async throws
    func listCourses(timetableId: String) async throws -> [CourseWithMeetings]
    func getCourse(courseId: String) async throws -> CourseWithMeetings?
    func saveCourse(input: SaveCourseInput) async throws -> String
    func deleteCourse(courseId: String) async throws
    func getWeekSchedule(timetableId: String, week: Int) async throws -> WeekSchedule
    func findCourseConflicts(input: SaveCourseInput) async throws -> [CourseConflictWarning]
    func importTimetableDraft(_ draft: ImportedTimetableDraft) async throws -> String
}
