import SwiftUI
import SwiftData
import PhotosUI

struct MealScanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var capturedImage: UIImage?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isAnalyzing = false
    @State private var analysis: AIService.FoodAnalysis?
    @State private var isSaved = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let image = capturedImage {
                    if isAnalyzing {
                        analyzingView(image: image)
                    } else if let result = analysis {
                        resultView(image: image, result: result)
                    } else {
                        errorView(image: image)
                    }
                } else {
                    captureSection
                }
            }
            .background(PulseColors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(PulseColors.textMuted)
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraView(image: $capturedImage)
                    .ignoresSafeArea()
            }
            .onChange(of: selectedPhoto) { _, newValue in
                loadPhoto(newValue)
            }
            .onChange(of: capturedImage) { _, newValue in
                if newValue != nil { analyzeImage() }
            }
        }
    }

    // MARK: - Capture

    private var captureSection: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "fork.knife.circle")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(PulseColors.textMuted)

            VStack(spacing: 6) {
                Text("Snap your meal")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(PulseColors.textPrimary)
                Text("AI will identify the food and estimate calories")
                    .font(.system(size: 14))
                    .foregroundStyle(PulseColors.textMuted)
            }

            Spacer()

            VStack(spacing: 12) {
                Button { showCamera = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 15, weight: .medium))
                        Text("Take Photo")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    HStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 15, weight: .medium))
                        Text("Choose from Library")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(PulseColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Analyzing

    private func analyzingView(image: UIImage) -> some View {
        VStack(spacing: 20) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.top, 20)

            Spacer()

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text("Analyzing your meal…")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(PulseColors.textMuted)
            }

            Spacer()
        }
    }

    // MARK: - Result

    private func resultView(image: UIImage, result: AIService.FoodAnalysis) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 14) {
                    Text(result.name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(PulseColors.textPrimary)

                    if !result.description.isEmpty {
                        Text(result.description)
                            .font(.system(size: 14))
                            .foregroundStyle(PulseColors.textSecondary)
                    }

                    HStack(spacing: 0) {
                        macroCell(value: "\(result.calories)", label: "kcal", highlight: true)
                        Spacer()
                        macroCell(value: String(format: "%.0f g", result.proteinG), label: "Protein")
                        Spacer()
                        macroCell(value: String(format: "%.0f g", result.carbsG), label: "Carbs")
                        Spacer()
                        macroCell(value: String(format: "%.0f g", result.fatG), label: "Fat")
                    }
                    .padding(16)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 20)

                Spacer().frame(height: 20)

                VStack(spacing: 10) {
                    if isSaved {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.green)
                            Text("Saved to Meals")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.green)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        Button { saveMeal(result) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                Text("Log this meal")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    Button { retake() } label: {
                        Text("Retake")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(PulseColors.textMuted)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .padding(.top, 16)
        }
    }

    private func macroCell(value: String, label: String, highlight: Bool = false) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: highlight ? 22 : 16, weight: .bold))
                .foregroundStyle(PulseColors.textPrimary)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(PulseColors.textMuted)
        }
    }

    // MARK: - Error

    private func errorView(image: UIImage) -> some View {
        VStack(spacing: 20) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 20)

            Spacer()

            VStack(spacing: 8) {
                Text("Couldn't analyze this image")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PulseColors.textPrimary)
                Text("Try taking a clearer photo of your food")
                    .font(.system(size: 14))
                    .foregroundStyle(PulseColors.textMuted)
            }

            Button { retake() } label: {
                Text("Try again")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .padding(.top, 16)
    }

    // MARK: - Actions

    private func analyzeImage() {
        guard let image = capturedImage,
              let data = image.jpegData(compressionQuality: 0.6) else { return }
        isAnalyzing = true
        Task {
            let result = await AIService.shared.analyzeFoodImage(data)
            // The user may have retaken/dismissed while analysis was in flight;
            // only apply the result if the same image is still on screen.
            guard capturedImage === image else { return }
            isAnalyzing = false
            analysis = result
        }
    }

    private func saveMeal(_ result: AIService.FoodAnalysis) {
        let meal = MealLog(
            name: result.name,
            description_: result.description,
            calories: result.calories,
            proteinG: result.proteinG,
            carbsG: result.carbsG,
            fatG: result.fatG
        )
        modelContext.insert(meal)
        modelContext.saveOrLog("tracker", surface: true)
        withAnimation { isSaved = true }
    }

    private func retake() {
        capturedImage = nil
        analysis = nil
        isAnalyzing = false
        isSaved = false
        selectedPhoto = nil
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = UIImage(data: data) {
                capturedImage = img
            }
        }
    }
}
