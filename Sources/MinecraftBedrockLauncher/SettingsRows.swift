import SwiftUI

struct SettingsRow<Accessory: View>: View {
    var title: String
    var subtitle: String
    var systemImage: String
    @ViewBuilder var accessory: Accessory

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

            accessory
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }
}

struct ToggleRow: View {
    var title: String
    var subtitle: String
    var systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle, systemImage: systemImage) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }
}

struct MenuPickerRow: View {
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
    var isDisabled = false

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle, systemImage: systemImage) {
            Picker(title, selection: $selection) {
                ForEach(options) { option in
                    Text(option.title)
                        .tag(option.value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .disabled(isDisabled)
        }
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
        SettingsRow(title: title, subtitle: subtitle, systemImage: systemImage) {
            DeleteButton(
                help: title,
                isWorking: isWorking,
                isComplete: isComplete,
                isDisabled: isDisabled,
                action: action
            )
        }
    }
}

struct DeleteButton: View {
    var help: String
    var isWorking: Bool
    var isComplete = false
    var isDisabled: Bool
    var action: () -> Void

    var body: some View {
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
        .help(help)
    }
}

struct SettingsSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            VStack(spacing: 0) {
                content
            }
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
