import NikoCore
import SwiftUI

func tokenText(_ count: Int) -> String {
    switch count {
    case 1_000_000_000...: return String(format: "%.1fB", Double(count) / 1_000_000_000)
    case 1_000_000...: return String(format: "%.1fM", Double(count) / 1_000_000)
    case 1_000...: return String(format: "%.1fK", Double(count) / 1_000)
    default: return "\(count)"
    }
}

func costText(_ cost: Double) -> String {
    cost > 0 && cost < 0.01 ? "<$0.01" : String(format: "$%.2f", cost)
}

struct UsageView: View {
    @ObservedObject var model: AppModel

    private var usage: UsageSnapshot { model.usage }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let failure = usage.failure {
                Text(L("Usage tracking is unavailable: %@", failure))
                    .font(.system(size: 11)).foregroundStyle(Theme.waiting).fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 10) {
                tile(L("Today"), cost: usage.todayCost, tokens: usage.todayTokens)
                tile(L("Last 7 days"), cost: usage.weekCost, tokens: usage.weekTokens)
            }
            if usage.days.contains(where: { $0.tokens > 0 }) { chart }
            if !usage.week.isEmpty { breakdown }
            if !usage.rateLimits.isEmpty { limits }
            if usage.week.isEmpty && usage.rateLimits.isEmpty && usage.failure == nil {
                Text(usage.indexing ? L("Reading your local transcripts…")
                     : L("No usage found yet. Numbers appear after an agent has written a transcript on this Mac."))
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
            footnote
        }
    }

    private func tile(_ title: String, cost: Double, tokens: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.tertiary)
            Text(costText(cost)).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Theme.primary)
            Text(L("%@ tokens", tokenText(tokens))).font(.system(size: 11)).foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
    }

    private var chart: some View {
        let peak = max(usage.days.map(\.tokens).max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(usage.days) { day in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(day.id == usage.days.last?.id ? Theme.working : Theme.working.opacity(0.4))
                        .frame(height: max(2, 44 * CGFloat(day.tokens) / CGFloat(peak)))
                    Text(String(day.id.suffix(2))).font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.tertiary)
                }
                .frame(maxWidth: .infinity)
                .help("\(day.id): \(costText(day.cost)), \(tokenText(day.tokens))")
            }
        }
        .frame(height: 60, alignment: .bottom)
        .accessibilityLabel(L("Tokens per day, last 7 days"))
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L("By model, last 7 days").uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.tertiary)
            ForEach(Array(usage.week.prefix(6).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    Image(systemName: AgentRegistry.symbol(for: row.agent)).font(.system(size: 11)).foregroundStyle(Theme.secondary).frame(width: 16)
                    Text(row.model).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.primary).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text(tokenText(row.tokens)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.secondary)
                    Text(costText(row.cost)).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.primary)
                        .frame(minWidth: 54, alignment: .trailing)
                }
            }
            if usage.week.count > 6 {
                Text(L("+ %lld more", usage.week.count - 6)).font(.system(size: 11)).foregroundStyle(Theme.tertiary)
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
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Claude rate limits").uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.tertiary)
            ForEach(usage.rateLimits) { window in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(windowName(window.id)).font(.system(size: 12)).foregroundStyle(Theme.primary)
                        Spacer()
                        Text(String(format: "%.0f%%", window.usedPercent)).font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(window.usedPercent >= 85 ? Theme.attention : Theme.primary)
                        Text(resetText(window.resetsAt)).font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.10))
                            Capsule().fill(window.usedPercent >= 85 ? Theme.attention : Theme.working)
                                .frame(width: max(3, proxy.size.width * CGFloat(window.usedPercent / 100)))
                        }
                    }
                    .frame(height: 5)
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
        .font(.system(size: 10.5)).foregroundStyle(Theme.tertiary).fixedSize(horizontal: false, vertical: true)
    }
}
