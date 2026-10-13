import NikoCore
import SwiftUI

/// Usage, one agent at a time or all together: the rolling five hours, today,
/// the last seven and thirty days, the limits of the plan as far as they are
/// known, a week of bars and the models behind the numbers.
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
                    .font(look.body(12)).foregroundStyle(Theme.amber).fixedSize(horizontal: false, vertical: true)
            }
            if usage.agents.count > 2 { switcher }
            if usage.agents.isEmpty || (current.week.tokens == 0 && current.limits.isEmpty && current.fiveHours.tokens == 0) {
                if usage.failure == nil {
                    Text(usage.indexing ? L("Reading your local transcripts…")
                         : L("No usage found yet. Numbers appear after an agent has written a transcript on this Mac."))
                        .font(look.body(12.5)).foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                tiles
                if current.id == "all" { allLimits } else { limits(current) }
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
                                .font(look.body(12, .semibold))
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
            tile(L("30 days"), current.month)
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
        // Models on a plan often have no list price: then the tokens are the figure, not "$0.00".
        let unpriced = window.cost == 0 && window.tokens > 0
        return tileFrame {
            Text(title.uppercased()).font(look.mono(9.5, .semibold)).foregroundStyle(Theme.tertiary)
            Text(unpriced ? tokenText(window.tokens) : costText(window.cost))
                .font(look.title(20)).foregroundStyle(Theme.primary).lineLimit(1).minimumScaleFactor(0.7)
            Text(unpriced ? L("tokens, no list price") : L("%@ tokens", tokenText(window.tokens)))
                .font(look.body(11)).foregroundStyle(Theme.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
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
        switch window.id {
        case "tools_month": return L("Tool calls, monthly")
        case "extra_usage": return L("Extra usage")
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
            if let agent { MascotView(source: agent, size: 15) }
            Text(windowName(window)).font(look.body(12)).foregroundStyle(Theme.primary).lineLimit(1)
                .frame(width: 112, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule().fill(hot ? Theme.coral : look.accent)
                        .frame(width: max(4, proxy.size.width * CGFloat(window.usedPercent / 100)))
                }
            }
            .frame(height: 5)
            Text(String(format: "%.0f%%", window.usedPercent)).font(look.mono(12, .medium))
                .foregroundStyle(hot ? Theme.coral : Theme.primary).frame(width: 40, alignment: .trailing)
            Text(resetText(window.resetsAt)).font(look.body(11)).foregroundStyle(Theme.tertiary).lineLimit(1)
                .frame(width: 112, alignment: .trailing)
        }
    }

    /// Who the numbers come from, in a few words.
    private func sourceText(_ agent: UsageSnapshot.AgentUsage) -> String {
        let name = AgentRegistry.displayName(for: agent.id)
        switch agent.limitsSource {
        case .provider?: return agent.limitsCapturedAt.map { L("asked %@", sinceText($0)) } ?? ""
        case .statusLine?: return L("from %@'s status line", name)
        case .limitReached?: return L("%@ was turned away", name)
        case .agentFiles?, nil: return L("as %@ reports them", name)
        }
    }

    /// The provider that can be asked about an agent's plan, if there is one.
    private func lookup(for agent: String) -> (enabled: Bool, provider: String)? {
        guard let provider = ProviderLookupText.provider(agent) else { return nil }
        return (model.settings.asksProvider(agent), provider)
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
                ForEach(agent.limits) { limitRow($0, agent: nil) }
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

    /// Every agent's limits in one list.
    @ViewBuilder
    private var allLimits: some View {
        let withLimits = usage.agents.filter { $0.id != "all" && !$0.limits.isEmpty }
        if !withLimits.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(L("Limits").uppercased()).font(look.mono(10.5, .semibold)).foregroundStyle(Theme.tertiary)
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
                    Text(String(day.id.suffix(2))).font(look.mono(9, .regular)).foregroundStyle(Theme.tertiary)
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
            Text(L("By model, last 7 days").uppercased()).font(look.mono(10.5, .semibold)).foregroundStyle(Theme.tertiary)
            ForEach(Array(current.models.prefix(4).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    MascotView(source: row.agent, size: 16)
                    Text(row.model).font(look.mono(12)).foregroundStyle(Theme.primary).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text(tokenText(row.tokens)).font(look.mono(11, .regular)).foregroundStyle(Theme.secondary)
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
        default: return nil
        }
    }

    static func problem(_ state: ProviderLimitsClient.State, agent: String) -> String? {
        let codex = agent == ProviderLimitsClient.codex
        switch state {
        case .ok: return nil
        case .noLogin:
            return codex ? L("Codex has not signed in with a ChatGPT plan on this Mac, so there is nothing to ask with.")
                : L("Claude Code has not signed in on this Mac, so there is nothing to ask with.")
        case .loginExpired:
            return codex ? L("Codex's sign-in on this Mac has run out. It renews itself the next time Codex runs.")
                : L("Claude Code's sign-in on this Mac has run out. It renews itself the next time Claude Code runs in a terminal.")
        case .denied: return L("macOS was told not to share %@'s sign-in.", AgentRegistry.displayName(for: agent))
        case .noKey: return L("No Coding Plan key has been added yet.")
        case .unauthorized:
            return agent == ProviderLimitsClient.glm ? L("The key was not accepted.") : L("%@ did not accept the sign-in.", provider(agent) ?? "")
        case .rateLimited: return L("The provider asked for a pause. Trying again in a few minutes.")
        case .unreachable: return L("The provider could not be reached.")
        case .unreadable: return L("The provider answered in a form this version does not read.")
        }
    }
}
