import SwiftUI
import PhotosUI

struct AvatarPhotoPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItem: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var originalImage: UIImage?
    @State private var selectedStyle: AvatarStyle = .original
    @State private var previewImage: UIImage?
    @State private var isEditing = false

    var existingAvatarData: Data?
    var onComplete: (Data, Bool) -> Void

    enum AvatarStyle: String, CaseIterable {
        case original = "Original"
        case lineArt = "Line Art"
        case halftone = "Halftone"
        case blackWhite = "B&W"

        var icon: String {
            switch self {
            case .original: return "photo"
            case .lineArt: return "pencil.tip"
            case .halftone: return "circle.grid.3x3.fill"
            case .blackWhite: return "circle.lefthalf.filled"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let preview = previewImage {
                    editingView(preview: preview)
                } else if isProcessing {
                    Spacer()
                    ProgressView("Processing...")
                    Spacer()
                } else if !isEditing, let data = existingAvatarData, let uiImage = UIImage(data: data) {
                    currentAvatarView(image: uiImage)
                } else {
                    emptyPickerView
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Profile Picture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: selectedItem) { _, item in
                guard let item else { return }
                loadOriginal(item)
            }
            .onChange(of: selectedStyle) { _, _ in
                applyStyle()
            }
        }
    }

    private func currentAvatarView(image: UIImage) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(PulseColors.borderHairline, lineWidth: 1)
                }

            Text("Current photo")
                .font(PulseFont.body(14))
                .foregroundStyle(PulseColors.textMuted)

            PhotosPicker(selection: $selectedItem, matching: .images) {
                Text("Change Photo")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    private func editingView(preview: UIImage) -> some View {
        VStack(spacing: 20) {
            Image(uiImage: preview)
                .resizable()
                .scaledToFill()
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(PulseColors.borderHairline, lineWidth: 1)
                }
                .padding(.top, 16)

            stylePicker

            Button {
                guard let data = preview.pngData() else { return }
                onComplete(data, selectedStyle != .original)
                dismiss()
            } label: {
                Text("Use This Photo")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 40)

            PhotosPicker(selection: $selectedItem, matching: .images) {
                Text("Choose Different Photo")
                    .font(PulseFont.body(14))
                    .foregroundStyle(PulseColors.textMuted)
            }
        }
    }

    private var emptyPickerView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "person.crop.square")
                .font(.system(size: 60, weight: .thin))
                .foregroundStyle(PulseColors.textMuted)

            Text("Choose a photo")
                .font(PulseFont.bodySemibold(18))
                .foregroundStyle(PulseColors.textPrimary)
            Text("Pick a style or keep it original")
                .font(PulseFont.body(14))
                .foregroundStyle(PulseColors.textMuted)

            PhotosPicker(selection: $selectedItem, matching: .images) {
                Text("Select Photo")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 40)
            .padding(.top, 20)
            Spacer()
        }
    }

    private var stylePicker: some View {
        HStack(spacing: 8) {
            ForEach(AvatarStyle.allCases, id: \.self) { style in
                Button {
                    selectedStyle = style
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: style.icon)
                            .font(.system(size: 16))
                        Text(style.rawValue)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(selectedStyle == style ? Color.white : PulseColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(selectedStyle == style ? Color.black : PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    private func loadOriginal(_ item: PhotosPickerItem) {
        isProcessing = true
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                await MainActor.run { isProcessing = false }
                return
            }
            await MainActor.run {
                originalImage = image
                isProcessing = false
                applyStyle()
            }
        }
    }

    private func applyStyle() {
        guard let original = originalImage else { return }
        Task {
            let processed: UIImage
            switch selectedStyle {
            case .original:
                processed = original
            case .lineArt:
                processed = ImageFilterService.lineArt(original)
            case .halftone:
                processed = ImageFilterService.halftone(original)
            case .blackWhite:
                processed = ImageFilterService.blackWhite(original)
            }
            await MainActor.run {
                previewImage = processed
            }
        }
    }
}
