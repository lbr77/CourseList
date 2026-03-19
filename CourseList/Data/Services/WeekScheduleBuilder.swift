import Foundation

enum WeekScheduleBuilder {
    static func build(week: Int, courses: [CourseWithMeetings]) -> WeekSchedule {
        var days = (1 ... 7).map { WeekScheduleDay(weekday: $0) }

        for course in courses {
            for meeting in course.meetings {
                guard meeting.startWeek <= week, meeting.endWeek >= week else { continue }
                guard weekMatchesType(week, weekType: meeting.weekType) else { continue }

                let item = DayScheduleItem(
                    courseId: course.id,
                    name: course.name,
                    teacher: course.teacher,
                    location: meeting.location ?? course.location,
                    color: course.color,
                    note: course.note,
                    weekday: meeting.weekday,
                    startWeek: meeting.startWeek,
                    endWeek: meeting.endWeek,
                    startPeriod: meeting.startPeriod,
                    endPeriod: meeting.endPeriod,
                    weekType: meeting.weekType
                )
                days[meeting.weekday - 1].items.append(item)
            }
        }

        for index in days.indices {
            days[index].items.sort {
                if $0.startPeriod != $1.startPeriod { return $0.startPeriod < $1.startPeriod }
                if $0.endPeriod != $1.endPeriod { return $0.endPeriod < $1.endPeriod }
                return $0.name < $1.name
            }
        }

        return WeekSchedule(week: week, days: days)
    }

    static func buildCoursesSnapshot(
        timetable: Timetable,
        week: Int,
        periods: [TimetablePeriod],
        courses: [CourseWithMeetings]
    ) -> WeekCoursesSnapshot {
        let periodMap = Dictionary(uniqueKeysWithValues: periods.map { ($0.periodIndex, $0) })
        var items: [WeekCourseInfo] = []

        for course in courses {
            for meeting in course.meetings {
                guard meeting.startWeek <= week, meeting.endWeek >= week else { continue }
                guard weekMatchesType(week, weekType: meeting.weekType) else { continue }

                let startTime = periodMap[meeting.startPeriod]?.startTime
                let endTime = periodMap[meeting.endPeriod]?.endTime

                items.append(
                    WeekCourseInfo(
                        meetingId: meeting.id,
                        courseId: course.id,
                        courseName: course.name,
                        teacher: course.teacher,
                        location: meeting.location ?? course.location,
                        color: course.color,
                        note: course.note,
                        weekday: meeting.weekday,
                        week: week,
                        startPeriod: meeting.startPeriod,
                        endPeriod: meeting.endPeriod,
                        startTime: startTime,
                        endTime: endTime,
                        weekType: meeting.weekType
                    )
                )
            }
        }

        items.sort {
            if $0.weekday != $1.weekday { return $0.weekday < $1.weekday }
            if $0.startPeriod != $1.startPeriod { return $0.startPeriod < $1.startPeriod }
            if $0.endPeriod != $1.endPeriod { return $0.endPeriod < $1.endPeriod }
            return $0.courseName < $1.courseName
        }

        return WeekCoursesSnapshot(
            timetableId: timetable.id,
            timetableName: timetable.name,
            week: week,
            items: items
        )
    }
}
