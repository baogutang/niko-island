import NikoCore
import SwiftUI

struct PanelView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(NikoVersion.displayName).font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Text(L("No agents running yet."))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 96)
        }
        .foregroundStyle(.white)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.92)))
    }
}
