import Foundation

enum WeekType: String, Codable, CaseIterable, Sendable {
    case all
    case odd
    case even

    var title: String {
        switch self {
        case .all: return "全部"
        case .odd: return "单周"
        case .even: return "双周"
        }
    }
}

struct Timetable: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var name: String
    var startDate: String
    var weeksCount: Int
    var isActive: Bool
    let createdAt: String
    var updatedAt: String
}

struct TimetablePeriod: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let timetableId: String
    let periodIndex: Int
    let startTime: String
    let endTime: String
}

struct PeriodTemplate: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var name: String
    var isDefault: Bool
    let createdAt: String
    var updatedAt: String
}

struct PeriodTemplateItem: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let templateId: String
    let periodIndex: Int
    let startTime: String
    let endTime: String
}

struct Course: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let timetableId: String
    var name: String
    var teacher: String?
    var location: String?
    var color: String?
    var note: String?
    let createdAt: String
    var updatedAt: String
}

struct CourseMeeting: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let courseId: String
    let weekday: Int
    let startWeek: Int
    let endWeek: Int
    let startPeriod: Int
    let endPeriod: Int
    let location: String?
    let weekType: WeekType
    let createdAt: String
}

struct CourseWithMeetings: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let timetableId: String
    var name: String
    var teacher: String?
    var location: String?
    var color: String?
    var note: String?
    let createdAt: String
    var updatedAt: String
    var meetings: [CourseMeeting]
}

struct CourseConflictWarning: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let courseId: String
    let courseName: String
    let weekday: Int
    let startPeriod: Int
    let endPeriod: Int
    let message: String

    init(courseId: String, courseName: String, weekday: Int, startPeriod: Int, endPeriod: Int, message: String) {
        id = createIdentifier(prefix: "warning")
        self.courseId = courseId
        self.courseName = courseName
        self.weekday = weekday
        self.startPeriod = startPeriod
        self.endPeriod = endPeriod
        self.message = message
    }
}

struct DayScheduleItem: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let courseId: String
    let name: String
    let teacher: String?
    let location: String?
    let color: String?
    let note: String?
    let weekday: Int
    let startWeek: Int
    let endWeek: Int
    let startPeriod: Int
    let endPeriod: Int
    let weekType: WeekType

    init(courseId: String, name: String, teacher: String?, location: String?, color: String?, note: String?, weekday: Int, startWeek: Int, endWeek: Int, startPeriod: Int, endPeriod: Int, weekType: WeekType) {
        id = [courseId, weekday, startWeek, endWeek, startPeriod, endPeriod, weekType.rawValue].map(String.init(describing:)).joined(separator: ":")
        self.courseId = courseId
        self.name = name
        self.teacher = teacher
        self.location = location
        self.color = color
        self.note = note
        self.weekday = weekday
        self.startWeek = startWeek
        self.endWeek = endWeek
        self.startPeriod = startPeriod
        self.endPeriod = endPeriod
        self.weekType = weekType
    }
}

struct WeekScheduleDay: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    let weekday: Int
    var items: [DayScheduleItem]

    init(weekday: Int, items: [DayScheduleItem] = []) {
        id = weekday
        self.weekday = weekday
        self.items = items
    }
}

struct WeekSchedule: Codable, Equatable, Sendable {
    let week: Int
    var days: [WeekScheduleDay]
}
