import SwiftUI

struct ToggleRow: View {
    var title: String
    var subtitle: String
    var systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }
}

struct SegmentedRow: View {
    struct Option: Identifiable {
        var title: String
        var value: Int

        var id: Int {
            value
        }
    }

    var title: String
    var subtitle: String
    var systemImage: String
    @Binding var selection: Int
    var options: [Option]
    var pickerWidth: CGFloat = 176
    var isDisabled = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Picker(title, selection: $selection) {
                ForEach(options) { option in
                    Text(option.title)
                        .tag(option.value)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: pickerWidth)
            .disabled(isDisabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }
}

struct DeleteRow: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var isWorking: Bool
    var isComplete: Bool
    var isDisabled: Bool
    var action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Button(role: .destructive, action: action) {
                ZStack {
                    ProgressView()
                        .controlSize(.small)
                        .opacity(isWorking ? 1 : 0)
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .opacity(isComplete && !isWorking ? 1 : 0)
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                        .opacity(!isWorking && !isComplete ? 1 : 0)
                }
                .frame(width: 18, height: 18)
                .animation(.easeInOut(duration: 0.18), value: isWorking)
                .animation(.easeInOut(duration: 0.18), value: isComplete)
            }
            .buttonStyle(.borderless)
            .disabled(isDisabled)
            .help(title)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }
}
