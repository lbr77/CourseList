import Foundation

protocol TimetableRepositoryProtocol: Sendable {
    func listTimetables() async throws -> [Timetable]
    func getActiveTimetable() async throws -> Timetable?
    func setActiveTimetable(id: String) async throws
    func createTimetable(input: CreateTimetableInput) async throws -> String
    func updateTimetable(input: UpdateTimetableInput) async throws
    func deleteTimetable(id: String) async throws
    func listPeriodTemplates() async throws -> [PeriodTemplate]
    func getPeriodTemplate(id: String) async throws -> PeriodTemplate?
    func getDefaultPeriodTemplate() async throws -> PeriodTemplate?
    func listPeriodTemplateItems(templateId: String) async throws -> [PeriodTemplateItem]
    func savePeriodTemplate(input: SavePeriodTemplateInput) async throws -> String
    func deletePeriodTemplate(id: String) async throws
    func setDefaultPeriodTemplate(id: String) async throws
    func listPeriods(timetableId: String) async throws -> [TimetablePeriod]
    func replacePeriods(timetableId: String, periods: [TimetablePeriodInput]) async throws
    func listCourses(timetableId: String) async throws -> [CourseWithMeetings]
    func getCourse(courseId: String) async throws -> CourseWithMeetings?
    func saveCourse(input: SaveCourseInput) async throws -> String
    func deleteCourse(courseId: String) async throws
    func getWeekSchedule(timetableId: String, week: Int) async throws -> WeekSchedule
    func getWeekCourses(timetableId: String, week: Int) async throws -> WeekCoursesSnapshot
    func findCourseConflicts(input: SaveCourseInput) async throws -> [CourseConflictWarning]
    func importTimetableDraft(_ draft: ImportedTimetableDraft) async throws -> String
}
