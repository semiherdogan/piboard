import SwiftUI

struct BoardView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(TaskStatus.allCases, id: \.self) { status in
                BoardColumnView(status: status)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Board")
    }
}

private struct BoardColumnView: View {
    let status: TaskStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(status.title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}
