import Foundation

struct JLUVPNImportAdapter: ImportAdapter {
    let id = "jlu-vpn"
    let label = "JLU timetable"

    private let termSelector = "#dqxnxq2"
    private let currentWeekSelector = "#zkbzc"

    var captureJavaScript: String {
        """
        (() => {
          const normalizeText = (value) => (value || '').replace(/\\s+/g, ' ').trim();
          const getText = (selector) => normalizeText(document.querySelector(selector)?.textContent || '');
          const getRows = (selector) => Array.from(document.querySelectorAll(selector));
          const periods = getRows('#kcb_container td[data-unit]')
            .map((cell) => {
              const periodIndex = Number(cell.getAttribute('data-unit'));
              const text = normalizeText(cell.textContent || '');
              const match = text.match(/第\\d+节\\s*([0-9]{2}:[0-9]{2})-([0-9]{2}:[0-9]{2})/);
              if (!Number.isFinite(periodIndex) || !match) return null;
              return { periodIndex, startTime: match[1], endTime: match[2] };
            })
            .filter(Boolean);
          const getTextFromNode = (node) => normalizeText(node?.textContent || '');
          const getCourseName = (node) => {
            if (!node) return '';
            const directText = Array.from(node.childNodes || [])
              .filter((child) => child.nodeType === Node.TEXT_NODE)
              .map((child) => normalizeText(child.textContent || ''))
              .filter(Boolean)
              .join(' ');
            return directText || getTextFromNode(node);
          };
          const courses = getRows('#kcb_container .mtt_arrange_item')
            .map((item) => ({
              name: getCourseName(item.querySelector('.mtt_item_kcmc')),
              teacher: getTextFromNode(item.querySelector('.mtt_item_jxbmc')),
              detail: getTextFromNode(item.querySelector('.mtt_item_room')),
              classText: getTextFromNode(item.querySelector('.mtt_item_class')),
              color: normalizeText(item.style?.backgroundColor || ''),
            }))
            .filter((item) => item.name && item.detail);
          const unscheduledCourses = getRows('#wptk_contaner .wpk-container .kbck-card-unset')
            .map((card) => {
              const values = {};
              Array.from(card.querySelectorAll('div')).forEach((row, index) => {
                const texts = Array.from(row.querySelectorAll('span'))
                  .map((element) => normalizeText(element.textContent || ''))
                  .filter(Boolean);
                if (index === 0 && texts[0]) values.name = texts[0];
                if (texts.length >= 2) values[texts[0]] = texts[1];
              });
              return {
                name: values.name || '',
                teacher: values['上课教师'] || '',
                weekText: values['上课周次'] || '',
                classNo: values['教学班序号'] || '',
              };
            })
            .filter((item) => item.name);
          return {
            url: window.location.href,
            title: document.title,
            appName: window._JW_INIT_CONFIG?.appname || '',
            termText: getText('\(termSelector)'),
            currentWeekText: getText('\(currentWeekSelector)'),
            capturedAt: new Date().toISOString(),
            periods,
            courses,
            unscheduledCourses,
          };
        })();
        """
    }

    func matches(_ context: ImportContext) -> Bool {
        isJluVPNURL(context.url) && isLikelyTimetableContext(context)
    }

    func normalize(rawPayload: Any, context: ImportContext) throws -> ImportedTimetableDraft {
        guard let payload = rawPayload as? [String: Any] else {
            throw AppError.importNormalize("JLU 导入返回的数据格式不正确。")
        }

        let termName = normalizeOptionalText((payload["termText"] as? String) ?? "")
            ?? normalizeOptionalText(context.title)
            ?? "JLU timetable"

        let periods = ((payload["periods"] as? [[String: Any]]) ?? []).compactMap { item -> ImportedPeriodDraft? in
            guard let periodIndex = item["periodIndex"] as? Int,
                  let startTime = item["startTime"] as? String,
                  let endTime = item["endTime"] as? String else { return nil }
            return ImportedPeriodDraft(periodIndex: periodIndex, startTime: startTime, endTime: endTime)
        }.sorted { $0.periodIndex < $1.periodIndex }

        let rawCourses = (payload["courses"] as? [[String: Any]]) ?? []
        let unscheduledCourses = (payload["unscheduledCourses"] as? [[String: Any]]) ?? []

        if periods.isEmpty {
            throw AppError.importNormalize("JLU 页面中没有找到节次定义。")
        }
        if rawCourses.isEmpty {
            throw AppError.importNormalize("JLU 页面匹配成功，但没有找到已排课的课程。")
        }

        var warnings: [ImportWarning] = []
        var coursesByKey: [String: ImportedCourseDraft] = [:]
        var skippedCourses: [String] = []

        for rawCourse in rawCourses {
            let name = normalizeOptionalText(rawCourse["name"] as? String)
            let detail = normalizeOptionalText(rawCourse["detail"] as? String)
            guard let name, let detail else { continue }
            do {
                let template = try parseMeetingTemplate(detail)
                let meetings = expandMeetingTemplate(template)
                upsertCourse(&coursesByKey, rawCourse: rawCourse, normalizedName: name, meetings: meetings)
            } catch {
                skippedCourses.append(name)
            }
        }

        if !skippedCourses.isEmpty {
            warnings.append(.init(code: "jlu_skipped_courses", message: "有 \(skippedCourses.count) 门课未能解析：\(skippedCourses.prefix(5).joined(separator: ", "))", severity: .warning))
        }
        if !unscheduledCourses.isEmpty {
            let names = unscheduledCourses.compactMap { $0["name"] as? String }
            warnings.append(.init(code: "jlu_unscheduled_courses", message: "有 \(unscheduledCourses.count) 门未排课课程被跳过：\(names.prefix(5).joined(separator: ", "))", severity: .warning))
        }

        let inference = inferStartDate(capturedAt: payload["capturedAt"] as? String, currentWeekText: payload["currentWeekText"] as? String)
        warnings.append(inference.warning)

        let courses = coursesByKey.values.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        if courses.isEmpty {
            throw AppError.importNormalize("JLU 页面中识别到了课块，但无法解析出有效上课时间。")
        }

        return ImportedTimetableDraft(
            name: "JLU \(termName)",
            termName: termName,
            startDate: inference.startDate,
            weeksCount: computeWeeksCount(courses: courses, unscheduledCourses: unscheduledCourses),
            periods: periods,
            courses: courses,
            warnings: warnings,
            source: .init(
                adapterId: id,
                adapterLabel: label,
                capturedAt: (payload["capturedAt"] as? String) ?? nowISO8601String(),
                url: (payload["url"] as? String) ?? context.url,
                title: (payload["title"] as? String) ?? context.title
            )
        )
    }
}

private extension JLUVPNImportAdapter {
    typealias WeekRange = (startWeek: Int, endWeek: Int, weekType: WeekType)
    typealias MeetingTemplate = (weekday: Int, startPeriod: Int, endPeriod: Int, location: String?, weekRanges: [WeekRange])

    func isJluVPNURL(_ url: String) -> Bool {
        guard let host = URL(string: url)?.host?.lowercased() else { return false }
        return host == "vpn.jlu.edu.cn" || host.hasSuffix(".jlu.edu.cn")
    }

    func isLikelyTimetableContext(_ context: ImportContext) -> Bool {
        let haystack = "\(context.title ?? "") \(context.textSample ?? "") \(context.htmlSample ?? "") \(context.url)".lowercased()
        return ["我的课表", "课表查看", "/sys/wdkb/", "wut_table", "mtt_arrange_item"].contains(where: haystack.contains)
    }

    func parseWeekdayToken(_ token: String) throws -> Int {
        let normalized = normalizeWhitespace(token.replacingOccurrences(of: "星期", with: ""))
        if let digit = normalized.first(where: { ("1" ... "7").contains(String($0)) }), let value = Int(String(digit)) { return value }
        let lookup: [String: Int] = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "日": 7, "天": 7, "七": 7]
        if let value = lookup[String(normalized.prefix(1))] { return value }
        throw AppError.importNormalize("无法解析星期：\(token)")
    }

    func parsePeriodToken(_ token: String) throws -> (Int, Int) {
        let normalized = normalizeWhitespace(token)
        let regex = try NSRegularExpression(pattern: #"^第(\d+)节(?:-第?(\d+)节)?$"#)
        let range = NSRange(normalized.startIndex..., in: normalized)
        guard let match = regex.firstMatch(in: normalized, range: range),
              let startRange = Range(match.range(at: 1), in: normalized),
              let start = Int(normalized[startRange])
        else {
            throw AppError.importNormalize("无法解析节次：\(token)")
        }
        if let endRange = Range(match.range(at: 2), in: normalized), let end = Int(normalized[endRange]) { return (start, end) }
        return (start, start)
    }

    func parseWeekToken(_ token: String) throws -> WeekRange {
        let normalized = normalizeWhitespace(token)
        let weekType: WeekType = normalized.contains("单") ? .odd : (normalized.contains("双") ? .even : .all)
        let compact = normalized
            .replacingOccurrences(of: "周", with: "")
            .replacingOccurrences(of: #"\((?:单|双)\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[单双]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let regex = try NSRegularExpression(pattern: #"^(\d+)(?:-(\d+))?$"#)
        let range = NSRange(compact.startIndex..., in: compact)
        guard let match = regex.firstMatch(in: compact, range: range),
              let startRange = Range(match.range(at: 1), in: compact),
              let startWeek = Int(compact[startRange])
        else {
            throw AppError.importNormalize("无法解析周次：\(token)")
        }
        let endWeek: Int
        if let endRange = Range(match.range(at: 2), in: compact), let parsed = Int(compact[endRange]) {
            endWeek = parsed
        } else {
            endWeek = startWeek
        }
        return (startWeek, endWeek, weekType)
    }

    func parseMeetingTemplate(_ detail: String) throws -> MeetingTemplate {
        let tokens = normalizeWhitespace(detail).split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let weekdayIndex = tokens.firstIndex(where: { $0.hasPrefix("星期") }),
              let periodIndex = tokens.firstIndex(where: { $0.hasPrefix("第") && $0.contains("节") }),
              weekdayIndex < periodIndex else {
            throw AppError.importNormalize("无法解析课程详情：\(detail)")
        }
        let weekRanges = try tokens[..<weekdayIndex].map { try parseWeekToken(String($0)) }
        let weekday = try parseWeekdayToken(String(tokens[weekdayIndex]))
        let (startPeriod, endPeriod) = try parsePeriodToken(String(tokens[periodIndex]))
        let location = normalizeOptionalText(tokens[(periodIndex + 1)...].joined(separator: ","))
        if weekRanges.isEmpty { throw AppError.importNormalize("课程详情没有有效周次：\(detail)") }
        return (weekday, startPeriod, endPeriod, location, weekRanges)
    }

    func expandMeetingTemplate(_ template: MeetingTemplate) -> [ImportedMeetingDraft] {
        template.weekRanges.map {
            ImportedMeetingDraft(
                weekday: template.weekday,
                startWeek: $0.startWeek,
                endWeek: $0.endWeek,
                startPeriod: template.startPeriod,
                endPeriod: template.endPeriod,
                location: template.location,
                weekType: $0.weekType
            )
        }
    }

    func inferStartDate(capturedAt: String?, currentWeekText: String?) -> (startDate: String, warning: ImportWarning) {
        let formatter = ISO8601DateFormatter()
        let captureDate = capturedAt.flatMap { formatter.date(from: $0) } ?? Date()
        let fallback = formatDateInput(Date())
        guard let currentWeekText, let currentWeek = Int(currentWeekText), currentWeek >= 1 else {
            return (fallback, .init(code: "jlu_missing_start_date", message: "无法推断学期开始日期，已默认填为今天，请导入后检查。", severity: .warning))
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let weekday = calendar.component(.weekday, from: captureDate)
        let mondayOffset = weekday == 1 ? -6 : 2 - weekday
        guard let monday = calendar.date(byAdding: .day, value: mondayOffset - (currentWeek - 1) * 7, to: captureDate) else {
            return (fallback, .init(code: "jlu_missing_start_date", message: "无法推断学期开始日期，已默认填为今天，请导入后检查。", severity: .warning))
        }
        return (formatDateInput(monday), .init(code: "jlu_inferred_start_date", message: "已根据当前周次推断开学日期。", severity: .info))
    }

    func upsertCourse(_ coursesByKey: inout [String: ImportedCourseDraft], rawCourse: [String: Any], normalizedName: String, meetings: [ImportedMeetingDraft]) {
        let teacher = normalizeOptionalText(rawCourse["teacher"] as? String)
        let color = normalizeOptionalText(rawCourse["color"] as? String)
        let nextNote = normalizeOptionalText(rawCourse["classText"] as? String)
        let key = [normalizedName, teacher ?? ""].joined(separator: "__")

        if var existing = coursesByKey[key] {
            existing.note = appendDistinctNote(current: existing.note, next: nextNote)
            existing.color = existing.color ?? color
            existing.meetings = dedupeMeetings(existing.meetings + meetings)
            coursesByKey[key] = existing
            return
        }

        coursesByKey[key] = ImportedCourseDraft(
            name: normalizedName,
            teacher: teacher,
            location: nil,
            color: color,
            note: appendDistinctNote(current: nil, next: nextNote),
            meetings: dedupeMeetings(meetings)
        )
    }

    func appendDistinctNote(current: String?, next: String?) -> String? {
        guard let next = normalizeOptionalText(next) else { return current }
        guard let current else { return next }
        return current.contains(next) ? current : current + "\n" + next
    }

    func dedupeMeetings(_ meetings: [ImportedMeetingDraft]) -> [ImportedMeetingDraft] {
        var seen = Set<String>()
        var result: [ImportedMeetingDraft] = []
        for meeting in meetings {
            let key = [meeting.weekday, meeting.startWeek, meeting.endWeek, meeting.startPeriod, meeting.endPeriod, meeting.weekType.rawValue, meeting.location ?? ""].map(String.init(describing:)).joined(separator: ":")
            if seen.insert(key).inserted {
                result.append(meeting)
            }
        }
        return result.sorted {
            if $0.weekday != $1.weekday { return $0.weekday < $1.weekday }
            if $0.startPeriod != $1.startPeriod { return $0.startPeriod < $1.startPeriod }
            return $0.startWeek < $1.startWeek
        }
    }

    func computeWeeksCount(courses: [ImportedCourseDraft], unscheduledCourses: [[String: Any]]) -> Int {
        var maxWeek = 1
        for course in courses {
            for meeting in course.meetings where meeting.endWeek > maxWeek {
                maxWeek = meeting.endWeek
            }
        }
        for course in unscheduledCourses {
            guard let weekText = normalizeOptionalText(course["weekText"] as? String) else { continue }
            for token in weekText.split(separator: ",") {
                if let range = try? parseWeekToken(String(token)), range.endWeek > maxWeek {
                    maxWeek = range.endWeek
                }
            }
        }
        return maxWeek
    }
}
