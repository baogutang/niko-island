import NikoCore
import SwiftUI

/// Half a year of work, from every connected agent's hooks: a day per square,
/// what the last week was made of, and which tools did the work. Agents that
/// write no token log (Cursor, Gemini CLI, Kiro…) show up here too.
struct ActivitySection: View {
    var activity: ActivitySnapshot
    /// An agent id, or "all".
    var agent: String
    @Environment(\.look) private var look
    @Environment(\.isStaticPreview) private var isStaticPreview
    @State private var hoveredDay: ActivitySnapshot.Day?
    @State private var appeared = false

    private var days: [ActivitySnapshot.Day] { activity.days[agent] ?? [] }

    var body: some View {
        let week = activity.total(agent, lastDays: 7)
        let streak = activity.streak(agent)
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L("Activity, 26 weeks").uppercased()).font(look.mono(10.5, .semibold)).foregroundStyle(Theme.tertiary)
                Text(hoveredDay.map(dayText) ?? L("%lld sessions · %@ prompts · %@ tool calls in 7 days",
                                                   week.sessions, countText(week.prompts), countText(week.tools)))
                    .font(look.body(11)).foregroundStyle(hoveredDay == nil ? Theme.tertiary : Theme.secondary)
                    .lineLimit(1).contentTransition(.opacity)
                    .animation(Motion.snappy(look.motion), value: hoveredDay?.id)
                Spacer(minLength: 4)
                if streak >= 2 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill").font(.system(size: 9, weight: .bold))
                        Text(L("%lld days in a row", streak)).font(look.body(10.5, .semibold))
                    }
                    .foregroundStyle(Theme.amber)
                    .padding(.horizontal, 7).padding(.vertical, 2.5)
                    .background(Capsule().fill(Theme.amber.opacity(0.13)))
                }
            }
            HStack(alignment: .top, spacing: 22) {
                grid
                VStack(alignment: .leading, spacing: 12) {
                    if agent == "all", activity.agents.count > 1 { agents }
                    tools
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            guard !isStaticPreview else { return }
            withAnimation(Motion.smooth(look.motion).delay(0.05)) { appeared = true }
        }
    }

    // MARK: Grid

    /// Weeks as columns, Monday on top; today is the last filled square.
    private var grid: some View {
        let peak = max(days.map(\.weight).max() ?? 1, 1)
        let columns = weeks
        let cell: CGFloat = 9, gap: CGFloat = 2
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: gap) {
                ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                    Text(monthLabel(column, previous: index > 0 ? columns[index - 1] : nil))
                        .font(look.mono(8, .regular)).foregroundStyle(Theme.tertiary)
                        .fixedSize().frame(width: cell, alignment: .leading)
                }
            }
            .frame(height: 10, alignment: .leading)
            HStack(alignment: .top, spacing: gap) {
                ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { row in
                            square(column[row], peak: peak, index: index * 7 + row, cell: cell)
                        }
                    }
                }
            }
            legend(peak: peak)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Activity per day, last 26 weeks"))
    }

    @ViewBuilder
    private func square(_ day: ActivitySnapshot.Day?, peak: Int, index: Int, cell: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: look.radius(2.2), style: .continuous)
        if let day {
            let level = day.weight > 0 ? 0.22 + 0.78 * sqrt(Double(day.weight) / Double(peak)) : 0
            let isToday = day.id == days.last?.id
            shape
                .fill(day.weight > 0 ? look.accent.opacity(level) : Color.white.opacity(0.06))
                .overlay(shape.strokeBorder(Color.white.opacity(isToday ? 0.55 : (hoveredDay?.id == day.id ? 0.8 : 0)), lineWidth: 1))
                .frame(width: cell, height: cell)
                .scaleEffect(appeared || isStaticPreview ? 1 : 0.4)
                .opacity(appeared || isStaticPreview ? 1 : 0)
                .animation(isStaticPreview ? nil : Motion.smooth(look.motion).delay(Double(index) * 0.0016), value: appeared)
                .onHover { inside in
                    if inside { hoveredDay = day } else if hoveredDay?.id == day.id { hoveredDay = nil }
                }
        } else {
            Color.clear.frame(width: cell, height: cell)
        }
    }

    private func legend(peak: Int) -> some View {
        HStack(spacing: 3) {
            Text(L("less")).font(look.mono(8, .regular)).foregroundStyle(Theme.tertiary)
            ForEach([0.0, 0.3, 0.55, 0.8, 1.0], id: \.self) { level in
                RoundedRectangle(cornerRadius: look.radius(2), style: .continuous)
                    .fill(level == 0 ? Color.white.opacity(0.06) : look.accent.opacity(0.22 + 0.78 * level))
                    .frame(width: 7, height: 7)
            }
            Text(L("more")).font(look.mono(8, .regular)).foregroundStyle(Theme.tertiary)
        }
        .padding(.top, 2)
    }

    /// The days in columns of seven, Monday first; days before the first and after today are empty.
    private var weeks: [[ActivitySnapshot.Day?]] {
        guard let first = days.first, let start = Self.date(first.id) else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let lead = (calendar.component(.weekday, from: start) + 5) % 7   // Monday is 0
        var cells: [ActivitySnapshot.Day?] = Array(repeating: nil, count: lead) + days.map { $0 }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    private static func date(_ id: String) -> Date? {
        let parts = id.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// The month's short name over the first column it starts in.
    private func monthLabel(_ column: [ActivitySnapshot.Day?], previous: [ActivitySnapshot.Day?]?) -> String {
        guard let day = column.compactMap({ $0 }).first else { return "" }
        let month = day.id.split(separator: "-").dropFirst().first.map(String.init)
        let before = previous?.compactMap { $0 }.first?.id.split(separator: "-").dropFirst().first.map(String.init)
        guard let month, month != before, let number = Int(month), (1...12).contains(number) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Localization.locale
        let names = formatter.shortStandaloneMonthSymbols ?? []
        return names.count == 12 ? names[number - 1] : month
    }

    private func dayText(_ day: ActivitySnapshot.Day) -> String {
        let date = Self.date(day.id) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Localization.locale
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        if day.sessions == 0 && day.weight == 0 { return L("%@: nothing", formatter.string(from: date)) }
        return L("%@: %lld sessions, %@ prompts, %@ tool calls", formatter.string(from: date), day.sessions,
                 countText(day.prompts), countText(day.tools))
    }

    private func countText(_ count: Int) -> String {
        count >= 10_000 ? String(format: "%.0fk", Double(count) / 1000)
            : count >= 1000 ? String(format: "%.1fk", Double(count) / 1000) : "\(count)"
    }

    // MARK: Lists

    private var agents: some View {
        let ranked = activity.agents.prefix(4)
        let peak = max(ranked.map(\.sessions7).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 5) {
            Text(L("Agents, 7 days").uppercased()).font(look.mono(9.5, .semibold)).foregroundStyle(Theme.tertiary)
            ForEach(Array(ranked)) { row in
                HStack(spacing: 7) {
                    MascotView(source: row.id, size: 15)
                    Text(AgentRegistry.displayName(for: row.id)).font(look.body(11.5)).foregroundStyle(Theme.primary).lineLimit(1)
                        .frame(width: 92, alignment: .leading)
                    bar(Double(row.sessions7) / Double(peak), tint: AgentTint.color(for: row.id))
                    Text(L("%lld sessions", row.sessions7)).font(look.mono(10, .regular)).foregroundStyle(Theme.secondary)
                        .frame(width: 74, alignment: .trailing)
                }
            }
        }
    }

    @ViewBuilder
    private var tools: some View {
        let list = (activity.tools[agent] ?? []).prefix(agent == "all" && activity.agents.count > 1 ? 4 : 6)
        if !list.isEmpty {
            let peak = max(list.map(\.count).max() ?? 1, 1)
            VStack(alignment: .leading, spacing: 5) {
                Text(L("Tools, 7 days").uppercased()).font(look.mono(9.5, .semibold)).foregroundStyle(Theme.tertiary)
                ForEach(Array(list)) { tool in
                    HStack(spacing: 7) {
                        Image(systemName: Self.symbol(for: tool.name)).font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Theme.secondary).frame(width: 15)
                        Text(tool.name).font(look.mono(11, .regular)).foregroundStyle(Theme.primary).lineLimit(1)
                            .truncationMode(.middle).frame(width: 92, alignment: .leading)
                        bar(Double(tool.count) / Double(peak), tint: look.accent)
                        Text(countText(tool.count)).font(look.mono(10, .regular)).foregroundStyle(Theme.secondary)
                            .frame(width: 74, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func bar(_ fraction: Double, tint: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule().fill(LinearGradient(colors: [tint.opacity(0.65), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(4, proxy.size.width * CGFloat(appeared || isStaticPreview ? fraction : 0)))
            }
        }
        .frame(height: 5)
    }

    static func symbol(for tool: String) -> String {
        switch tool.lowercased() {
        case "bash", "shell", "run_shell_command", "execute_command": return "terminal"
        case "read", "read_file", "view": return "doc.text"
        case "edit", "write", "multiedit", "apply_patch", "str_replace", "write_file", "replace": return "pencil"
        case "grep", "glob", "search", "find", "list", "ls", "codebase_search": return "magnifyingglass"
        case "webfetch", "websearch", "web_fetch", "google_web_search": return "globe"
        case "task", "agent": return "person.2"
        case "todowrite", "todo_write", "update_plan": return "checklist"
        case let name where name.hasPrefix("mcp"): return "puzzlepiece.extension"
        default: return "wrench.and.screwdriver"
        }
    }
}
