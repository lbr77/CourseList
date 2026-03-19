import SwiftUI

struct TimetableHomeView: View {
    @ObservedObject var viewModel: TimetableHomeViewModel
    @State private var visibleDate = Date()
    @State private var scrollToCurrentWeekToken = 0
    let onImportTap: () -> Void
    let onNewTimetableTap: () -> Void
    let onManageTimetableTap: () -> Void
    let onNewCourseTap: () -> Void
    let onEditCourseTap: (CourseWithMeetings, CoursePreviewSelectionContext) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            fixedTodayHeader

            CalendarKitTimetableView(
                timetable: viewModel.currentTimetable,
                periods: viewModel.periods,
                courses: viewModel.courses,
                schedule: viewModel.schedule,
                scheduleCache: viewModel.scheduleCache,
                onSelectCourse: onEditCourseTap,
                onVisibleDateChange: { date in
                    visibleDate = date
                    Task { await viewModel.goToDate(date) }
                },
                scrollToCurrentWeekToken: scrollToCurrentWeekToken
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .background(Color(.systemBackground))
        .alert("错误", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task {
            if viewModel.currentTimetable == nil, !viewModel.isLoading {
                await viewModel.reload()
            }
        }
    }

    private var fixedTodayHeader: some View {
        let today = Date()
        let isCurrentWeek = makeTimetableDisplayCalendar().isDate(today, equalTo: visibleDate, toGranularity: .weekOfYear)

        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(titleString(for: today))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                if isCurrentWeek {
                    Text(weekdayString(for: today))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            if !isCurrentWeek {
                Button("回到本周") {
                    scrollToCurrentWeekToken += 1
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func titleString(for date: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        return "\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日"
    }

    private func weekdayString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}
