import Foundation

func validateImportedTimetableDraft(_ draft: ImportedTimetableDraft) -> [String] {
    var errors: [String] = []
    let createInput = CreateTimetableInput(
        name: draft.name,
        termName: draft.termName,
        startDate: draft.startDate,
        weeksCount: draft.weeksCount,
        periods: draft.periods.map { .init(periodIndex: $0.periodIndex, startTime: $0.startTime, endTime: $0.endTime) }
    )
    if let error = validateCreateTimetableInput(createInput) {
        errors.append(error)
    }
    if draft.courses.isEmpty {
        errors.append("导入结果中没有课程。")
    }
    let indexes = draft.periods.map(\ .periodIndex)
    if indexes.enumerated().contains(where: { $0.offset + 1 != $0.element }) {
        errors.append("导入的节次必须从 1 开始连续编号。")
    }
    for (index, course) in draft.courses.enumerated() {
        let input = SaveCourseInput(
            timetableId: "import-preview",
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
        let periods = draft.periods.map { TimetablePeriod(id: "preview_\($0.periodIndex)", timetableId: "preview", periodIndex: $0.periodIndex, startTime: $0.startTime, endTime: $0.endTime) }
        if let error = validateSaveCourseInput(input, periods: periods) {
            errors.append("第 \(index + 1) 门课程：\(error)")
        }
    }
    return errors
}
