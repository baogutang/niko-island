import NikoCore
import SwiftUI

struct UsageView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Text(L("Usage tracking arrives with the usage engine."))
            .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            .frame(maxWidth: .infinity, minHeight: 60)
    }
}
