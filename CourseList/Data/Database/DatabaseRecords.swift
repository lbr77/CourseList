import Foundation
import WCDBSwift

let appDatabaseName = "course-list.db"
let appDatabaseVersion = 1

enum DatabaseTable {
    static let timetables = "timetables"
    static let courses = "courses"
    static let courseMeetings = "course_meetings"
    static let timetablePeriods = "timetable_periods"
    static let periodTemplates = "period_templates"
    static let periodTemplateItems = "period_template_items"
}

let schemaSQL = """
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS timetables (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  term_name TEXT NOT NULL,
  start_date TEXT NOT NULL,
  weeks_count INTEGER NOT NULL CHECK (weeks_count >= 1),
  is_active INTEGER NOT NULL DEFAULT 0 CHECK (is_active IN (0, 1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS courses (
  id TEXT PRIMARY KEY NOT NULL,
  timetable_id TEXT NOT NULL,
  name TEXT NOT NULL,
  teacher TEXT,
  location TEXT,
  color TEXT,
  note TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (timetable_id) REFERENCES timetables(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS course_meetings (
  id TEXT PRIMARY KEY NOT NULL,
  course_id TEXT NOT NULL,
  weekday INTEGER NOT NULL CHECK (weekday >= 1 AND weekday <= 7),
  start_week INTEGER NOT NULL CHECK (start_week >= 1),
  end_week INTEGER NOT NULL CHECK (end_week >= start_week),
  start_period INTEGER NOT NULL CHECK (start_period >= 1),
  end_period INTEGER NOT NULL CHECK (end_period >= start_period),
  location TEXT,
  week_type TEXT NOT NULL DEFAULT 'all' CHECK (week_type IN ('all', 'odd', 'even')),
  created_at TEXT NOT NULL,
  FOREIGN KEY (course_id) REFERENCES courses(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS timetable_periods (
  id TEXT PRIMARY KEY NOT NULL,
  timetable_id TEXT NOT NULL,
  period_index INTEGER NOT NULL CHECK (period_index >= 1),
  start_time TEXT NOT NULL,
  end_time TEXT NOT NULL,
  FOREIGN KEY (timetable_id) REFERENCES timetables(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS period_templates (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  is_default INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0, 1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS period_template_items (
  id TEXT PRIMARY KEY NOT NULL,
  template_id TEXT NOT NULL,
  period_index INTEGER NOT NULL CHECK (period_index >= 1),
  start_time TEXT NOT NULL,
  end_time TEXT NOT NULL,
  FOREIGN KEY (template_id) REFERENCES period_templates(id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_timetables_single_active
  ON timetables(is_active)
  WHERE is_active = 1;

CREATE INDEX IF NOT EXISTS idx_courses_timetable_id
  ON courses(timetable_id);

CREATE INDEX IF NOT EXISTS idx_course_meetings_course_id
  ON course_meetings(course_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_timetable_periods_unique_period
  ON timetable_periods(timetable_id, period_index);


CREATE UNIQUE INDEX IF NOT EXISTS idx_period_templates_single_default
  ON period_templates(is_default)
  WHERE is_default = 1;

CREATE UNIQUE INDEX IF NOT EXISTS idx_period_template_items_unique_period
  ON period_template_items(template_id, period_index);
"""

final class TimetableRecord: TableCodable {
    var id = ""
    var name = ""
    var termName = ""
    var startDate = ""
    var weeksCount = 0
    var isActive = false
    var createdAt = ""
    var updatedAt = ""

    enum CodingKeys: String, CodingTableKey {
        typealias Root = TimetableRecord
        case id
        case name
        case termName = "term_name"
        case startDate = "start_date"
        case weeksCount = "weeks_count"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        static let objectRelationalMapping = TableBinding(CodingKeys.self)
    }
}

final class TimetablePeriodRecord: TableCodable {
    var id = ""
    var timetableId = ""
    var periodIndex = 0
    var startTime = ""
    var endTime = ""

    enum CodingKeys: String, CodingTableKey {
        typealias Root = TimetablePeriodRecord
        case id
        case timetableId = "timetable_id"
        case periodIndex = "period_index"
        case startTime = "start_time"
        case endTime = "end_time"
        static let objectRelationalMapping = TableBinding(CodingKeys.self)
    }
}


final class PeriodTemplateRecord: TableCodable {
    var id = ""
    var name = ""
    var isDefault = false
    var createdAt = ""
    var updatedAt = ""

    enum CodingKeys: String, CodingTableKey {
        typealias Root = PeriodTemplateRecord
        case id
        case name
        case isDefault = "is_default"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        static let objectRelationalMapping = TableBinding(CodingKeys.self)
    }
}

final class PeriodTemplateItemRecord: TableCodable {
    var id = ""
    var templateId = ""
    var periodIndex = 0
    var startTime = ""
    var endTime = ""

    enum CodingKeys: String, CodingTableKey {
        typealias Root = PeriodTemplateItemRecord
        case id
        case templateId = "template_id"
        case periodIndex = "period_index"
        case startTime = "start_time"
        case endTime = "end_time"
        static let objectRelationalMapping = TableBinding(CodingKeys.self)
    }
}

final class CourseRecord: TableCodable {
    var id = ""
    var timetableId = ""
    var name = ""
    var teacher: String?
    var location: String?
    var color: String?
    var note: String?
    var createdAt = ""
    var updatedAt = ""

    enum CodingKeys: String, CodingTableKey {
        typealias Root = CourseRecord
        case id
        case timetableId = "timetable_id"
        case name
        case teacher
        case location
        case color
        case note
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        static let objectRelationalMapping = TableBinding(CodingKeys.self)
    }
}

final class CourseMeetingRecord: TableCodable {
    var id = ""
    var courseId = ""
    var weekday = 1
    var startWeek = 1
    var endWeek = 1
    var startPeriod = 1
    var endPeriod = 1
    var location: String?
    var weekType = WeekType.all.rawValue
    var createdAt = ""

    enum CodingKeys: String, CodingTableKey {
        typealias Root = CourseMeetingRecord
        case id
        case courseId = "course_id"
        case weekday
        case startWeek = "start_week"
        case endWeek = "end_week"
        case startPeriod = "start_period"
        case endPeriod = "end_period"
        case location
        case weekType = "week_type"
        case createdAt = "created_at"
        static let objectRelationalMapping = TableBinding(CodingKeys.self)
    }
}
