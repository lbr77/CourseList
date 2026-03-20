import Foundation

func validateTimetablePeriods(_ periods: [TimetablePeriodInput]) -> String? {
    guard !periods.isEmpty else { return L10n.tr("Please add at least one section.") }

    for (index, period) in periods.enumerated() {
        if period.periodIndex != index + 1 {
            return L10n.tr("Section numbers must start from 1 and increase continuously.")
        }
        guard let startTime = parseTimeInput(period.startTime),
              let endTime = parseTimeInput(period.endTime)
        else {
            return L10n.tr("Section times must be in HH:mm format.")
        }
        if startTime >= endTime {
            return L10n.tr("The section end time must be later than the start time.")
        }
    }

    return nil
}

func validateSavePeriodTemplateInput(_ input: SavePeriodTemplateInput) -> String? {
    if input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return L10n.tr("Template name cannot be empty.") }
    return validateTimetablePeriods(input.periods)
}

func validateCreateTimetableInput(_ input: CreateTimetableInput) -> String? {
    if input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return L10n.tr("The class schedule name cannot be empty.") }
    if parseDateInput(input.startDate) == nil { return L10n.tr("Start date must be in YYYY-MM-DD format.") }
    if input.weeksCount < 1 { return L10n.tr("The week number must be at least 1.") }
    return validateTimetablePeriods(input.periods)
}

func validateUpdateTimetableInput(_ input: UpdateTimetableInput) -> String? {
    if input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return L10n.tr("The class schedule name cannot be empty.") }
    if parseDateInput(input.startDate) == nil { return L10n.tr("Start date must be in YYYY-MM-DD format.") }
    if input.weeksCount < 1 { return L10n.tr("The week number must be at least 1.") }
    return nil
}

func validateSaveCourseInput(_ input: SaveCourseInput, periods: [TimetablePeriod]? = nil) -> String? {
    if input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return L10n.tr("Course name cannot be empty.") }
    if input.meetings.isEmpty { return L10n.tr("Please add at least one class time.") }
    let periodsCount = periods?.count

    for meeting in input.meetings {
        if !(1 ... 7).contains(meeting.weekday) { return L10n.tr("Day of the week must be between 1 and 7.") }
        if meeting.startWeek < 1 || meeting.endWeek < meeting.startWeek { return L10n.tr("Invalid week range.") }
        if meeting.startPeriod < 1 || meeting.endPeriod < meeting.startPeriod { return L10n.tr("The section range is invalid.") }
        if let periodsCount, meeting.endPeriod > periodsCount { return L10n.tr("The number of course sections exceeds the timetable configuration.") }
    }

    return nil
}
