import Foundation

enum ImportPhase: String, Codable, Sendable {
    case browsing
    case capturing
    case unsupported
    case preview
    case importing
    case done
    case error
}

struct ImportWarning: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let code: String
    let message: String
    let severity: Severity

    enum Severity: String, Codable, Sendable {
        case info
        case warning
    }

    init(code: String, message: String, severity: Severity) {
        id = createIdentifier(prefix: "import_warning")
        self.code = code
        self.message = message
        self.severity = severity
    }
}

struct ImportedPeriodDraft: Codable, Equatable, Sendable {
    var periodIndex: Int
    var startTime: String
    var endTime: String
}

struct ImportedMeetingDraft: Codable, Equatable, Sendable {
    var weekday: Int
    var startWeek: Int
    var endWeek: Int
    var startPeriod: Int
    var endPeriod: Int
    var location: String?
    var weekType: WeekType
}

struct ImportedCourseDraft: Codable, Equatable, Sendable {
    var name: String
    var teacher: String?
    var location: String?
    var color: String?
    var note: String?
    var meetings: [ImportedMeetingDraft]
}

struct ImportedTimetableDraft: Codable, Equatable, Sendable {
    struct Source: Codable, Equatable, Sendable {
        var adapterId: String
        var adapterLabel: String
        var capturedAt: String
        var url: String
        var title: String?
    }

    var name: String
    var startDate: String
    var weeksCount: Int
    var periods: [ImportedPeriodDraft]
    var courses: [ImportedCourseDraft]
    var warnings: [ImportWarning]
    var source: Source
}

struct ImportContext: Codable, Equatable, Sendable {
    var url: String
    var title: String?
    var textSample: String?
    var htmlSample: String?
    var html: String?
}

struct ImportUnsupportedSnapshot: Codable, Equatable, Sendable {
    var url: String
    var title: String?
    var textSample: String?
    var htmlSample: String?
    var html: String?
    var reason: String
}

struct TimetableImportSchool: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let adapterId: String
    let defaultImportURL: String
}

let timetableImportSchools: [TimetableImportSchool] = [
    .init(id: "jlu", label: "吉林大学（vpn)", adapterId: "jlu-vpn", defaultImportURL: "https://vpn.jlu.edu.cn")
]
