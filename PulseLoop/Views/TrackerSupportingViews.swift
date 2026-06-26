import SwiftUI
import UIKit

// MARK: - Supporting Views

struct StatCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(PulseFont.body(11))
                .foregroundStyle(PulseColors.textMuted)
                .lineLimit(1)
            Text(value)
                .font(PulseFont.bodySemibold(15))
                .foregroundStyle(PulseColors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }
}

struct DeviceRow: View {
    let icon: String
    let name: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(PulseColors.textSecondary)
                .frame(width: 30, height: 30)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(PulseFont.bodyMedium(14)).foregroundStyle(PulseColors.textPrimary)
                Text(detail).font(PulseFont.body(12)).foregroundStyle(PulseColors.textMuted)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

struct TimelineContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
    }
}

struct TimelineRow: View {
    let time: String
    let icon: String
    let title: String
    let subtitle: String
    let isDone: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(time)
                .font(PulseFont.bodySemibold(11.5))
                .foregroundStyle(PulseColors.textMuted)
                .frame(width: 40, alignment: .trailing)

            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PulseColors.textPrimary)
                .frame(width: 28, height: 28)
                .background(isDone ? PulseColors.fillMuted : PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(PulseColors.borderHairline, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(PulseFont.bodyMedium(13))
                    .foregroundStyle(PulseColors.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(PulseFont.body(11.5))
                    .foregroundStyle(PulseColors.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(PulseColors.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
        .padding(.bottom, 6)
    }
}

// MARK: - Protocol Scan Camera

struct ProtocolScanCameraView: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        init(onCapture: @escaping (UIImage) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

struct MacroBar: View {
    let label: String
    let value: Int
    let goal: Int
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(PulseFont.body(12))
                .foregroundStyle(PulseColors.textMuted)
                .frame(width: 50, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(PulseColors.fillSubtle)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * min(CGFloat(value) / CGFloat(goal), 1.0))
                }
            }
            .frame(height: 6)
            Text("\(value)g")
                .font(PulseFont.bodyMedium(11))
                .foregroundStyle(PulseColors.textSecondary)
                .frame(width: 32, alignment: .trailing)
        }
    }
}

struct MealRow: View {
    let icon: String
    let name: String
    let detail: String
    let kcal: Int
    let protein: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(PulseColors.textPrimary)
                .frame(width: 34, height: 34)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(PulseFont.bodyMedium(14)).foregroundStyle(PulseColors.textPrimary)
                Text(detail).font(PulseFont.body(12)).foregroundStyle(PulseColors.textMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(kcal) kcal").font(PulseFont.bodyMedium(13)).foregroundStyle(PulseColors.textPrimary)
                if let protein {
                    Text(protein).font(PulseFont.body(11)).foregroundStyle(PulseColors.textMuted)
                }
            }
        }
        .padding(14)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }
}

struct RoutineGridCard: View {
    let icon: String
    let title: String
    let streak: Int
    let progress: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(PulseColors.textPrimary)
                    .frame(width: 30, height: 30)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(PulseColors.textMuted)
                    Text("\(streak)d")
                        .font(PulseFont.bodySemibold(11))
                        .foregroundStyle(PulseColors.textPrimary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(PulseColors.fillSubtle)
                .clipShape(Capsule())
            }
            Text(title)
                .font(PulseFont.bodyMedium(13))
                .foregroundStyle(PulseColors.textPrimary)
                .lineLimit(1)
            Text(progress)
                .font(PulseFont.body(12))
                .foregroundStyle(PulseColors.textMuted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PulseColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
    }
}

struct AISupplementProfile {
    let name: String
    let category: String
    let defaultDose: String
    let timing: String
    let benefit: String
    let mechanism: String
    let pros: [String]
    let cons: [String]
    let bestTimeReason: String
    let interactionNotes: String
}

struct ProtocolItem: Identifiable {
    let id = UUID()
    let icon: String
    let name: String
    let dose: String
    let timing: String
    var healthBenefit: String?
}

struct GroupedProtocolSection: View {
    let title: String
    let count: String
    let items: [ProtocolItem]
    var onLog: ((ProtocolItem) -> Void)?
    var onTap: ((ProtocolItem) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.8)
                Spacer()
                Text(count)
                    .font(PulseFont.body(12))
                    .foregroundStyle(PulseColors.textFaint)
            }

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 12) {
                        Image(systemName: item.icon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(PulseColors.textPrimary)
                            .frame(width: 30, height: 30)
                            .background(PulseColors.fillSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(PulseFont.bodyMedium(14))
                                .foregroundStyle(PulseColors.textPrimary)
                            HStack(spacing: 6) {
                                Text(item.dose)
                                    .font(PulseFont.body(12))
                                    .foregroundStyle(PulseColors.textMuted)
                                if let benefit = item.healthBenefit {
                                    Text("·")
                                        .font(PulseFont.body(12))
                                        .foregroundStyle(PulseColors.textFaint)
                                    Text(benefit)
                                        .font(PulseFont.body(11))
                                        .foregroundStyle(PulseColors.accent)
                                        .lineLimit(1)
                                }
                            }
                        }
                        Spacer()
                        Button { onLog?(item) } label: {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 18))
                                .foregroundStyle(PulseColors.textMuted)
                        }
                        .buttonStyle(.plain)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(PulseColors.textFaint)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap?(item) }

                    if index < items.count - 1 {
                        Rectangle()
                            .fill(PulseColors.borderHairline)
                            .frame(height: 1)
                            .padding(.leading, 56)
                    }
                }
            }
            .background(PulseColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(PulseColors.borderHairline, lineWidth: 1)
            }
        }
    }
}
