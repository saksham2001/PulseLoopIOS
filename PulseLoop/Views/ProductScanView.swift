import SwiftUI
import PhotosUI
import Vision
import SwiftData

struct ProductScanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    @State private var isProcessing = false
    @State private var recognizedProduct: SupplementInfo?
    @State private var productSource: ProductSource = .localKnowledgeBase
    @State private var recognizedText: [String] = []
    @State private var showCamera = false
    @State private var isSaved = false
    @State private var manualSearchText = ""
    @State private var isSearching = false
    @State private var searchResults: [ProductSearchResult] = []
    @Query(sort: \Medication.name) private var medications: [Medication]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let image = capturedImage {
                    if isProcessing {
                        processingView(image: image)
                    } else if let product = recognizedProduct {
                        ProductCardView(image: image, product: product, allMedications: medications, source: productSource) {
                            addToProtocol(product)
                        }
                    } else if !searchResults.isEmpty {
                        searchResultsView(image: image)
                    } else {
                        unrecognizedView(image: image)
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
                if newValue != nil { processImage() }
            }
        }
    }

    // MARK: - Capture Section

    private var captureSection: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(PulseColors.textMuted)
                Text("Scan a product")
                    .font(PulseFont.title(22))
                    .foregroundStyle(PulseColors.textPrimary)
                Text("Take a photo of any food, supplement, medication, or peptide. AI will identify it and show you calories, macros, dosing, benefits, and interactions.")
                    .font(PulseFont.body(14))
                    .foregroundStyle(PulseColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            VStack(spacing: 12) {
                Button { showCamera = true } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 16))
                        Text("Take Photo")
                            .font(PulseFont.bodySemibold(15))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(PulseColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    HStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 16))
                        Text("Choose from Library")
                            .font(PulseFont.bodySemibold(15))
                    }
                    .foregroundStyle(PulseColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(PulseColors.borderHairline, lineWidth: 1)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Processing

    private func processingView(image: UIImage) -> some View {
        VStack(spacing: 20) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 250)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 6)
                .padding(.top, 30)

            VStack(spacing: 8) {
                ProgressView()
                    .tint(PulseColors.accent)
                Text("Analyzing product…")
                    .font(PulseFont.bodyMedium(14))
                    .foregroundStyle(PulseColors.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Unrecognized

    private func unrecognizedView(image: UIImage) -> some View {
        VStack(spacing: 20) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.top, 30)

            VStack(spacing: 8) {
                Text("Couldn't identify this product")
                    .font(PulseFont.bodySemibold(16))
                    .foregroundStyle(PulseColors.textPrimary)

                if !recognizedText.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Detected text:")
                            .font(PulseFont.bodyMedium(12))
                            .foregroundStyle(PulseColors.textMuted)
                        Text(recognizedText.prefix(5).joined(separator: ", "))
                            .font(PulseFont.body(13))
                            .foregroundStyle(PulseColors.textSecondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("SEARCH ONLINE")
                    .font(PulseFont.bodyMedium(11))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.6)

                HStack(spacing: 10) {
                    TextField("Type product name…", text: $manualSearchText)
                        .font(PulseFont.body(14))
                        .submitLabel(.search)
                        .onSubmit { searchOnline() }

                    Button { searchOnline() } label: {
                        if isSearching {
                            ProgressView()
                                .frame(width: 32, height: 32)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(PulseColors.accent)
                                .clipShape(Circle())
                        }
                    }
                    .disabled(manualSearchText.isEmpty || isSearching)
                }
                .padding(12)
                .background(PulseColors.fillSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(PulseColors.borderHairline, lineWidth: 1)
                }
            }
            .padding(.horizontal, 20)

            Spacer()

            Button {
                capturedImage = nil
                recognizedProduct = nil
                recognizedText = []
            } label: {
                Text("Try again with camera")
                    .font(PulseFont.bodySemibold(15))
                    .foregroundStyle(PulseColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(PulseColors.fillSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    private func searchOnline() {
        guard !manualSearchText.isEmpty else { return }
        isSearching = true
        Task {
            let outcome = await ProductSearchService.searchAndPersist(query: manualSearchText, in: modelContext)
            let results = outcome.results
            if results.count == 1, let first = results.first {
                recognizedProduct = first.info
                productSource = first.source
            } else if !results.isEmpty {
                searchResults = results
            }
            isSearching = false
        }
    }

    private func searchResultsView(image: UIImage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 20)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(PulseColors.textMuted)
                    Text("FOUND \(searchResults.count) MATCHES")
                        .font(PulseFont.bodyMedium(11))
                        .foregroundStyle(PulseColors.textMuted)
                        .tracking(0.6)
                }

                VStack(spacing: 10) {
                    ForEach(Array(searchResults.enumerated()), id: \.offset) { _, result in
                        Button {
                            recognizedProduct = result.info
                            productSource = result.source
                            searchResults = []
                        } label: {
                            HStack(spacing: 12) {
                                Text(result.info.emoji)
                                    .font(.system(size: 22))
                                    .frame(width: 40, height: 40)
                                    .background(PulseColors.fillSubtle)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(result.info.name)
                                        .font(PulseFont.bodySemibold(14))
                                        .foregroundStyle(PulseColors.textPrimary)
                                    Text(result.info.benefit.prefix(60) + (result.info.benefit.count > 60 ? "…" : ""))
                                        .font(PulseFont.body(12))
                                        .foregroundStyle(PulseColors.textSecondary)
                                        .lineLimit(2)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    sourceBadge(result.source)
                                    Text(result.info.category.capitalized)
                                        .font(PulseFont.body(10))
                                        .foregroundStyle(PulseColors.textMuted)
                                }
                            }
                            .padding(12)
                            .background(PulseColors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(PulseColors.borderHairline, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    private func sourceBadge(_ source: ProductSource) -> some View {
        Text(source.rawValue)
            .font(PulseFont.bodyMedium(9))
            .foregroundStyle(sourceColor(source))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(sourceColor(source).opacity(0.1))
            .clipShape(Capsule())
    }

    private func sourceColor(_ source: ProductSource) -> Color {
        switch source {
        case .localKnowledgeBase: return PulseColors.success
        case .openFDA: return PulseColors.spo2
        case .openFoodFacts: return .orange
        case .custom: return PulseColors.textMuted
        case .aiResearch: return PulseColors.accent
        }
    }

    // MARK: - Logic

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                await MainActor.run { capturedImage = uiImage }
            }
        }
    }

    private func processImage() {
        guard let image = capturedImage, let cgImage = image.cgImage else { return }
        isProcessing = true

        let request = VNRecognizeTextRequest { request, _ in
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                DispatchQueue.main.async { isProcessing = false }
                return
            }

            let texts = observations.compactMap { $0.topCandidates(1).first?.string }
            DispatchQueue.main.async {
                recognizedText = texts
                matchProduct(from: texts)
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    private func matchProduct(from texts: [String]) {
        Task {
            let result = await ProductSearchService.searchFromOCR(texts: texts)
            if let result {
                recognizedProduct = result.info
                productSource = result.source
                isProcessing = false
            } else {
                // Broader search with all detected text — persists any discovery.
                let query = texts.prefix(5).joined(separator: " ")
                let outcome = await ProductSearchService.searchAndPersist(query: query, in: modelContext)
                let results = outcome.results
                if results.count == 1, let first = results.first {
                    recognizedProduct = first.info
                    productSource = first.source
                } else if !results.isEmpty {
                    searchResults = results
                }
                isProcessing = false
            }
        }
    }

    private func addToProtocol(_ product: SupplementInfo) {
        let existing = medications.first(where: { $0.name.lowercased() == product.name.lowercased() })
        if existing == nil {
            let cat = MedicationCategory(rawValue: product.category) ?? .supplement
            let med = Medication(
                name: product.name, dose: product.defaultDose, category: cat,
                emoji: product.emoji, timing: product.timing,
                benefit: product.benefit, mechanism: product.mechanism,
                interactionNotes: product.interactionNotes,
                bestTimeReason: product.bestTimeReason, stackNotes: product.stackNotes
            )
            modelContext.insert(med)
        }
        // Persist to the reusable custom catalog so the scan is remembered.
        CustomProductStore.upsert(
            product,
            source: productSource.rawValue,
            isAIGenerated: productSource == .aiResearch,
            citations: [],
            in: modelContext
        )
        modelContext.saveOrLog("tracker", surface: true)
        withAnimation { isSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() }
    }
}

// MARK: - Studio Product Card

struct ProductCardView: View {
    let image: UIImage
    let product: SupplementInfo
    let allMedications: [Medication]
    var source: ProductSource = .localKnowledgeBase
    let onAdd: () -> Void

    @State private var isAdded = false

    private var interactions: [Interaction] {
        SupplementKnowledge.getInteractions(
            for: product.name,
            inProtocol: allMedications.map(\.name)
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                studioImage
                productInfo
                interactionsSection
                addButton
            }
            .padding(20)
            .padding(.bottom, 40)
        }
    }

    private var studioImage: some View {
        ZStack {
            // Clean gradient background
            LinearGradient(
                colors: [Color(UIColor.secondarySystemBackground), Color(UIColor.tertiarySystemBackground)],
                startPoint: .top, endPoint: .bottom
            )

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(24)
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(PulseColors.borderHairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 8)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 10))
                Text(source.rawValue)
                    .font(PulseFont.bodyMedium(11))
            }
            .foregroundStyle(PulseColors.success)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .padding(12)
        }
    }

    private var productInfo: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(product.emoji)
                    .font(.system(size: 28))
                    .frame(width: 48, height: 48)
                    .background(categoryColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 3) {
                    Text(product.name)
                        .font(PulseFont.title(20))
                        .foregroundStyle(PulseColors.textPrimary)
                    HStack(spacing: 8) {
                        Text(product.defaultDose)
                            .font(PulseFont.bodyMedium(13))
                            .foregroundStyle(PulseColors.textSecondary)
                        Text(product.category.capitalized)
                            .font(PulseFont.bodyMedium(11))
                            .foregroundStyle(categoryColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(categoryColor.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                InfoRow(icon: "sparkles", label: "Benefit", text: product.benefit)
                InfoRow(icon: "atom", label: "Mechanism", text: product.mechanism)
                InfoRow(icon: "clock", label: "Best time", text: "\(product.timing)  -  \(product.bestTimeReason)")
            }
            .padding(14)
            .background(PulseColors.fillSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if !product.interactionNotes.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                    Text(product.interactionNotes)
                        .font(PulseFont.body(12))
                        .foregroundStyle(PulseColors.textSecondary)
                        .lineSpacing(2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var interactionsSection: some View {
        Group {
            if !interactions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 12))
                            .foregroundStyle(PulseColors.textMuted)
                        Text("INTERACTIONS WITH YOUR STACK")
                            .font(PulseFont.bodyMedium(11))
                            .foregroundStyle(PulseColors.textMuted)
                            .tracking(0.6)
                    }
                    ForEach(interactions) { interaction in
                        InteractionCard(interaction: interaction)
                    }
                }
            }
        }
    }

    private var addButton: some View {
        Button {
            withAnimation { isAdded = true }
            onAdd()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 16))
                Text(isAdded ? "Added to protocol!" : "Add to my protocol")
                    .font(PulseFont.bodySemibold(15))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(isAdded ? PulseColors.success : PulseColors.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(isAdded)
    }

    private var categoryColor: Color {
        switch product.category {
        case "vitamin", "supplement": return PulseColors.success
        case "peptide": return PulseColors.spo2
        default: return PulseColors.accent
        }
    }
}

struct InfoRow: View {
    let icon: String
    let label: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(PulseColors.textMuted)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(PulseFont.bodyMedium(10))
                    .foregroundStyle(PulseColors.textMuted)
                    .tracking(0.4)
                Text(text)
                    .font(PulseFont.body(13))
                    .foregroundStyle(PulseColors.textPrimary)
                    .lineSpacing(2)
            }
        }
    }
}

// MARK: - Camera UIKit Bridge

struct CameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        init(_ parent: CameraView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.image = img
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
