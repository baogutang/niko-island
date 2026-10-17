import NikoCore
import SwiftUI

/// Usage, one agent at a time or all together: the rolling five hours, today,
/// the last seven and thirty days, the limits of the plan as far as they are
/// known, a week of bars and the models behind the numbers.
/// Used inside the island and in Settings.
struct UsageView: View {
    var model: AppModel
    @Environment(\.look) private var look
    @Environment(\.isStaticPreview) private var isStaticPreview
    /// The bar chart shows days, or the twelve months.
    @AppStorage("NikoUsageByMonth") private var byMonth = false
    @Namespace private var spanSpace

    private var usage: UsageSnapshot { model.usage }

    private var activity: ActivitySnapshot { model.activity }

    /// Agents to pick from: those with tokens or limits, then those only heard from
    /// through their hooks (Cursor, Gemini CLI and the like write no token log).
    private var agentIDs: [String] {
        var ids = usage.agents.map(\.id)
        if ids.isEmpty, !activity.isEmpty { ids = ["all"] }
        for agent in activity.agents where !ids.contains(agent.id) { ids.append(agent.id) }
        return ids
    }

    /// The agent being shown; falls back to "all" when the chosen one has nothing.
    private var current: UsageSnapshot.AgentUsage {
        if let agent = usage.agent(model.usageAgent) { return agent }
        if model.usageAgent != "all", activity.agents.contains(where: { $0.id == model.usageAgent }) {
            return UsageSnapshot.AgentUsage(id: model.usageAgent)
        }
        return usage.agent("all") ?? UsageSnapshot.AgentUsage(id: "all")
    }

    private var hasTokens: Bool {
        !(usage.agents.isEmpty || (current.week.tokens == 0 && current.limits.isEmpty && current.fiveHours.tokens == 0
                                   && (current.credits?.month ?? 0) == 0))
    }

    private var hasActivity: Bool { (activity.days[current.id] ?? []).contains { $0.sessions > 0 || $0.weight > 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let failure = usage.failure {
                Text(L("Usage tracking is unavailable: %@", failure))
                    .font(look.body(12)).foregroundStyle(Theme.amber).fixedSize(horizontal: false, vertical: true)
            }
            if agentIDs.count > 2 { switcher }
            if !hasTokens {
                if hasActivity {
                    if current.id != "all" { limits(current) }
                } else if usage.failure == nil {
                    Text(usage.indexing ? L("Reading your local transcripts…")
                         : L("No usage found yet. Numbers appear after an agent has written a transcript on this Mac."))
                        .font(look.body(12.5)).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                tiles
                if current.id == "all" { allLimits } else { limits(current) }
                HStack(alignment: .top, spacing: 22) {
                    if current.days.contains(where: { $0.tokens > 0 }) || current.months.contains(where: { $0.tokens > 0 }) {
                        chart.frame(width: 200)
                    }
                    if !current.models.isEmpty { breakdown }
                }
                if current.quarters.contains(where: { $0 > 0 }) || current.weekHours.joined().contains(where: { $0 > 0 }) {
                    HStack(alignment: .top, spacing: 22) {
                        quarterStrip
                        heatmap
                    }
                }
            }
            if !topSessions.isEmpty { topList }
            if hasActivity { ActivitySection(activity: activity, agent: current.id) }
            footnote
        }
    }

    // MARK: Switcher

    @ViewBuilder
    private var switcher: some View {
        if isStaticPreview || agentIDs.count <= 5 {
            pills
        } else {
            ScrollView(.horizontal, showsIndicators: false) { pills }
        }
    }

    private var pills: some View {
        Group {
            HStack(spacing: 6) {
                ForEach(agentIDs, id: \.self) { id in
                    let selected = id == current.id
                    Button { withAnimation(Motion.snappy(look.motion)) { model.usageAgent = id } } label: {
                        HStack(spacing: 6) {
                            if id != "all" { MascotView(source: id, size: 15, mood: selected ? .happy : .idle) }
                            Text(id == "all" ? L("All") : AgentRegistry.displayName(for: id))
                                .font(look.body(12, .semibold))
                        }
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .foregroundStyle(selected ? Color.black : Theme.primary.opacity(0.85))
                        .background {
                            if selected {
                                Capsule().fill(Color.white).matchedGeometryEffect(id: "agent-pill", in: spanSpace)
                            } else {
                                Capsule().fill(Color.white.opacity(0.10))
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle(pressed: 0.95))
                }
            }
        }
    }

    // MARK: Tiles

    @ViewBuilder
    private var tiles: some View {
        if let credits = current.credits, current.week.tokens == 0 {
            // Kiro counts in credits, not tokens.
            HStack(alignment: .top, spacing: 8) {
                creditTile(L("5 hours"), credits.fiveHours)
                creditTile(L("Today"), credits.today)
                creditTile(L("7 days"), credits.week)
                creditTile(L("30 days"), credits.month)
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                tile(L("5 hours"), current.fiveHours)
                tile(L("Today"), current.today)
                tile(L("7 days"), current.week)
                tile(L("30 days"), current.month)
            }
        }
    }

    private func creditTile(_ title: String, _ amount: Double) -> some View {
        tileFrame {
            Text(title.uppercased()).font(look.mono(9.5, .semibold)).foregroundStyle(Theme.tertiary)
            Text(amount >= 100 ? String(format: "%.0f", amount) : String(format: "%.1f", amount))
                .contentTransition(.numericText())
                .font(look.title(20)).foregroundStyle(Theme.primary).lineLimit(1).minimumScaleFactor(0.7)
            Text(L("credits")).font(look.body(11)).foregroundStyle(Theme.secondary).lineLimit(1)
        }
    }

    private func tileFrame<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: look.radius(14), style: .continuous)
        return VStack(alignment: .leading, spacing: 2) { content() }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 84, maxHeight: 84, alignment: .topLeading)
            .background(shape.fill(Theme.field))
            .overlay(shape.strokeBorder(Theme.hairline))
    }

    private func tile(_ title: String, _ window: UsageSnapshot.Window) -> some View {
        // Models on a plan often have no list price: then the tokens are the figure, not "$0.00".
        let unpriced = window.cost == 0 && window.tokens > 0
        return tileFrame {
            Text(title.uppercased()).font(look.mono(9.5, .semibold)).foregroundStyle(Theme.tertiary)
            Text(unpriced ? tokenText(window.billable) : costText(window.cost))
                .contentTransition(.numericText())
                .animation(Motion.smooth(look.motion), value: window.cost)
                .font(look.title(20)).foregroundStyle(Theme.primary).lineLimit(1).minimumScaleFactor(0.7)
            Text(unpriced ? L("tokens, no list price") : L("%@ tokens", tokenText(window.billable)))
                .font(look.body(11)).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.8)
            if window.cacheRead > 0 {
                Text(L("+ %@ read from cache", tokenText(window.cacheRead)))
                    .font(look.body(10)).foregroundStyle(Theme.tertiary).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    private func sinceText(_ date: Date) -> String {
        let now = isStaticPreview ? PreviewClock.now : Date()
        let seconds = max(0, now.timeIntervalSince(date).wholeSeconds)
        if seconds < 90 { return L("just now") }
        if seconds < 3600 { return L("%lld min ago", seconds / 60) }
        if seconds < 86_400 { return L("%lldh %lldm ago", seconds / 3600, (seconds % 3600) / 60) }
        return L("%lld days ago", seconds / 86_400)
    }

    // MARK: Limits

    private func resetText(_ date: Date?) -> String {
        guard let date else { return "" }
        let now = isStaticPreview ? PreviewClock.now : Date()
        let seconds = max(0, date.timeIntervalSince(now).wholeSeconds)
        if seconds >= 86_400 { return L("resets in %lldd %lldh", seconds / 86_400, (seconds % 86_400) / 3600) }
        return L("resets in %lldh %lldm", seconds / 3600, (seconds % 3600) / 60)
    }

    /// `mascot`: the agent's creature is drawn (in the list of every agent's limits).
    /// `capturedAt`: when the reading was made; an old one is drawn faintly, with its age instead of a pace.
    private func limitRow(_ window: RateLimitWindow, agent: String, mascot: Bool, capturedAt: Date?) -> some View {
        let level = QuotaLevel(used: window.usedPercent)
        let stale = LimitFreshness.isStale(capturedAt, now: isStaticPreview ? PreviewClock.now : Date())
        let tint = stale ? Theme.tertiary : LimitWords.color(level, accent: look.accent)
        // A pace worked out from readings that stopped coming says nothing about now.
        let outlook = isStaticPreview || stale ? nil : model.outlook(agent: agent, window: window)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                if mascot { MascotView(source: agent, size: 15) }
                Text(LimitWords.name(window)).font(look.body(12)).foregroundStyle(Theme.primary).lineLimit(1)
                    .frame(width: 112, alignment: .leading)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.10))
                        if let projected = outlook?.usedAtReset, projected > window.usedPercent + 1 {
                            // Where the pace of late leads by the reset, faintly.
                            Capsule().fill((outlook?.runsOutBeforeReset == true ? Theme.coral : tint).opacity(0.22))
                                .frame(width: max(4, proxy.size.width * CGFloat(projected / 100)))
                        }
                        Capsule().fill(tint)
                            .frame(width: max(4, proxy.size.width * CGFloat(window.usedPercent / 100)))
                    }
                    .animation(Motion.smooth(look.motion), value: window.usedPercent)
                }
                .frame(height: 5)
                Text(String(format: "%.0f%%", window.usedPercent)).font(look.mono(12, .medium))
                    .contentTransition(.numericText(value: window.usedPercent))
                    .animation(Motion.smooth(look.motion), value: window.usedPercent)
                    .foregroundStyle(stale ? Theme.tertiary : level == .ok ? Theme.primary : tint).frame(width: 40, alignment: .trailing)
                Text(resetText(window.resetsAt)).font(look.body(11)).foregroundStyle(Theme.tertiary).lineLimit(1)
                    .frame(width: 112, alignment: .trailing)
            }
            if stale, let capturedAt {
                Text(L("Last read %@", sinceText(capturedAt))).font(look.body(10.5)).foregroundStyle(Theme.tertiary)
                    .padding(.leading, (mascot ? 25 : 0) + 122)
            } else if let outlook, let text = LimitWords.outlook(outlook, window: window) {
                Text(text).font(look.body(10.5))
                    .foregroundStyle(outlook.runsOutBeforeReset && outlook.runsOutAt != nil ? Theme.amber : Theme.tertiary)
                    .padding(.leading, (mascot ? 25 : 0) + 122)
            }
        }
    }

    /// Claude Code's own figures stop coming when it is used only in the Claude app (its status
    /// line runs in a terminal). Having it look for itself keeps them current.
    @ViewBuilder
    private func staleClaudeHint(_ agent: UsageSnapshot.AgentUsage) -> some View {
        let now = isStaticPreview ? PreviewClock.now : Date()
        if agent.id == ProviderLimitsClient.claude, !agent.limits.isEmpty, LimitFreshness.isStale(agent.limitsCapturedAt, now: now),
           !model.settings.claudeAsksItself, !model.settings.claudeLimitsLookup {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L("Claude Code's status line only runs in a terminal, so in the Claude app these figures stop coming. Having Claude Code look for itself keeps them current."))
                    .font(look.body(11.5)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                smallButton(L("Keep current"), primary: true) { model.settings.claudeAsksItself = true }
            }
        }
    }

    /// Lookups the user switched on that are not answering (no key yet, a sign-in that ran out…).
    private var lookupProblems: [(agent: String, text: String, state: ProviderLimitsClient.State)] {
        model.providerLookups.compactMap { agent, result in
            guard model.settings.asksProvider(agent), let text = ProviderLookupText.problem(result.state, agent: agent) else { return nil }
            return (agent, text, result.state)
        }
        .sorted { AgentRegistry.displayName(for: $0.agent) < AgentRegistry.displayName(for: $1.agent) }
    }

    /// Who the numbers come from, in a few words.
    private func sourceText(_ agent: UsageSnapshot.AgentUsage) -> String {
        let name = AgentRegistry.displayName(for: agent.id)
        switch agent.limitsSource {
        case .provider?: return agent.limitsCapturedAt.map { L("asked %@", sinceText($0)) } ?? ""
        case .statusLine?: return agent.limitsCapturedAt.map { L("from %@'s status line, %@", name, sinceText($0)) } ?? L("from %@'s status line", name)
        case .agentCache?: return agent.limitsCapturedAt.map { L("as %@ last saw them, %@", name, sinceText($0)) } ?? ""
        case .limitReached?: return L("%@ was turned away", name)
        case .agentFiles?, nil: return L("as %@ reports them", name)
        }
    }

    /// The provider that can be asked about an agent's plan, if there is one.
    private func lookup(for agent: String) -> (enabled: Bool, provider: String)? {
        guard let provider = ProviderLookupText.provider(agent) else { return nil }
        // For Claude Code, having it look for itself counts as asking.
        let itself = agent == ProviderLimitsClient.claude && model.settings.claudeAsksItself
        return (model.settings.asksProvider(agent) || itself, provider)
    }

    private func smallButton(_ title: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(look.body(11, .semibold))
                .foregroundStyle(primary ? Color.black : Theme.primary)
                .padding(.horizontal, 9).padding(.vertical, 3.5)
                .background(Capsule().fill(primary ? Color.white : Color.white.opacity(0.13)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func openUsageSettings() {
        model.settingsPage = "usage"
        model.onOpenSettings?()
    }

    @ViewBuilder
    private func limits(_ agent: UsageSnapshot.AgentUsage) -> some View {
        let name = AgentRegistry.displayName(for: agent.id)
        let asking = lookup(for: agent.id)
        let result = model.providerLookups[agent.id]
        let resetsInApp = AgentRegistry.all.first { $0.id == agent.id }?.quotaResetInApp == true
        if !agent.limits.isEmpty || asking != nil || resetsInApp {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(L("Limits").uppercased()).font(look.mono(10, .semibold)).foregroundStyle(Theme.tertiary)
                    if !agent.limits.isEmpty {
                        Text(sourceText(agent)).font(look.body(11)).foregroundStyle(Theme.tertiary).lineLimit(1)
                    }
                    if let plan = agent.plan, !plan.isEmpty { Chip(text: plan.capitalized) }
                    Spacer(minLength: 4)
                    if let left = agent.resetsLeft, left > 0 {
                        Chip(text: agent.id == ProviderLimitsClient.codex ? L("%lld resets saved", left) : L("%lld resets left", left), tint: look.accent)
                    }
                    if asking?.enabled == true, !isStaticPreview { smallButton(L("Check now")) { model.refreshProviderLimits() } }
                    if resetsInApp {
                        smallButton(L("Reset in %@…", name)) { model.openAgentApp(agent.id) }
                            .help(L("A reset is spent in %@ itself. This only brings it to the front.", name))
                    }
                }
                ForEach(agent.limits) { limitRow($0, agent: agent.id, mascot: false, capturedAt: agent.limitsCapturedAt) }
                staleClaudeHint(agent)
                if let asking {
                    if !asking.enabled {
                        // Nothing local knows the plan's windows: say where they are and how to see them.
                        if agent.limits.isEmpty || agent.limitsSource == .limitReached {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(L("%@ keeps the plan's limits on its own servers.", name))
                                    .font(look.body(11.5)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 4)
                                smallButton(L("Show them…"), primary: true, action: openUsageSettings)
                            }
                        }
                    } else if agent.id == ProviderLimitsClient.claude, model.settings.claudeAsksItself, !model.settings.claudeLimitsLookup,
                              let text = ProviderLookupText.claudeItself(model.claudeLookup, looking: model.claudeIsLooking, problemsOnly: true) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(text).font(look.body(11.5)).foregroundStyle(Theme.amber).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                        }
                    } else if let result, let text = ProviderLookupText.problem(result.state, agent: agent.id) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(text).font(look.body(11.5)).foregroundStyle(Theme.amber).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            if result.state == .noKey || result.state == .unauthorized { smallButton(L("Settings…"), action: openUsageSettings) }
                        }
                    }
                }
            }
        }
    }

    /// Every agent's limits in one list, and the lookups that are switched on but not answering.
    @ViewBuilder
    private var allLimits: some View {
        let withLimits = usage.agents.filter { $0.id != "all" && !$0.limits.isEmpty }
        let problems = isStaticPreview ? [] : lookupProblems
        if !withLimits.isEmpty || !problems.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(L("Limits").uppercased()).font(look.mono(10.5, .semibold)).foregroundStyle(Theme.tertiary)
                ForEach(withLimits) { agent in
                    ForEach(LimitRows.shown(agent.limits)) { limitRow($0, agent: agent.id, mascot: true, capturedAt: agent.limitsCapturedAt) }
                    if let quiet = LimitRows.quiet(agent.limits) {
                        Text(L("%lld more at 0%%", quiet)).font(look.body(10.5)).foregroundStyle(Theme.tertiary)
                            .padding(.leading, 25 + 122)
                    }
                    staleClaudeHint(agent)
                }
                ForEach(problems, id: \.agent) { problem in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        MascotView(source: problem.agent, size: 15)
                        Text("\(AgentRegistry.displayName(for: problem.agent))  \(problem.text)")
                            .font(look.body(11.5)).foregroundStyle(Theme.amber).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        smallButton(L("Settings…"), action: openUsageSettings)
                    }
                }
            }
        }
    }

    // MARK: Chart and models

    private var chart: some View {
        let months = byMonth && current.months.contains(where: { $0.tokens > 0 })
        let bars = months ? current.months : current.days
        let peak = max(bars.map(\.tokens).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 8) {
            spanPicker
            HStack(alignment: .bottom, spacing: months ? 3 : 6) {
                ForEach(bars) { bar in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: look.radius(months ? 3 : 4), style: .continuous)
                            .fill(bar.id == bars.last?.id ? look.accent : look.accent.opacity(bar.tokens > 0 ? 0.35 : 0.12))
                            .frame(height: bar.tokens > 0 ? max(3, 50 * CGFloat(bar.tokens) / CGFloat(peak)) : 2)
                        Text(months ? monthLabel(bar.id) : String(bar.id.suffix(2)))
                            .font(look.mono(months ? 8 : 9, .regular)).foregroundStyle(Theme.tertiary)
                            .lineLimit(1).fixedSize()
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(bar.id): \(costText(bar.cost)), \(tokenText(bar.tokens))")
                }
            }
            .frame(height: 68, alignment: .bottom)
            .animation(Motion.smooth(), value: months)
        }
        .accessibilityLabel(months ? L("Tokens per month, last 12 months") : L("Tokens per day, last 7 days"))
    }

    /// "7 days | 12 months": a sliding white capsule, as the agent pills.
    private var spanPicker: some View {
        HStack(spacing: 2) {
            ForEach([false, true], id: \.self) { months in
                let selected = months == byMonth
                Button { withAnimation(Motion.snappy()) { byMonth = months } } label: {
                    Text(months ? L("12 months") : L("7 days"))
                        .font(look.body(10.5, .semibold))
                        .foregroundStyle(selected ? Color.black : Theme.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background {
                            if selected { Capsule().fill(Color.white).matchedGeometryEffect(id: "span", in: spanSpace) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    /// The month's initial in the app's language ("O"), or its number where months are numbered.
    private func monthLabel(_ id: String) -> String {
        let parts = id.split(separator: "-")
        guard parts.count == 2, let month = Int(parts[1]), (1...12).contains(month) else { return id }
        let formatter = DateFormatter()
        formatter.locale = Localization.locale
        // Twelve bars in 200 points: one letter fits; where months are numbered ("10月"), the number.
        let short = formatter.shortStandaloneMonthSymbols ?? []
        if short.count == 12, short[month - 1].first?.isNumber == true { return String(month) }
        let letters = formatter.veryShortStandaloneMonthSymbols ?? []
        return letters.count == 12 ? letters[month - 1] : String(month)
    }

    /// The last 24 hours in quarter hours: when the work happened today.
    private var quarterStrip: some View {
        let quarters = current.quarters
        let peak = max(quarters.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 6) {
            Text(L("Last 24 hours").uppercased()).font(look.mono(10.5, .semibold)).foregroundStyle(Theme.tertiary)
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(Array(quarters.enumerated()), id: \.offset) { index, tokens in
                    Rectangle()
                        .fill(index == quarters.count - 1 ? look.accent : look.accent.opacity(tokens > 0 ? 0.55 : 0.12))
                        .frame(width: 2, height: tokens > 0 ? max(2, 40 * CGFloat(tokens) / CGFloat(peak)) : 1)
                }
            }
            .frame(height: 40, alignment: .bottom)
            HStack {
                Text(L("24h ago")).font(look.mono(9, .regular)).foregroundStyle(Theme.tertiary)
                Spacer()
                Text(L("now")).font(look.mono(9, .regular)).foregroundStyle(Theme.tertiary)
            }
            .frame(width: 287)
        }
        .accessibilityLabel(L("Tokens per quarter hour, last 24 hours"))
    }

    /// Four weeks by weekday and hour: the rhythm of the work.
    private var heatmap: some View {
        let grid = current.weekHours.count == 7 ? current.weekHours : Array(repeating: Array(repeating: 0, count: 24), count: 7)
        let peak = max(grid.joined().max() ?? 1, 1)
        let days = [L("Mon"), L("Tue"), L("Wed"), L("Thu"), L("Fri"), L("Sat"), L("Sun")]
        return VStack(alignment: .leading, spacing: 6) {
            Text(L("When, last 4 weeks").uppercased()).font(look.mono(10.5, .semibold)).foregroundStyle(Theme.tertiary)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(0..<7, id: \.self) { row in
                    HStack(spacing: 2) {
                        Text(days[row]).font(look.mono(8.5, .regular)).foregroundStyle(Theme.tertiary).frame(width: 22, alignment: .leading)
                        ForEach(0..<24, id: \.self) { hour in
                            let tokens = grid[row][hour]
                            RoundedRectangle(cornerRadius: look.radius(1.5), style: .continuous)
                                .fill(tokens > 0 ? look.accent.opacity(0.18 + 0.82 * sqrt(Double(tokens) / Double(peak))) : Color.white.opacity(0.06))
                                .frame(width: 7, height: 7)
                        }
                    }
                }
            }
        }
        .accessibilityLabel(L("Tokens by weekday and hour, last 4 weeks"))
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(L("By model, last 7 days").uppercased()).font(look.mono(10.5, .semibold)).foregroundStyle(Theme.tertiary)
                if let rate = current.cacheHitRate {
                    Text(L("cache hits %lld%%", Int((rate * 100).rounded()))).font(look.mono(10.5, .regular)).foregroundStyle(Theme.tertiary)
                        .help(L("Prompt tokens read from the cache, out of every prompt token, in these seven days."))
                }
            }
            ForEach(Array(current.models.prefix(4).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    MascotView(source: row.agent, size: 16)
                    Text(row.model).font(look.mono(12)).foregroundStyle(Theme.primary).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text(tokenText(row.billable)).font(look.mono(11, .regular)).foregroundStyle(Theme.secondary)
                        .help(L("%@ tokens in and out, %@ more read from the cache", tokenText(row.billable), tokenText(row.cacheRead)))
                    Text(row.cost == 0 && row.tokens > 0 ? "—" : costText(row.cost)).font(look.mono(12, .semibold))
                        .foregroundStyle(row.cost == 0 ? Theme.tertiary : Theme.primary)
                        .frame(minWidth: 58, alignment: .trailing)
                }
            }
            if current.models.count > 4 {
                Text(L("+ %lld more", current.models.count - 4)).font(look.body(11.5)).foregroundStyle(Theme.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var topSessions: [UsageSnapshot.TopSession] {
        usage.topSessions.filter { current.id == "all" || $0.agent == current.id }
    }

    /// The sessions that spent the most this week.
    private var topList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Top sessions, 7 days").uppercased()).font(look.mono(10.5, .semibold)).foregroundStyle(Theme.tertiary)
            ForEach(topSessions) { row in
                HStack(spacing: 8) {
                    MascotView(source: row.agent, size: 16)
                    Text(row.project.map { ($0 as NSString).lastPathComponent } ?? AgentRegistry.displayName(for: row.agent))
                        .font(look.body(12.5, .medium)).foregroundStyle(Theme.primary).lineLimit(1)
                    Text(AgentRegistry.displayName(for: row.agent)).font(look.body(11)).foregroundStyle(Theme.tertiary).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(tokenText(row.tokens)).font(look.mono(11, .regular)).foregroundStyle(Theme.secondary)
                    Text(row.cost == 0 ? "—" : costText(row.cost)).font(look.mono(12, .semibold))
                        .foregroundStyle(row.cost == 0 ? Theme.tertiary : Theme.primary).frame(minWidth: 58, alignment: .trailing)
                }
            }
        }
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L("Costs are estimates from public list prices; your plan or invoice may differ. Counted from what the agents wrote on this Mac only."))
            if !usage.unpricedModels.isEmpty {
                Text(L("No price known for: %@", usage.unpricedModels.prefix(4).joined(separator: ", ")))
            }
        }
        .font(look.body(11)).foregroundStyle(Theme.tertiary).fixedSize(horizontal: false, vertical: true)
    }
}

/// What a lookup's outcome means, in words. Said the same way in the usage view and in Settings.
enum ProviderLookupText {
    /// Who is asked about an agent's plan.
    static func provider(_ agent: String) -> String? {
        switch agent {
        case ProviderLimitsClient.claude: return "Anthropic"
        case ProviderLimitsClient.glm: return "BigModel / Z.ai"
        case ProviderLimitsClient.codex: return "OpenAI"
        case ProviderLimitsClient.kimi: return "Kimi"
        case ProviderLimitsClient.minimax: return "MiniMax"
        case ProviderLimitsClient.gemini: return "Google"
        case ProviderLimitsClient.copilot: return "GitHub"
        case ProviderLimitsClient.cursor: return "Cursor"
        case ProviderLimitsClient.kiro: return "Kiro"
        default: return nil
        }
    }

    /// Plans asked with a key the user typed in, rather than with the agent's own sign-in.
    static func usesKey(_ agent: String) -> Bool { AppModel.keyAccounts[agent] != nil }

    /// How Claude Code's own look went, in words. `problemsOnly`: say nothing while all is well.
    static func claudeItself(_ outcome: ClaudeCodeUsage.Outcome?, looking: Bool, problemsOnly: Bool = false) -> String? {
        switch outcome {
        case nil: return problemsOnly ? nil : (looking ? L("Claude Code is looking…") : nil)
        case .fresh?: return problemsOnly ? nil : L("Claude Code looked, and the figures above are its own.")
        case .unchanged?: return L("Claude Code ran but kept no new answer. If it has never signed in on this Mac, run claude once in a terminal.")
        case .noClaudeCode?: return L("No claude program was found on this Mac.")
        case .failed?: return L("Claude Code could not be run, or took too long.")
        }
    }

    static func problem(_ state: ProviderLimitsClient.State, agent: String) -> String? {
        let codex = agent == ProviderLimitsClient.codex, gemini = agent == ProviderLimitsClient.gemini
        let copilot = agent == ProviderLimitsClient.copilot, cursor = agent == ProviderLimitsClient.cursor
        let kiro = agent == ProviderLimitsClient.kiro
        switch state {
        case .ok: return nil
        case .noLogin:
            if kiro { return L("Kiro has not signed in on this Mac, so there is nothing to ask with.") }
            if cursor { return L("Cursor's app has not signed in on this Mac, so there is nothing to ask with.") }
            if gemini { return L("Gemini CLI has not signed in with a Google account on this Mac, so there is nothing to ask with.") }
            if copilot { return L("The GitHub CLI (gh) has not signed in on this Mac, so there is nothing to ask with.") }
            return codex ? L("Codex has not signed in with a ChatGPT plan on this Mac, so there is nothing to ask with.")
                : L("Claude Code has not signed in on this Mac, so there is nothing to ask with.")
        case .loginExpired:
            if kiro { return L("Kiro's sign-in on this Mac has run out. It renews itself while Kiro runs.") }
            if cursor { return L("Cursor's sign-in on this Mac has run out. It renews itself the next time Cursor opens.") }
            if gemini { return L("Gemini CLI's sign-in on this Mac has run out. It renews itself the next time Gemini CLI runs.") }
            if copilot { return L("GitHub did not accept the GitHub CLI's sign-in. Run gh auth login to renew it.") }
            return codex ? L("Codex's sign-in on this Mac has run out. It renews itself the next time Codex runs.")
                : L("Claude Code's sign-in on this Mac has run out. It renews itself the next time Claude Code runs in a terminal.")
        case .denied: return L("macOS was told not to share %@'s sign-in.", AgentRegistry.displayName(for: agent))
        case .noKey: return L("No Coding Plan key has been added yet.")
        case .unauthorized:
            return usesKey(agent) ? L("The key was not accepted.") : L("%@ did not accept the sign-in.", provider(agent) ?? "")
        case .rateLimited: return L("The provider asked for a pause. Trying again in a few minutes.")
        case .unreachable: return L("The provider could not be reached.")
        case .unreadable: return L("The provider answered in a form this version does not read.")
        }
    }
}

/// Limits in words and colours, the same in the usage view and in notices.
enum LimitWords {
    static func name(_ window: RateLimitWindow) -> String {
        switch window.id {
        case "tools_month": return L("Tool calls, monthly")
        case "extra_usage": return L("Extra usage")
        case "copilot_premium": return L("Premium requests, monthly")
        case "copilot_chat": return L("Chat, monthly")
        case "copilot_completions": return L("Completions, monthly")
        case "cursor_total": return L("Included usage, this cycle")
        case "cursor_auto": return L("Auto, this cycle")
        case "cursor_api": return L("Named models, this cycle")
        case "cursor_on_demand": return L("On-demand spending")
        case "kiro_credits": return L("Credits, this month")
        case "kiro_trial": return L("Free-trial credits")
        case "kiro_bonus": return L("Bonus credits")
        case "daily_pro": return L("Pro models, daily")
        case "daily_flash": return L("Flash models, daily")
        case "daily_flash_lite": return L("Flash-Lite models, daily")
        case let id where id.hasPrefix("seven_day_"):
            // One model's share of the week, or a share this version has no name for.
            return L("Weekly, %@", id.dropFirst("seven_day_".count).replacingOccurrences(of: "_", with: " ").capitalized)
        default: break
        }
        switch window.minutes {
        case 300?: return L("5-hour limit")
        case 10080?: return L("Weekly limit")
        case let minutes? where minutes % 1440 == 0: return L("%lld-day limit", minutes / 1440)
        case let minutes? where minutes % 60 == 0: return L("%lld-hour limit", minutes / 60)
        default: return window.id.replacingOccurrences(of: "_", with: " ")
        }
    }


    static func color(_ level: QuotaLevel, accent: Color) -> Color {
        switch level {
        case .ok: return accent
        case .warning: return Theme.amber
        case .critical: return Theme.coral
        }
    }

    /// "1h 20m", "3d 4h": how long until a moment.
    static func span(_ seconds: Int) -> String {
        if seconds >= 86_400 { return L("%lldd %lldh", seconds / 86_400, (seconds % 86_400) / 3600) }
        if seconds >= 3600 { return L("%lldh %lldm", seconds / 3600, (seconds % 3600) / 60) }
        return L("%lld min", max(1, seconds / 60))
    }

    /// The pace of late, and where it leads, in a few words.
    static func outlook(_ outlook: QuotaOutlook, window: RateLimitWindow, now: Date = Date()) -> String? {
        let pace = outlook.pacePerHour
        guard pace > 0.05 else { return L("hardly used lately") }
        let rate = pace >= 10 ? String(format: "%.0f", pace) : String(format: "%.1f", pace)
        if outlook.runsOutBeforeReset, let at = outlook.runsOutAt {
            return L("%@%% an hour: runs out in about %@, before the reset", rate, span(max(0, at.timeIntervalSince(now).wholeSeconds)))
        }
        if let projected = outlook.usedAtReset {
            return L("%@%% an hour: about %lld%% by the reset", rate, Int(projected.rounded()))
        }
        return L("%@%% an hour", rate)
    }
}
