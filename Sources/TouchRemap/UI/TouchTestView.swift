import SwiftUI

/// Live view of the fingers on the panel, drawn in the mapped display's aspect ratio.
struct TouchTestView: View {
    let controller: DeviceController

    var body: some View {
        let size = controller.display?.bounds.size ?? CGSize(width: 16, height: 9)
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Touch test")).font(.caption).foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                    if controller.contacts.isEmpty {
                        Text(L("Touch the screen to see your fingers here"))
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    ForEach(controller.contacts, id: \.id) { c in
                        Circle()
                            .fill(Color.accentColor.opacity(0.85))
                            .frame(width: 18, height: 18)
                            .position(x: c.x * geo.size.width, y: c.y * geo.size.height)
                    }
                }
            }
            .aspectRatio(size.width / max(size.height, 1), contentMode: .fit)
            .frame(maxHeight: 160)
        }
    }
}
