import SwiftUI
import WidgetKit

struct CourseListWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: CourseWidgetSnapshot
}

struct CourseListWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CourseListWidgetEntry {
        CourseListWidgetEntry(date: Date(), snapshot: Self.sampleSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (CourseListWidgetEntry) -> Void) {
        let snapshot = CourseWidgetSnapshotStore.load() ?? Self.sampleSnapshot
        completion(CourseListWidgetEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CourseListWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = CourseWidgetSnapshotStore.load() ?? Self.sampleSnapshot
        let entry = CourseListWidgetEntry(date: now, snapshot: snapshot)
        let refreshDate = nextRefreshDate(snapshot: snapshot, now: now)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private func nextRefreshDate(snapshot: CourseWidgetSnapshot, now: Date) -> Date {
        var dates: [Date] = []

        if let midnight = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: Calendar(identifier: .gregorian).startOfDay(for: now)) {
            dates.append(midnight)
        }

        for course in snapshot.today.courses {
            if let start = buildDate(date: course.date, time: course.startTime), start > now {
                dates.append(start)
            }
            if let end = buildDate(date: course.date, time: course.endTime), end > now {
                dates.append(end)
            }
        }

        if let nextCourse = snapshot.nextCourse,
           let nextStart = buildDate(date: nextCourse.date, time: nextCourse.startTime),
           nextStart > now {
            dates.append(nextStart)
        }

        return dates.filter { $0 > now }.min() ?? now.addingTimeInterval(30 * 60)
    }

    private func buildDate(date: String, time: String?) -> Date? {
        guard let time else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: "\(date) \(time)")
    }

    private static var sampleSnapshot: CourseWidgetSnapshot {
        let today = formatDate(Date())
        return CourseWidgetSnapshot(
            state: .ready,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            timetable: .init(
                id: "sample",
                name: "课程表",
                startDate: today,
                weeksCount: 20,
                currentWeek: 8
            ),
            today: .init(
                weekday: 1,
                date: today,
                courses: [
                    .init(
                        id: "course_sample",
                        courseId: "course_sample",
                        name: "高等数学",
                        location: "一教 201",
                        color: "#3B82F6",
                        startPeriod: 1,
                        endPeriod: 2,
                        startTime: "08:00",
                        endTime: "09:40",
                        date: today,
                        isOngoing: false
                    ),
                ]
            ),
            nextCourse: nil,
            errorMessage: nil
        )
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct CourseListWidgetEntryView: View {
    var entry: CourseListWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private var header: some View {
        HStack {
            Text(entry.snapshot.timetable?.name ?? "课程表")
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let week = entry.snapshot.timetable?.currentWeek {
                Text("第\(week)周")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch entry.snapshot.state {
        case .ready, .noCourses:
            if let course = entry.snapshot.today.courses.first {
                VStack(alignment: .leading, spacing: 4) {
                    Text(course.isOngoing ? "进行中" : "今日第一节")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(course.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text(timeText(course))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let location = course.location {
                        Text(location)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else if let next = entry.snapshot.nextCourse {
                VStack(alignment: .leading, spacing: 4) {
                    Text("下一节")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(next.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text(timeText(next))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("今天没有课程")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        case .noTimetable:
            Text("还没有课表")
                .font(.body)
                .foregroundStyle(.secondary)
        case .unavailable:
            Text("暂时无法读取课程")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func timeText(_ course: CourseWidgetSnapshot.CourseSummary) -> String {
        switch (course.startTime, course.endTime) {
        case let (start?, end?):
            return "\(start)-\(end)"
        case let (start?, nil):
            return start
        case let (nil, end?):
            return end
        default:
            return "第\(course.startPeriod)-\(course.endPeriod)节"
        }
    }
}

struct CourseListWidget: Widget {
    let kind: String = "CourseListWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CourseListWidgetProvider()) { entry in
            CourseListWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("课程表")
        .description("显示今天课程与下一节课程。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct CourseListWidgetBundle: WidgetBundle {
    var body: some Widget {
        CourseListWidget()
    }
}
