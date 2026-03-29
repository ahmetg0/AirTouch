import SwiftUI

struct GestureListView: View {
    var body: some View {
        Form {
            Section("Hand Gestures") {
                ForEach(BuiltInGesture.allCases) { gesture in
                    HStack(spacing: 14) {
                        Image(systemName: gesture.icon)
                            .font(.title2)
                            .frame(width: 32)
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(gesture.rawValue)
                                .fontWeight(.medium)
                            Text(gesture.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
