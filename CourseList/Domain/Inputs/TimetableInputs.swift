import Foundation

struct TimetablePeriodInput: Codable, Equatable, Sendable {
    var periodIndex: Int
    var startTime: String
    var endTime: String
}

struct CreateTimetableInput: Codable, Equatable, Sendable {
    var name: String
    var termName: String
    var startDate: String
    var weeksCount: Int
    var periods: [TimetablePeriodInput]
}

struct UpdateTimetableInput: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var termName: String
    var startDate: String
    var weeksCount: Int
}

struct CourseMeetingInput: Codable, Equatable, Sendable {
    var weekday: Int
    var startWeek: Int
    var endWeek: Int
    var startPeriod: Int
    var endPeriod: Int
    var location: String?
    var weekType: WeekType
}

struct SaveCourseInput: Codable, Equatable, Sendable {
    var id: String?
    var timetableId: String
    var name: String
    var teacher: String?
    var location: String?
    var color: String?
    var note: String?
    var meetings: [CourseMeetingInput]
}
