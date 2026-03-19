import Foundation
import WCDBSwift

final class TimetableRepository: TimetableRepositoryProtocol {
    private let manager: DatabaseManager

    init(manager: DatabaseManager) {
        self.manager = manager
    }

    func listTimetables() async throws -> [Timetable] {
        try await manager.read { database in
            let records: [TimetableRecord] = try database.getObjects(fromTable: DatabaseTable.timetables)
            return records
                .map(Self.mapTimetable)
                .sorted { shouldDisplayTimetableBefore($0, $1) }
        }
    }

    func getActiveTimetable() async throws -> Timetable? {
        try await manager.read { database in
            let records: [TimetableRecord] = try database.getObjects(fromTable: DatabaseTable.timetables)
            return resolveCurrentTimetable(timetables: records.map(Self.mapTimetable))
        }
    }

    func setActiveTimetable(id: String) async throws {
        try await manager.write { database in
            try database.run(transaction: { _ in
                try database.update(table: DatabaseTable.timetables, on: TimetableRecord.Properties.isActive, with: false)
                try database.update(
                    table: DatabaseTable.timetables,
                    on: TimetableRecord.Properties.isActive, TimetableRecord.Properties.updatedAt,
                    with: true, nowISO8601String(),
                    where: TimetableRecord.Properties.id == id
                )
            })
        }
    }

    func createTimetable(input: CreateTimetableInput) async throws -> String {
        if let error = validateCreateTimetableInput(input) { throw AppError.validation(error) }
        let timetableId = createIdentifier(prefix: "timetable")
        let timestamp = nowISO8601String()

        try await manager.write { database in
            try database.run(transaction: { _ in
                let record = TimetableRecord()
                let normalizedName = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
                record.id = timetableId
                record.name = normalizedName
                record.termName = normalizedName
                record.startDate = input.startDate
                record.weeksCount = input.weeksCount
                record.isActive = false
                record.createdAt = timestamp
                record.updatedAt = timestamp
                try database.insert(record, intoTable: DatabaseTable.timetables)
                try Self.insertPeriods(input.periods, timetableId: timetableId, database: database)
            })
        }

        return timetableId
    }

    func updateTimetable(input: UpdateTimetableInput) async throws {
        if let error = validateUpdateTimetableInput(input) { throw AppError.validation(error) }
        try await manager.write { database in
            let normalizedName = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
            try database.update(
                table: DatabaseTable.timetables,
                on: TimetableRecord.Properties.name,
                TimetableRecord.Properties.termName,
                TimetableRecord.Properties.startDate,
                TimetableRecord.Properties.weeksCount,
                TimetableRecord.Properties.updatedAt,
                with: normalizedName,
                normalizedName,
                input.startDate,
                input.weeksCount,
                nowISO8601String(),
                where: TimetableRecord.Properties.id == input.id
            )
        }
    }

    func deleteTimetable(id: String) async throws {
        try await manager.write { database in
            try database.run(transaction: { _ in
                let courses: [CourseRecord] = try database.getObjects(fromTable: DatabaseTable.courses, where: CourseRecord.Properties.timetableId == id)
                for course in courses {
                    try database.delete(fromTable: DatabaseTable.courseMeetings, where: CourseMeetingRecord.Properties.courseId == course.id)
                }
                try database.delete(fromTable: DatabaseTable.courses, where: CourseRecord.Properties.timetableId == id)
                try database.delete(fromTable: DatabaseTable.timetablePeriods, where: TimetablePeriodRecord.Properties.timetableId == id)
                try database.delete(fromTable: DatabaseTable.timetables, where: TimetableRecord.Properties.id == id)
            })
        }
    }

    func listPeriodTemplates() async throws -> [PeriodTemplate] {
        try await manager.read { database in
            let records: [PeriodTemplateRecord] = try database.getObjects(fromTable: DatabaseTable.periodTemplates)
            return records
                .map(Self.mapPeriodTemplate)
                .sorted(by: Self.sortPeriodTemplates)
        }
    }

    func getPeriodTemplate(id: String) async throws -> PeriodTemplate? {
        try await manager.read { database in
            let record = try database.getObject(fromTable: DatabaseTable.periodTemplates, where: PeriodTemplateRecord.Properties.id == id) as PeriodTemplateRecord?
            return record.map(Self.mapPeriodTemplate)
        }
    }

    func getDefaultPeriodTemplate() async throws -> PeriodTemplate? {
        try await manager.read { database in
            let record = try database.getObject(fromTable: DatabaseTable.periodTemplates, where: PeriodTemplateRecord.Properties.isDefault == true) as PeriodTemplateRecord?
            return record.map(Self.mapPeriodTemplate)
        }
    }

    func listPeriodTemplateItems(templateId: String) async throws -> [PeriodTemplateItem] {
        try await manager.read { database in
            let records: [PeriodTemplateItemRecord] = try database.getObjects(
                fromTable: DatabaseTable.periodTemplateItems,
                where: PeriodTemplateItemRecord.Properties.templateId == templateId
            )
            return records.sorted { $0.periodIndex < $1.periodIndex }.map(Self.mapPeriodTemplateItem)
        }
    }

    func savePeriodTemplate(input: SavePeriodTemplateInput) async throws -> String {
        if let error = validateSavePeriodTemplateInput(input) { throw AppError.validation(error) }
        let templateId = input.id ?? createIdentifier(prefix: "period_template")
        let timestamp = nowISO8601String()
        let normalizedName = input.name.trimmingCharacters(in: .whitespacesAndNewlines)

        try await manager.write { database in
            try database.run(transaction: { _ in
                let existing = try database.getObject(fromTable: DatabaseTable.periodTemplates, where: PeriodTemplateRecord.Properties.id == templateId) as PeriodTemplateRecord?

                if let existing {
                    try database.update(
                        table: DatabaseTable.periodTemplates,
                        on: PeriodTemplateRecord.Properties.name,
                        PeriodTemplateRecord.Properties.updatedAt,
                        with: normalizedName,
                        timestamp,
                        where: PeriodTemplateRecord.Properties.id == existing.id
                    )
                    try database.delete(fromTable: DatabaseTable.periodTemplateItems, where: PeriodTemplateItemRecord.Properties.templateId == existing.id)
                    try Self.insertPeriodTemplateItems(input.periods, templateId: existing.id, database: database)
                    return
                }

                let existingDefault = try database.getObject(fromTable: DatabaseTable.periodTemplates, where: PeriodTemplateRecord.Properties.isDefault == true) as PeriodTemplateRecord?
                let record = PeriodTemplateRecord()
                record.id = templateId
                record.name = normalizedName
                record.isDefault = existingDefault == nil
                record.createdAt = timestamp
                record.updatedAt = timestamp
                try database.insert(record, intoTable: DatabaseTable.periodTemplates)
                try Self.insertPeriodTemplateItems(input.periods, templateId: templateId, database: database)
            })
        }

        return templateId
    }

    func deletePeriodTemplate(id: String) async throws {
        try await manager.write { database in
            try database.run(transaction: { _ in
                let record = try database.getObject(fromTable: DatabaseTable.periodTemplates, where: PeriodTemplateRecord.Properties.id == id) as PeriodTemplateRecord?
                let wasDefault = record?.isDefault == true

                try database.delete(fromTable: DatabaseTable.periodTemplateItems, where: PeriodTemplateItemRecord.Properties.templateId == id)
                try database.delete(fromTable: DatabaseTable.periodTemplates, where: PeriodTemplateRecord.Properties.id == id)

                if wasDefault {
                    let remaining: [PeriodTemplateRecord] = try database.getObjects(fromTable: DatabaseTable.periodTemplates)
                    if let fallback = remaining.sorted(by: Self.sortPeriodTemplateRecords).first {
                        try database.update(
                            table: DatabaseTable.periodTemplates,
                            on: PeriodTemplateRecord.Properties.isDefault,
                            PeriodTemplateRecord.Properties.updatedAt,
                            with: true,
                            nowISO8601String(),
                            where: PeriodTemplateRecord.Properties.id == fallback.id
                        )
                    }
                }
            })
        }
    }

    func setDefaultPeriodTemplate(id: String) async throws {
        try await manager.write { database in
            try database.run(transaction: { _ in
                try database.update(table: DatabaseTable.periodTemplates, on: PeriodTemplateRecord.Properties.isDefault, with: false)
                try database.update(
                    table: DatabaseTable.periodTemplates,
                    on: PeriodTemplateRecord.Properties.isDefault,
                    PeriodTemplateRecord.Properties.updatedAt,
                    with: true,
                    nowISO8601String(),
                    where: PeriodTemplateRecord.Properties.id == id
                )
            })
        }
    }

    func listPeriods(timetableId: String) async throws -> [TimetablePeriod] {
        try await manager.read { database in
            let records: [TimetablePeriodRecord] = try database.getObjects(
                fromTable: DatabaseTable.timetablePeriods,
                where: TimetablePeriodRecord.Properties.timetableId == timetableId
            )
            return records.sorted { $0.periodIndex < $1.periodIndex }.map(Self.mapPeriod)
        }
    }

    func replacePeriods(timetableId: String, periods: [TimetablePeriodInput]) async throws {
        if let error = validateTimetablePeriods(periods) { throw AppError.validation(error) }
        try await manager.write { database in
            try database.run(transaction: { _ in
                try database.delete(fromTable: DatabaseTable.timetablePeriods, where: TimetablePeriodRecord.Properties.timetableId == timetableId)
                try Self.insertPeriods(periods, timetableId: timetableId, database: database)
                try database.update(
                    table: DatabaseTable.timetables,
                    on: TimetableRecord.Properties.updatedAt,
                    with: nowISO8601String(),
                    where: TimetableRecord.Properties.id == timetableId
                )
            })
        }
    }

    func listCourses(timetableId: String) async throws -> [CourseWithMeetings] {
        try await manager.read { database in
            let records: [CourseRecord] = try database.getObjects(
                fromTable: DatabaseTable.courses,
                where: CourseRecord.Properties.timetableId == timetableId
            )
            return try records.sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.createdAt > $1.createdAt
            }.map { try Self.mapCourse($0, database: database) }
        }
    }

    func getCourse(courseId: String) async throws -> CourseWithMeetings? {
        try await manager.read { database in
            let record = try database.getObject(fromTable: DatabaseTable.courses, where: CourseRecord.Properties.id == courseId) as CourseRecord?
            return try record.map { try Self.mapCourse($0, database: database) }
        }
    }

    func saveCourse(input: SaveCourseInput) async throws -> String {
        let periods = try await listPeriods(timetableId: input.timetableId)
        if let error = validateSaveCourseInput(input, periods: periods) { throw AppError.validation(error) }
        let courseId = input.id ?? createIdentifier(prefix: "course")
        let timestamp = nowISO8601String()

        try await manager.write { database in
            try database.run(transaction: { _ in
                let existing = try database.getObject(fromTable: DatabaseTable.courses, where: CourseRecord.Properties.id == courseId) as CourseRecord?
                if let existing {
                    try database.update(
                        table: DatabaseTable.courses,
                        on: CourseRecord.Properties.name,
                        CourseRecord.Properties.teacher,
                        CourseRecord.Properties.location,
                        CourseRecord.Properties.color,
                        CourseRecord.Properties.note,
                        CourseRecord.Properties.updatedAt,
                        with: input.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        normalizeOptionalText(input.teacher),
                        normalizeOptionalText(input.location),
                        normalizeOptionalText(input.color),
                        normalizeOptionalText(input.note),
                        timestamp,
                        where: CourseRecord.Properties.id == existing.id
                    )
                    try database.delete(fromTable: DatabaseTable.courseMeetings, where: CourseMeetingRecord.Properties.courseId == existing.id)
                } else {
                    let record = CourseRecord()
                    record.id = courseId
                    record.timetableId = input.timetableId
                    record.name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    record.teacher = normalizeOptionalText(input.teacher)
                    record.location = normalizeOptionalText(input.location)
                    record.color = normalizeOptionalText(input.color)
                    record.note = normalizeOptionalText(input.note)
                    record.createdAt = timestamp
                    record.updatedAt = timestamp
                    try database.insert(record, intoTable: DatabaseTable.courses)
                }
                try Self.insertMeetings(input.meetings, courseId: courseId, database: database)
            })
        }

        return courseId
    }

    func deleteCourse(courseId: String) async throws {
        try await manager.write { database in
            try database.run(transaction: { _ in
                try database.delete(fromTable: DatabaseTable.courseMeetings, where: CourseMeetingRecord.Properties.courseId == courseId)
                try database.delete(fromTable: DatabaseTable.courses, where: CourseRecord.Properties.id == courseId)
            })
        }
    }

    func getWeekSchedule(timetableId: String, week: Int) async throws -> WeekSchedule {
        let courses = try await listCourses(timetableId: timetableId)
        return WeekScheduleBuilder.build(week: week, courses: courses)
    }

    func findCourseConflicts(input: SaveCourseInput) async throws -> [CourseConflictWarning] {
        let courses = try await listCourses(timetableId: input.timetableId)
        return ConflictDetector.findConflicts(input: input, courses: courses)
    }

    func importTimetableDraft(_ draft: ImportedTimetableDraft) async throws -> String {
        let errors = validateImportedTimetableDraft(draft)
        if !errors.isEmpty { throw AppError.validation(errors.joined(separator: "\n")) }
        let timetableId = createIdentifier(prefix: "timetable")
        let timestamp = nowISO8601String()

        try await manager.write { database in
            try database.run(transaction: { _ in
                let timetable = TimetableRecord()
                let normalizedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                timetable.id = timetableId
                timetable.name = normalizedName
                timetable.termName = normalizedName
                timetable.startDate = draft.startDate
                timetable.weeksCount = draft.weeksCount
                timetable.isActive = false
                timetable.createdAt = timestamp
                timetable.updatedAt = timestamp
                try database.insert(timetable, intoTable: DatabaseTable.timetables)
                try Self.insertPeriods(draft.periods.map { .init(periodIndex: $0.periodIndex, startTime: $0.startTime, endTime: $0.endTime) }, timetableId: timetableId, database: database)
                for courseDraft in draft.courses {
                    let courseId = createIdentifier(prefix: "course")
                    let course = CourseRecord()
                    course.id = courseId
                    course.timetableId = timetableId
                    course.name = courseDraft.name
                    course.teacher = normalizeOptionalText(courseDraft.teacher)
                    course.location = normalizeOptionalText(courseDraft.location)
                    course.color = normalizeOptionalText(courseDraft.color)
                    course.note = normalizeOptionalText(courseDraft.note)
                    course.createdAt = timestamp
                    course.updatedAt = timestamp
                    try database.insert(course, intoTable: DatabaseTable.courses)
                    try Self.insertMeetings(courseDraft.meetings.map {
                        .init(
                            weekday: $0.weekday,
                            startWeek: $0.startWeek,
                            endWeek: $0.endWeek,
                            startPeriod: $0.startPeriod,
                            endPeriod: $0.endPeriod,
                            location: $0.location,
                            weekType: $0.weekType
                        )
                    }, courseId: courseId, database: database)
                }
            })
        }
        return timetableId
    }
}

private extension TimetableRepository {
    static func sortTimetables(_ lhs: TimetableRecord, _ rhs: TimetableRecord) -> Bool {
        shouldDisplayTimetableBefore(mapTimetable(lhs), mapTimetable(rhs))
    }

    static func sortPeriodTemplates(_ lhs: PeriodTemplate, _ rhs: PeriodTemplate) -> Bool {
        if lhs.isDefault != rhs.isDefault { return lhs.isDefault && !rhs.isDefault }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.name.localizedCompare(rhs.name) == .orderedAscending
    }

    static func sortPeriodTemplateRecords(_ lhs: PeriodTemplateRecord, _ rhs: PeriodTemplateRecord) -> Bool {
        sortPeriodTemplates(mapPeriodTemplate(lhs), mapPeriodTemplate(rhs))
    }

    static func mapTimetable(_ record: TimetableRecord) -> Timetable {
        Timetable(
            id: record.id,
            name: record.name,
            startDate: record.startDate,
            weeksCount: record.weeksCount,
            isActive: record.isActive,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    static func mapPeriodTemplate(_ record: PeriodTemplateRecord) -> PeriodTemplate {
        PeriodTemplate(
            id: record.id,
            name: record.name,
            isDefault: record.isDefault,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    static func mapPeriodTemplateItem(_ record: PeriodTemplateItemRecord) -> PeriodTemplateItem {
        PeriodTemplateItem(
            id: record.id,
            templateId: record.templateId,
            periodIndex: record.periodIndex,
            startTime: record.startTime,
            endTime: record.endTime
        )
    }

    static func mapPeriod(_ record: TimetablePeriodRecord) -> TimetablePeriod {
        TimetablePeriod(
            id: record.id,
            timetableId: record.timetableId,
            periodIndex: record.periodIndex,
            startTime: record.startTime,
            endTime: record.endTime
        )
    }

    static func mapMeeting(_ record: CourseMeetingRecord) -> CourseMeeting {
        CourseMeeting(
            id: record.id,
            courseId: record.courseId,
            weekday: record.weekday,
            startWeek: record.startWeek,
            endWeek: record.endWeek,
            startPeriod: record.startPeriod,
            endPeriod: record.endPeriod,
            location: record.location,
            weekType: WeekType(rawValue: record.weekType) ?? .all,
            createdAt: record.createdAt
        )
    }

    static func mapCourse(_ record: CourseRecord, database: Database) throws -> CourseWithMeetings {
        let meetings: [CourseMeetingRecord] = try database.getObjects(
            fromTable: DatabaseTable.courseMeetings,
            where: CourseMeetingRecord.Properties.courseId == record.id
        )
        return CourseWithMeetings(
            id: record.id,
            timetableId: record.timetableId,
            name: record.name,
            teacher: record.teacher,
            location: record.location,
            color: record.color,
            note: record.note,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            meetings: meetings.sorted {
                if $0.weekday != $1.weekday { return $0.weekday < $1.weekday }
                if $0.startPeriod != $1.startPeriod { return $0.startPeriod < $1.startPeriod }
                return $0.endPeriod < $1.endPeriod
            }.map(mapMeeting)
        )
    }

    static func insertPeriods(_ periods: [TimetablePeriodInput], timetableId: String, database: Database) throws {
        let records = periods.map { period -> TimetablePeriodRecord in
            let record = TimetablePeriodRecord()
            record.id = createIdentifier(prefix: "period")
            record.timetableId = timetableId
            record.periodIndex = period.periodIndex
            record.startTime = period.startTime
            record.endTime = period.endTime
            return record
        }
        if !records.isEmpty {
            try database.insert(records, intoTable: DatabaseTable.timetablePeriods)
        }
    }

    static func insertPeriodTemplateItems(_ periods: [TimetablePeriodInput], templateId: String, database: Database) throws {
        let records = periods.map { period -> PeriodTemplateItemRecord in
            let record = PeriodTemplateItemRecord()
            record.id = createIdentifier(prefix: "period_template_item")
            record.templateId = templateId
            record.periodIndex = period.periodIndex
            record.startTime = period.startTime
            record.endTime = period.endTime
            return record
        }
        if !records.isEmpty {
            try database.insert(records, intoTable: DatabaseTable.periodTemplateItems)
        }
    }

    static func insertMeetings(_ meetings: [CourseMeetingInput], courseId: String, database: Database) throws {
        let records = meetings.map { meeting -> CourseMeetingRecord in
            let record = CourseMeetingRecord()
            record.id = createIdentifier(prefix: "meeting")
            record.courseId = courseId
            record.weekday = meeting.weekday
            record.startWeek = meeting.startWeek
            record.endWeek = meeting.endWeek
            record.startPeriod = meeting.startPeriod
            record.endPeriod = meeting.endPeriod
            record.location = normalizeOptionalText(meeting.location)
            record.weekType = meeting.weekType.rawValue
            record.createdAt = nowISO8601String()
            return record
        }
        if !records.isEmpty {
            try database.insert(records, intoTable: DatabaseTable.courseMeetings)
        }
    }
}
