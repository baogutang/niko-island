import NikoCore
import SwiftUI

/// Usage, one agent at a time or all together: the rolling five hours, today,
/// the last seven days, a counter the user can reset, the limits the provider
/// reports about itself, a week of bars and the models behind the numbers.
/// Used inside the island and in Settings.
struct UsageView: View {
    @ObservedObject var model: AppModel
    @Environment(\.look) private var look
    @Environment(\.isStaticPreview) private var isStaticPreview

    private var usage: UsageSnapshot { model.usage }

    /// The agent being shown; falls back to "all" when the chosen one has nothing.
    private var current: UsageSnapshot.AgentUsage {
        usage.agent(model.usageAgent) ?? usage.agent("all") ?? UsageSnapshot.AgentUsage(id: "all")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let failure = usage.failure {
                Text(L("Usage tracking is unavailable: %@", failure))
                    .font(Theme.body(12)).foregroundStyle(Theme.amber).fixedSize(horizontal: false, vertical: true)
            }
            if usage.agents.count > 2 { switcher }
            if usage.agents.isEmpty || (current.week.tokens == 0 && current.limits.isEmpty && current.fiveHours.tokens == 0) {
                if usage.failure == nil {
                    Text(usage.indexing ? L("Reading your local transcripts…")
                         : L("No usage found yet. Numbers appear after an agent has written a transcript on this Mac."))
                        .font(Theme.body(12.5)).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                tiles
                if let since = current.resetAt {
                    Text(L("Counting since %@ (%@).", since.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Localization.locale)), sinceText(since)))
                        .font(Theme.body(11)).foregroundStyle(Theme.tertiary)
                }
                if current.id == "all" { allLimits } else if !current.limits.isEmpty { limits(current) }
                HStack(alignment: .top, spacing: 22) {
                    if current.days.contains(where: { $0.tokens > 0 }) { chart.frame(width: 200) }
                    if !current.models.isEmpty { breakdown }
                }
            }
            footnote
        }
    }

    // MARK: Switcher

    @ViewBuilder
    private var switcher: some View {
        if isStaticPreview || usage.agents.count <= 5 {
            pills
        } else {
            ScrollView(.horizontal, showsIndicators: false) { pills }
        }
    }

    private var pills: some View {
        Group {
            HStack(spacing: 6) {
                ForEach(usage.agents) { agent in
                    let selected = agent.id == current.id
                    Button { model.usageAgent = agent.id } label: {
                        HStack(spacing: 6) {
                            if agent.id != "all" { MascotView(source: agent.id, size: 15) }
                            Text(agent.id == "all" ? L("All") : AgentRegistry.displayName(for: agent.id))
                                .font(Theme.body(12, .semibold))
                        }
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .foregroundStyle(selected ? Color.black : Theme.primary.opacity(0.85))
                        .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.10)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Tiles

    private var tiles: some View {
        HStack(alignment: .top, spacing: 8) {
            tile(L("5 hours"), current.fiveHours)
            tile(L("Today"), current.today)
            tile(L("7 days"), current.week)
            resetTile
        }
    }

    private func tileFrame<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return VStack(alignment: .leading, spacing: 2) { content() }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72, alignment: .topLeading)
            .background(shape.fill(Theme.field))
            .overlay(shape.strokeBorder(Theme.hairline))
    }

    private func tile(_ title: String, _ window: UsageSnapshot.Window) -> some View {
        tileFrame {
            Text(title.uppercased()).font(Theme.mono(9.5, .semibold)).foregroundStyle(Theme.tertiary)
            Text(costText(window.cost)).font(Theme.title(20)).foregroundStyle(Theme.primary).lineLimit(1).minimumScaleFactor(0.7)
            Text(L("%@ tokens", tokenText(window.tokens))).font(Theme.body(11)).foregroundStyle(Theme.secondary).lineLimit(1)
        }
    }

    /// A counter that starts when the user says so. Nothing is deleted by it.
    private var resetTile: some View {
        tileFrame {
            HStack(spacing: 4) {
                Text(L("Since reset").uppercased()).font(Theme.mono(9.5, .semibold)).foregroundStyle(Theme.tertiary).lineLimit(1)
                Spacer(minLength: 0)
                if current.resetAt != nil {
                    Button { model.clearUsageReset(current.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.tertiary)
                            .frame(width: 14, height: 12).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L("Stop this counter"))
                    .accessibilityLabel(L("Stop this counter"))
                }
            }
            if let window = current.sinceReset, let since = current.resetAt {
                Text(costText(window.cost)).font(Theme.title(20)).foregroundStyle(look.accent).lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: 4) {
                    Text(L("%@ tokens", tokenText(window.tokens)))
                        .font(Theme.body(10.5)).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.8)
                        .help(sinceText(since))
                    Spacer(minLength: 0)
                    resetButton(primary: false)
                }
            } else {
                Text("—").font(Theme.title(20)).foregroundStyle(Theme.quaternary)
                HStack(spacing: 4) {
                    Text(L("Count from now")).font(Theme.body(10.5)).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    resetButton(primary: true)
                }
            }
        }
    }

    private func resetButton(primary: Bool) -> some View {
        Button { model.resetUsage(current.id) } label: {
            Text(L("Reset")).font(Theme.body(10.5, .semibold))
                .foregroundStyle(primary ? Color.black : Theme.primary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(primary ? Color.white : Color.white.opacity(0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func sinceText(_ date: Date) -> String {
        let now = isStaticPreview ? PreviewClock.now : Date()
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 90 { return L("just now") }
        if seconds < 3600 { return L("%lld min ago", seconds / 60) }
        if seconds < 86_400 { return L("%lldh %lldm ago", seconds / 3600, (seconds % 3600) / 60) }
        return L("%lld days ago", seconds / 86_400)
    }

    // MARK: Limits

    private func windowName(_ window: RateLimitWindow) -> String {
        switch window.minutes {
        case 300?: return L("5-hour limit")
        case 10080?: return L("Weekly limit")
        case let minutes? where minutes % 1440 == 0: return L("%lld-day limit", minutes / 1440)
        case let minutes? where minutes % 60 == 0: return L("%lld-hour limit", minutes / 60)
        default: return window.id.replacingOccurrences(of: "_", with: " ")
        }
    }

    private func resetText(_ date: Date?) -> String {
        guard let date else { return "" }
        let now = isStaticPreview ? PreviewClock.now : Date()
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        if seconds >= 86_400 { return L("resets in %lldd %lldh", seconds / 86_400, (seconds % 86_400) / 3600) }
        return L("resets in %lldh %lldm", seconds / 3600, (seconds % 3600) / 60)
    }

    private func limitRow(_ window: RateLimitWindow, agent: String?) -> some View {
        let hot = window.usedPercent >= 85
        return HStack(spacing: 10) {
            if let agent { MascotView(source: agent, size: 16) }
            Text(windowName(window)).font(Theme.body(12.5)).foregroundStyle(Theme.primary).lineLimit(1)
                .frame(width: 104, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule().fill(hot ? Theme.coral : look.accent)
                        .frame(width: max(4, proxy.size.width * CGFloat(window.usedPercent / 100)))
                }
            }
            .frame(height: 6)
            Text(String(format: "%.0f%%", window.usedPercent)).font(Theme.mono(12.5, .semibold))
                .foregroundStyle(hot ? Theme.coral : Theme.primary).frame(width: 40, alignment: .trailing)
            Text(resetText(window.resetsAt)).font(Theme.body(11)).foregroundStyle(Theme.tertiary).lineLimit(1)
                .frame(width: 112, alignment: .trailing)
        }
    }

    private func limits(_ agent: UsageSnapshot.AgentUsage) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(L("Limits, as %@ reports them", AgentRegistry.displayName(for: agent.id)).uppercased())
                    .font(Theme.mono(10.5, .semibold)).foregroundStyle(Theme.tertiary)
                if let plan = agent.plan, !plan.isEmpty { Chip(text: plan) }
            }
            ForEach(agent.limits) { limitRow($0, agent: nil) }
        }
    }

    /// Every agent's limits in one list.
    @ViewBuilder
    private var allLimits: some View {
        let withLimits = usage.agents.filter { $0.id != "all" && !$0.limits.isEmpty }
        if !withLimits.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(L("Limits").uppercased()).font(Theme.mono(10.5, .semibold)).foregroundStyle(Theme.tertiary)
                ForEach(withLimits) { agent in
                    ForEach(agent.limits) { limitRow($0, agent: agent.id) }
                }
            }
        }
    }

    // MARK: Chart and models

    private var chart: some View {
        let days = current.days
        let peak = max(days.map(\.tokens).max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(days) { day in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(day.id == days.last?.id ? look.accent : look.accent.opacity(0.35))
                        .frame(height: max(3, 50 * CGFloat(day.tokens) / CGFloat(peak)))
                    Text(String(day.id.suffix(2))).font(Theme.mono(9, .regular)).foregroundStyle(Theme.tertiary)
                }
                .frame(maxWidth: .infinity)
                .help("\(day.id): \(costText(day.cost)), \(tokenText(day.tokens))")
            }
        }
        .frame(height: 68, alignment: .bottom)
        .accessibilityLabel(L("Tokens per day, last 7 days"))
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("By model, last 7 days").uppercased()).font(Theme.mono(10.5, .semibold)).foregroundStyle(Theme.tertiary)
            ForEach(Array(current.models.prefix(4).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    MascotView(source: row.agent, size: 16)
                    Text(row.model).font(Theme.mono(12)).foregroundStyle(Theme.primary).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text(tokenText(row.tokens)).font(Theme.mono(11, .regular)).foregroundStyle(Theme.secondary)
                    Text(costText(row.cost)).font(Theme.mono(12, .semibold)).foregroundStyle(Theme.primary)
                        .frame(minWidth: 58, alignment: .trailing)
                }
            }
            if current.models.count > 4 {
                Text(L("+ %lld more", current.models.count - 4)).font(Theme.body(11.5)).foregroundStyle(Theme.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L("Costs are estimates from public list prices; your plan or invoice may differ. Counted from what the agents wrote on this Mac only."))
            if !usage.unpricedModels.isEmpty {
                Text(L("No price known for: %@", usage.unpricedModels.prefix(4).joined(separator: ", ")))
            }
        }
        .font(Theme.body(11)).foregroundStyle(Theme.tertiary).fixedSize(horizontal: false, vertical: true)
    }
}
