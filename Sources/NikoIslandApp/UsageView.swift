import NikoCore
import SwiftUI

/// Usage at a glance: two big numbers, a week of bars, the models behind them,
/// and Claude's rate-limit windows. Used inside the island and in Settings.
struct UsageView: View {
    @ObservedObject var model: AppModel

    private var usage: UsageSnapshot { model.usage }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let failure = usage.failure {
                Text(L("Usage tracking is unavailable: %@", failure))
                    .font(Theme.body(12)).foregroundStyle(Theme.amber).fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .bottom, spacing: 26) {
                stat(L("Today"), cost: usage.todayCost, tokens: usage.todayTokens)
                stat(L("Last 7 days"), cost: usage.weekCost, tokens: usage.weekTokens)
                Spacer(minLength: 12)
                if usage.days.contains(where: { $0.tokens > 0 }) { chart.frame(width: 210) }
            }
            if !usage.week.isEmpty { breakdown }
            if !usage.rateLimits.isEmpty { limits }
            if usage.week.isEmpty && usage.rateLimits.isEmpty && usage.failure == nil {
                Text(usage.indexing ? L("Reading your local transcripts…")
                     : L("No usage found yet. Numbers appear after an agent has written a transcript on this Mac."))
                    .font(Theme.body(12.5)).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
            footnote
        }
    }

    private func stat(_ title: String, cost: Double, tokens: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased()).font(Theme.mono(10.5, .semibold)).foregroundStyle(Theme.tertiary)
            Text(costText(cost)).font(Theme.title(28)).foregroundStyle(Theme.primary)
            Text(L("%@ tokens", tokenText(tokens))).font(Theme.body(12)).foregroundStyle(Theme.secondary)
        }
        .fixedSize()
    }

    private var chart: some View {
        let peak = max(usage.days.map(\.tokens).max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(usage.days) { day in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(day.id == usage.days.last?.id ? Theme.mint : Theme.mint.opacity(0.35))
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
        VStack(alignment: .leading, spacing: 7) {
            Text(L("By model, last 7 days").uppercased()).font(Theme.mono(10.5, .semibold)).foregroundStyle(Theme.tertiary)
            ForEach(Array(usage.week.prefix(6).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    MascotView(source: row.agent, size: 18)
                    Text(row.model).font(Theme.mono(12.5)).foregroundStyle(Theme.primary).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text(tokenText(row.tokens)).font(Theme.mono(11.5, .regular)).foregroundStyle(Theme.secondary)
                    Text(costText(row.cost)).font(Theme.mono(12.5, .semibold)).foregroundStyle(Theme.primary)
                        .frame(minWidth: 62, alignment: .trailing)
                }
            }
            if usage.week.count > 6 {
                Text(L("+ %lld more", usage.week.count - 6)).font(Theme.body(11.5)).foregroundStyle(Theme.tertiary)
            }
        }
    }

    private func windowName(_ id: String) -> String {
        switch id {
        case "five_hour": return L("5-hour window")
        case "seven_day": return L("7-day window")
        default: return id.replacingOccurrences(of: "_", with: " ")
        }
    }

    private func resetText(_ date: Date?) -> String {
        guard let date else { return "" }
        let seconds = max(0, Int(date.timeIntervalSinceNow))
        if seconds >= 86_400 { return L("resets in %lldd %lldh", seconds / 86_400, (seconds % 86_400) / 3600) }
        return L("resets in %lldh %lldm", seconds / 3600, (seconds % 3600) / 60)
    }

    private var limits: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Claude rate limits").uppercased()).font(Theme.mono(10.5, .semibold)).foregroundStyle(Theme.tertiary)
            ForEach(usage.rateLimits) { window in
                let hot = window.usedPercent >= 85
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(windowName(window.id)).font(Theme.body(12.5)).foregroundStyle(Theme.primary)
                        Spacer()
                        Text(String(format: "%.0f%%", window.usedPercent)).font(Theme.mono(12.5, .semibold))
                            .foregroundStyle(hot ? Theme.coral : Theme.primary)
                        Text(resetText(window.resetsAt)).font(Theme.body(11.5)).foregroundStyle(Theme.tertiary)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.10))
                            Capsule().fill(hot ? Theme.coral : Theme.mint)
                                .frame(width: max(4, proxy.size.width * CGFloat(window.usedPercent / 100)))
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L("Costs are estimates from public list prices; your plan or invoice may differ. Counted from transcripts on this Mac only."))
            if !usage.unpricedModels.isEmpty {
                Text(L("No price known for: %@", usage.unpricedModels.prefix(4).joined(separator: ", ")))
            }
        }
        .font(Theme.body(11)).foregroundStyle(Theme.tertiary).fixedSize(horizontal: false, vertical: true)
    }
}
