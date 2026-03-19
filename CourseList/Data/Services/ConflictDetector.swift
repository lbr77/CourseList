import Foundation

enum ConflictDetector {
    static func findConflicts(input: SaveCourseInput, courses: [CourseWithMeetings]) -> [CourseConflictWarning] {
        var warnings: [CourseConflictWarning] = []

        for meeting in input.meetings {
            for course in courses where course.id != input.id {
                for savedMeeting in course.meetings {
                    guard meeting.weekday == savedMeeting.weekday else { continue }
                    guard periodsOverlap(meeting.startPeriod, meeting.endPeriod, savedMeeting.startPeriod, savedMeeting.endPeriod) else { continue }
                    guard weekRangesOverlap(
                        firstStart: meeting.startWeek,
                        firstEnd: meeting.endWeek,
                        firstType: meeting.weekType,
                        secondStart: savedMeeting.startWeek,
                        secondEnd: savedMeeting.endWeek,
                        secondType: savedMeeting.weekType
                    ) else { continue }

                    warnings.append(
                        CourseConflictWarning(
                            courseId: course.id,
                            courseName: course.name,
                            weekday: savedMeeting.weekday,
                            startPeriod: savedMeeting.startPeriod,
                            endPeriod: savedMeeting.endPeriod,
                            message: "\(course.name) 与星期\(meeting.weekday) 第 \(meeting.startPeriod)-\(meeting.endPeriod) 节存在重叠。"
                        )
                    )
                }
            }
        }

        return warnings
    }
}
