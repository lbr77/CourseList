import Foundation

func validateTimetablePeriods(_ periods: [TimetablePeriodInput]) -> String? {
    guard !periods.isEmpty else { return "请至少添加一个节次。" }

    for (index, period) in periods.enumerated() {
        if period.periodIndex != index + 1 {
            return "节次序号必须从 1 开始连续递增。"
        }
        guard let startTime = parseTimeInput(period.startTime),
              let endTime = parseTimeInput(period.endTime)
        else {
            return "节次时间必须使用 HH:mm 格式。"
        }
        if startTime >= endTime {
            return "节次结束时间必须晚于开始时间。"
        }
    }

    return nil
}

func validateSavePeriodTemplateInput(_ input: SavePeriodTemplateInput) -> String? {
    if input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "模板名称不能为空。" }
    return validateTimetablePeriods(input.periods)
}

func validateCreateTimetableInput(_ input: CreateTimetableInput) -> String? {
    if input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "课表名称不能为空。" }
    if parseDateInput(input.startDate) == nil { return "开学日期必须使用 YYYY-MM-DD 格式。" }
    if input.weeksCount < 1 { return "周数至少为 1。" }
    return validateTimetablePeriods(input.periods)
}

func validateUpdateTimetableInput(_ input: UpdateTimetableInput) -> String? {
    if input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "课表名称不能为空。" }
    if parseDateInput(input.startDate) == nil { return "开学日期必须使用 YYYY-MM-DD 格式。" }
    if input.weeksCount < 1 { return "周数至少为 1。" }
    return nil
}

func validateSaveCourseInput(_ input: SaveCourseInput, periods: [TimetablePeriod]? = nil) -> String? {
    if input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "课程名称不能为空。" }
    if input.meetings.isEmpty { return "请至少添加一条上课时间。" }
    let periodsCount = periods?.count

    for meeting in input.meetings {
        if !(1 ... 7).contains(meeting.weekday) { return "星期必须在 1 到 7 之间。" }
        if meeting.startWeek < 1 || meeting.endWeek < meeting.startWeek { return "周次范围无效。" }
        if meeting.startPeriod < 1 || meeting.endPeriod < meeting.startPeriod { return "节次范围无效。" }
        if let periodsCount, meeting.endPeriod > periodsCount { return "课程节次超出了课表配置。" }
    }

    return nil
}
