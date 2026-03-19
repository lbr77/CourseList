import Foundation

enum CourseWidgetSnapshotState: String, Codable {
    case ready
    case noTimetable
    case noCourses
    case unavailable
}

struct CourseWidgetSnapshot: Codable {
    struct TimetableSummary: Codable {
        let id: String
        let name: String
        let startDate: String
        let weeksCount: Int
        let currentWeek: Int
    }

    struct DaySummary: Codable {
        let weekday: Int
        let date: String
        let courses: [CourseSummary]
    }

    struct CourseSummary: Codable {
        let id: String
        let courseId: String
        let name: String
        let location: String?
        let color: String?
        let startPeriod: Int
        let endPeriod: Int
        let startTime: String?
        let endTime: String?
        let date: String
        let isOngoing: Bool
    }

    let state: CourseWidgetSnapshotState
    let generatedAt: String
    let timetable: TimetableSummary?
    let today: DaySummary
    let nextCourse: CourseSummary?
    let errorMessage: String?
}

enum CourseWidgetSharedConfig {
    static let appGroupIdentifier = "group.dev.nvme0n1p.CourseList"
    static let snapshotDirectoryName = "Widget"
    static let snapshotFileName = "snapshot.json"
}
