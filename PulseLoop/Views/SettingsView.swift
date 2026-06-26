import SwiftUI
import SwiftData
import AVFoundation

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RingBLEClient.self) private var ble
    @Environment(RingSyncCoordinator.self) private var coordinator
    @Query private var profiles: [UserProfile]
    @Binding var path: NavigationPath
    @AppStorage("appAppearance") private var appearance: String = AppAppearance.system.rawValue
    @AppStorage(ComfortPrefs.reduceMotionKey) private var reduceMotion = false
    @AppStorage(ComfortPrefs.softHapticsKey) private var softHaptics = true
    @AppStorage(ComfortPrefs.quietHoursKey) private var quietHours = false
    @AppStorage(WeightUnit.storageKey) private var weightUnit: String = WeightUnit.kg.rawValue
    @State private var nameDraft: String = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SectionHeader(title: "Appearance", action: nil)
                Picker("Theme", selection: $appearance) {
                    ForEach(AppAppearance.allCases, id: \.rawValue) { option in
                        Text(option.rawValue).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 4)

                SectionHeader(title: "Comfort", action: nil)
                ComfortToggleRow(icon: "wind", title: "Reduce motion", subtitle: "Minimal animations", isOn: $reduceMotion)
                ComfortToggleRow(icon: "iphone.radiowaves.left.and.right", title: "Soft haptics", subtitle: "Gentle tactile feedback", isOn: $softHaptics)
                ComfortToggleRow(icon: "moon", title: "Quiet hours", subtitle: "Mute alerts 10pm–7am", isOn: $quietHours)

                SectionHeader(title: "Fitness", action: nil)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Weight unit")
                        .font(PulseFont.bodyMedium(14))
                        .foregroundStyle(PulseColors.textSecondary)
                    Picker("Weight unit", selection: $weightUnit) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.label).tag(unit.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

                SectionHeader(title: "Profile", action: nil)
                profileNameField

                SectionHeader(title: "Ring", action: nil)
                StatusCopy(title: "Status", body: ble.state.rawValue.capitalized)
                if ble.state == .connected {
                    StatusCopy(title: "Battery", body: ble.batteryPercent.map { "\($0)%" } ?? "--")
                    SecondaryButton(title: "Sync now", systemImage: "clock.arrow.circlepath") { coordinator.syncNow() }
                    SecondaryButton(title: "Find ring", systemImage: "bell.fill") { coordinator.findRing() }
                    SecondaryButton(title: "Disconnect", systemImage: "xmark.circle") { ble.disconnect() }
                } else {
                    if ble.state == .scanning {
                        SecondaryButton(title: "Stop scanning", systemImage: "stop.circle") { ble.stopScanning() }
                    } else {
                        SecondaryButton(title: "Scan for ring", systemImage: "dot.radiowaves.left.and.right") { ble.startScanning() }
                    }
                    if ble.hasLastKnownRing && ble.state != .reconnecting {
                        SecondaryButton(title: "Reconnect last ring", systemImage: "arrow.clockwise") { ble.connectLastKnown() }
                    }
                    if ble.state == .scanning && ble.discovered.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Scanning… wake the ring by tapping or moving it.")
                                .font(.caption)
                                .foregroundStyle(PulseColors.textMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(ble.discovered) { ring in
                        Button {
                            ble.connect(to: ring.id)
                        } label: {
                            HStack {
                                Image(systemName: ring.isLikelyRing ? "circle.hexagongrid.circle.fill" : "dot.radiowaves.left.and.right")
                                    .foregroundStyle(ring.isLikelyRing ? PulseColors.accent : PulseColors.textMuted)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ring.name).font(.subheadline.weight(.medium))
                                    if ring.isLikelyRing {
                                        Text("SMART_RING").font(.caption2).foregroundStyle(PulseColors.accent)
                                    }
                                }
                                Spacer()
                                Text("\(ring.rssi) dBm")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(PulseColors.textMuted)
                            }
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let error = ble.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(PulseColors.heartRate)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                CloudSyncSettingsSection()

                CoachSettingsSection()

                AIModelSettingsSection()

                MultiAgentSettingsSection()

                SecondaryButton(title: "AI Quality", systemImage: "chart.bar.doc.horizontal") {
                    path.append(AppRoute.coachQuality)
                }

                VoiceSettingsSection()

                SectionHeader(title: "Tools", action: nil)
                #if DEBUG
                PrimaryButton(title: "Debug", systemImage: "ladybug") {
                    path.append(AppRoute.debug)
                }
                SecondaryButton(title: "Component gallery", systemImage: "square.grid.2x2") {
                    path.append(AppRoute.componentGallery)
                }
                #endif
                SecondaryButton(title: "Sub-App Builder", systemImage: "wand.and.stars") {
                    path.append(AppRoute.subAppBuilder)
                }
                SecondaryButton(title: "My Sub-Apps", systemImage: "square.stack.3d.up") {
                    path.append(AppRoute.mySubApps)
                }
                SecondaryButton(title: "Sub-App Store", systemImage: "sparkles.rectangle.stack") {
                    path.append(AppRoute.subAppRegistry)
                }
                ModuleUpdatesRow {
                    path.append(AppRoute.moduleUpdates)
                }
                SecondaryButton(title: "AI Credits", systemImage: "creditcard") {
                    path.append(AppRoute.credits)
                }
                SecondaryButton(title: "Mood Journal (spec runtime)", systemImage: "face.smiling") {
                    path.append(SpecSubAppRoute(specID: BuiltInSpecs.moodCheckIn.id))
                }

                PrivacyDataSettingsSection()

                #if DEBUG
                SectionHeader(title: "Data", action: nil)
                SecondaryButton(title: "Clear demo data", systemImage: "trash") {
                    SeedData.clearAll(modelContext)
                    let fresh = UserProfile()
                    fresh.onboardingCompleted = true
                    fresh.baselineCompleted = true
                    modelContext.insert(fresh)
                    try? modelContext.save()
                }
                SecondaryButton(title: "Reseed demo data", systemImage: "arrow.clockwise") {
                    SeedData.clearAll(modelContext)
                    SeedData.seedDemo(modelContext, completeOnboarding: true)
                }
                #endif
            }
            .padding()
        }
        .background(PulseColors.background)
        .navigationTitle("Settings")
        .onAppear { nameDraft = profiles.first?.name ?? "" }
    }

    /// Editable display name, persisted to `UserProfile.name`. Saves on commit and
    /// when focus leaves the field, so the value the user sees always sticks.
    private var profileNameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .font(PulseFont.bodyMedium(14))
                .foregroundStyle(PulseColors.textSecondary)
            TextField("Your name", text: $nameDraft)
                .font(PulseFont.body(15))
                .foregroundStyle(PulseColors.textPrimary)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($nameFocused)
                .onSubmit { saveName() }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(PulseColors.fillSubtle, in: RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PulseRadius.medium, style: .continuous).stroke(PulseColors.borderHairline, lineWidth: 1))
                .onChange(of: nameFocused) { _, focused in if !focused { saveName() } }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func saveName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = profiles.first ?? UserProfile()
        profile.name = trimmed.isEmpty ? nil : trimmed
        profile.updatedAt = Date()
        modelContext.insert(profile)
        try? modelContext.save()
    }
}

/// Per-tier AI model picker. Each PulseLoop AI workload (Coach chat, quick tasks,
/// photo/label scan, deep analysis) routes to its own model; this lets the user
/// pick the OpenRouter model per tier. Choices persist via `UserDefaults` under the
/// keys `AIModel` resolves at call time, so changes take effect on the next request.
struct AIModelSettingsSection: View {
    var body: some View {
        VStack(spacing: 16) {
            SectionHeader(title: "AI Models", action: nil)
            ForEach(AIModel.allCases) { tier in
                AIModelTierPicker(tier: tier)
            }
        }
    }
}

private struct AIModelTierPicker: View {
    let tier: AIModel
    @State private var selection: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tier.title)
                .font(PulseFont.bodyMedium(14))
                .foregroundStyle(PulseColors.textSecondary)
            Text(tier.subtitle)
                .font(PulseFont.body(12))
                .foregroundStyle(PulseColors.textMuted)
            Picker(tier.title, selection: $selection) {
                ForEach(tier.options) { option in
                    Text(tier.optionLabel(for: option)).tag(option.slug)
                }
            }
            .pickerStyle(.menu)
            .tint(PulseColors.textPrimary)
            .onChange(of: selection) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: tier.storageKey)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .onAppear {
            selection = tier.resolvedSlug
        }
    }
}

/// Multi-agent routing controls (Sakana-style). When ON, each chat turn is
/// classified and dispatched to the best specialist model (Strategist/Researcher),
/// with the routed agent shown in the trace. When OFF, the assistant uses the
/// generalist (Assistant & chat) model for every turn — exactly the prior behavior.
struct MultiAgentSettingsSection: View {
    @State private var routingEnabled: Bool = AgentRouter.routingEnabled
    @State private var strategist: String = ""
    @State private var researcher: String = ""

    var body: some View {
        VStack(spacing: 16) {
            SectionHeader(title: "Multi-Agent Routing", action: nil)

            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $routingEnabled) {
                    Text("Route to specialist models")
                        .font(PulseFont.bodyMedium(14))
                        .foregroundStyle(PulseColors.textPrimary)
                }
                .tint(PulseColors.accent)
                Text("Pick the best model per turn — Strategist for planning, Researcher for live research, Generalist for everything else. Off uses one model for all turns.")
                    .font(PulseFont.body(12))
                    .foregroundStyle(PulseColors.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(PulseColors.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PulseColors.borderSubtle, lineWidth: 1))
            .onChange(of: routingEnabled) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: AgentRouter.routingEnabledKey)
            }

            if routingEnabled {
                rolePicker(
                    title: "Strategist",
                    subtitle: "Planning & deep reasoning",
                    selection: $strategist,
                    key: "agentRole.strategist",
                    defaultSlug: AgentRouter.strategistDefault)
                rolePicker(
                    title: "Researcher",
                    subtitle: "Live web research & synthesis",
                    selection: $researcher,
                    key: "agentRole.researcher",
                    defaultSlug: AgentRouter.researcherDefault)
            }
        }
        .onAppear {
            routingEnabled = AgentRouter.routingEnabled
            strategist = AgentRouter.resolvedSlug(forKey: "agentRole.strategist", default: AgentRouter.strategistDefault)
            researcher = AgentRouter.resolvedSlug(forKey: "agentRole.researcher", default: AgentRouter.researcherDefault)
        }
    }

    @ViewBuilder
    private func rolePicker(title: String, subtitle: String, selection: Binding<String>, key: String, defaultSlug: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(PulseFont.bodyMedium(14))
                .foregroundStyle(PulseColors.textSecondary)
            Text(subtitle)
                .font(PulseFont.body(12))
                .foregroundStyle(PulseColors.textMuted)
            Picker(title, selection: selection) {
                ForEach(AIModel.smart.options) { option in
                    Text(option.slug == defaultSlug ? "\(option.label) (recommended)" : option.label)
                        .tag(option.slug)
                }
            }
            .pickerStyle(.menu)
            .tint(PulseColors.textPrimary)
            .onChange(of: selection.wrappedValue) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: key)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

/// Full voice configuration: which STT/TTS engine to use, plus voice, speed,
/// pitch, and auto-speak for text-to-speech. Reads/writes `VoicePreferences`
/// (UserDefaults), so changes apply on the next dictation/utterance. Includes a
/// "Preview voice" button so the user can hear the current TTS settings.
struct VoiceSettingsSection: View {
    @State private var sttEngine: STTEngine = VoicePreferences.sttEngine
    @State private var ttsEngine: TTSEngine = VoicePreferences.ttsEngine
    @State private var voiceID: String = VoicePreferences.ttsVoiceID ?? ""
    @State private var sherpaModelID: String = VoicePreferences.sherpaModelID
    @State private var sherpaSpeaker: Int = VoicePreferences.sherpaSpeaker
    @State private var openAIVoice: String = VoicePreferences.openAIVoice
    @State private var openAIModel: String = VoicePreferences.openAIModel
    @State private var openAIKeyDraft: String = ""
    @State private var openAIShowKey: Bool = false
    @State private var hasSavedOpenAIKey: Bool = false
    @State private var openAIError: String?
    @State private var rate: Double = Double(VoicePreferences.ttsRate)
    @State private var pitch: Double = Double(VoicePreferences.ttsPitch)
    @State private var autoSpeak: Bool = VoicePreferences.autoSpeakReplies
    @State private var voiceBrief: Bool = VoicePreferences.voiceBriefEnabled
    @State private var voiceServices = VoiceServices()

    private let voices = VoicePreferences.availableVoices
    private let kokoroVoices = KokoroTTSEngine.bundledVoiceNames
    private let openAIKeyStore = OpenAIKeychainStore()

    var body: some View {
        VStack(spacing: 16) {
            SectionHeader(title: "Voice (STT & TTS)", action: nil)

            // Speech-to-Text engine
            VStack(alignment: .leading, spacing: 6) {
                Text("Speech-to-text engine")
                    .font(PulseFont.bodyMedium(14))
                    .foregroundStyle(PulseColors.textSecondary)
                Picker("STT engine", selection: $sttEngine) {
                    ForEach(STTEngine.allCases) { engine in
                        Text(engine.isAvailable ? engine.label : "\(engine.label) — soon").tag(engine)
                    }
                }
                .pickerStyle(.menu)
                .tint(PulseColors.textPrimary)
                .onChange(of: sttEngine) { _, newValue in
                    if newValue.isAvailable {
                        VoicePreferences.sttEngine = newValue
                        voiceServices.prepare(stt: newValue.engineID)
                    } else {
                        sttEngine = .appleOnDevice
                        VoicePreferences.sttEngine = .appleOnDevice
                    }
                }
                Text(sttEngine.detail)
                    .font(PulseFont.body(12))
                    .foregroundStyle(PulseColors.textMuted)
                sttStatusRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)

            // Text-to-Speech engine
            VStack(alignment: .leading, spacing: 6) {
                Text("Text-to-speech engine")
                    .font(PulseFont.bodyMedium(14))
                    .foregroundStyle(PulseColors.textSecondary)
                Picker("TTS engine", selection: $ttsEngine) {
                    ForEach(TTSEngine.allCases) { engine in
                        // OpenAI is always selectable so its config panel (incl. the
                        // API-key field) is reachable; it just falls back to the
                        // on-device default at runtime until a key is saved.
                        let selectable = engine.isAvailable || engine == .openai
                        Text(selectable ? engine.label : "\(engine.label) — soon").tag(engine)
                    }
                }
                .pickerStyle(.menu)
                .tint(PulseColors.textPrimary)
                .onChange(of: ttsEngine) { _, newValue in
                    if newValue.isAvailable || newValue == .openai {
                        VoicePreferences.ttsEngine = newValue
                        voiceServices.prepare(tts: newValue.engineID)
                        // The two engines use different voice id namespaces
                        // (Apple identifiers vs Kokoro names). Reset the picker
                        // to a valid default for the newly selected engine.
                        if newValue == .kokoro {
                            if !kokoroVoices.contains(voiceID) {
                                voiceID = kokoroVoices.contains("af_heart") ? "af_heart" : (kokoroVoices.first ?? "")
                                VoicePreferences.ttsVoiceID = voiceID.isEmpty ? nil : voiceID
                            }
                        } else if newValue != .openai, !voices.contains(where: { $0.identifier == voiceID }) {
                            voiceID = ""
                            VoicePreferences.ttsVoiceID = nil
                        }
                    } else {
                        ttsEngine = .appleOnDevice
                        VoicePreferences.ttsEngine = .appleOnDevice
                    }
                }
                Text(ttsEngine.detail)
                    .font(PulseFont.body(12))
                    .foregroundStyle(PulseColors.textMuted)
                ttsStatusRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)

            // Voice picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Voice")
                    .font(PulseFont.bodyMedium(14))
                    .foregroundStyle(PulseColors.textSecondary)
                if ttsEngine == .sherpa {
                    // Model A/B selector — each bundled sherpa model is a distinct voice.
                    Picker("Model", selection: $sherpaModelID) {
                        ForEach(SherpaModel.bundled) { model in
                            Text(model.label).tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(PulseColors.textPrimary)
                    .onChange(of: sherpaModelID) { _, newValue in
                        VoicePreferences.sherpaModelID = newValue
                        let model = SherpaModel.model(withID: newValue)
                        // Reset speaker to a valid one for the new model.
                        if model.speakers[sherpaSpeaker] == nil {
                            sherpaSpeaker = model.defaultSpeaker
                            VoicePreferences.sherpaSpeaker = sherpaSpeaker
                        }
                        Task { await SherpaTTSEngine.shared.selectModel(model) }
                    }
                    let model = SherpaModel.model(withID: sherpaModelID)
                    if model.speakers.count > 1 {
                        Picker("Speaker", selection: $sherpaSpeaker) {
                            ForEach(model.speakers.keys.sorted(), id: \.self) { sid in
                                Text(model.speakers[sid] ?? "Voice \(sid)").tag(sid)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(PulseColors.textPrimary)
                        .onChange(of: sherpaSpeaker) { _, newValue in
                            VoicePreferences.sherpaSpeaker = newValue
                        }
                    }
                } else if ttsEngine == .openai {
                    Picker("Voice", selection: $openAIVoice) {
                        ForEach(OpenAITTSEngine.voices, id: \.id) { voice in
                            Text(voice.label).tag(voice.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(PulseColors.textPrimary)
                    .onChange(of: openAIVoice) { _, newValue in
                        VoicePreferences.openAIVoice = newValue
                    }
                    Picker("Model", selection: $openAIModel) {
                        ForEach(OpenAITTSEngine.models, id: \.id) { model in
                            Text(model.label).tag(model.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(PulseColors.textPrimary)
                    .onChange(of: openAIModel) { _, newValue in
                        VoicePreferences.openAIModel = newValue
                    }
                    openAIKeyField
                } else if ttsEngine == .kokoro {
                    Picker("Voice", selection: $voiceID) {
                        ForEach(kokoroVoices, id: \.self) { name in
                            Text(KokoroTTSEngine.friendlyLabel(for: name)).tag(name)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(PulseColors.textPrimary)
                    .onChange(of: voiceID) { _, newValue in
                        VoicePreferences.ttsVoiceID = newValue.isEmpty ? nil : newValue
                    }
                } else {
                    Picker("Voice", selection: $voiceID) {
                        Text("System default").tag("")
                        ForEach(voices, id: \.identifier) { voice in
                            Text("\(voice.name) (\(voice.language))").tag(voice.identifier)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(PulseColors.textPrimary)
                    .onChange(of: voiceID) { _, newValue in
                        VoicePreferences.ttsVoiceID = newValue.isEmpty ? nil : newValue
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)

            // Speed
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Speed")
                        .font(PulseFont.bodyMedium(14))
                        .foregroundStyle(PulseColors.textSecondary)
                    Spacer()
                    Text(String(format: "%.2fx", rate / Double(VoicePreferences.defaultRate)))
                        .font(PulseFont.body(12).monospacedDigit())
                        .foregroundStyle(PulseColors.textMuted)
                }
                Slider(
                    value: $rate,
                    in: Double(VoicePreferences.minRate)...Double(VoicePreferences.maxRate)
                )
                .tint(PulseColors.accent)
                .onChange(of: rate) { _, newValue in
                    VoicePreferences.ttsRate = Float(newValue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)

            // Pitch
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Pitch")
                        .font(PulseFont.bodyMedium(14))
                        .foregroundStyle(PulseColors.textSecondary)
                    Spacer()
                    Text(String(format: "%.2f", pitch))
                        .font(PulseFont.body(12).monospacedDigit())
                        .foregroundStyle(PulseColors.textMuted)
                }
                Slider(
                    value: $pitch,
                    in: Double(VoicePreferences.minPitch)...Double(VoicePreferences.maxPitch)
                )
                .tint(PulseColors.accent)
                .onChange(of: pitch) { _, newValue in
                    VoicePreferences.ttsPitch = Float(newValue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)

            ComfortToggleRow(
                icon: "speaker.wave.2",
                title: "Auto-speak replies",
                subtitle: "Read each Assistant reply aloud",
                isOn: $autoSpeak
            )
            .onChange(of: autoSpeak) { _, newValue in
                VoicePreferences.autoSpeakReplies = newValue
            }

            ComfortToggleRow(
                icon: "sun.max",
                title: "Spoken daily brief",
                subtitle: "Greet me with a short brief when I open voice mode",
                isOn: $voiceBrief
            )
            .onChange(of: voiceBrief) { _, newValue in
                VoicePreferences.voiceBriefEnabled = newValue
            }

            SecondaryButton(
                title: voiceServices.isSpeaking ? "Stop preview" : "Preview voice",
                systemImage: voiceServices.isSpeaking ? "stop.fill" : "play.fill"
            ) {
                if voiceServices.isSpeaking {
                    voiceServices.stopSpeaking()
                } else {
                    let previewVoiceID: String?
                    switch ttsEngine {
                    case .sherpa: previewVoiceID = String(sherpaSpeaker)
                    case .openai: previewVoiceID = openAIVoice
                    default: previewVoiceID = voiceID.isEmpty ? nil : voiceID
                    }
                    voiceServices.speak(
                        "Hi, I'm your PulseLoop assistant. This is how I'll sound when I read your insights aloud.",
                        rate: Float(rate),
                        pitch: Float(pitch),
                        voiceID: previewVoiceID
                    )
                }
            }
        }
        .onAppear {
            voiceServices.refreshReadiness()
            voiceServices.prepare(stt: sttEngine.engineID)
            voiceServices.prepare(tts: ttsEngine.engineID)
            hasSavedOpenAIKey = openAIKeyStore.hasKey
            // Make sure the stored voice belongs to the selected engine's
            // namespace so the picker shows a valid selection.
            if ttsEngine == .kokoro, !kokoroVoices.contains(voiceID) {
                voiceID = kokoroVoices.contains("af_heart") ? "af_heart" : (kokoroVoices.first ?? "")
                VoicePreferences.ttsVoiceID = voiceID.isEmpty ? nil : voiceID
            }
        }
    }

    /// OpenAI API-key field shown when the OpenAI TTS engine is selected. The key
    /// is stored only in the device Keychain (`OpenAIKeychainStore`) and unlocks
    /// the cloud voices; until it's saved the engine falls back to on-device.
    @ViewBuilder private var openAIKeyField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Group {
                    if openAIShowKey {
                        TextField("OpenAI API key (sk-…)", text: $openAIKeyDraft)
                    } else {
                        SecureField("OpenAI API key (sk-…)", text: $openAIKeyDraft)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 14).monospaced())
                .foregroundStyle(PulseColors.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(PulseColors.cardSoft, in: Capsule())
                .overlay(Capsule().stroke(PulseColors.borderSubtle, lineWidth: 1))

                Button { openAIShowKey.toggle() } label: {
                    Image(systemName: openAIShowKey ? "eye.slash" : "eye")
                        .font(.system(size: 15))
                        .foregroundStyle(PulseColors.textMuted)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                QuickActionButton(label: hasSavedOpenAIKey ? "Update key" : "Save key", accent: true) { saveOpenAIKey() }
                    .disabled(openAIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if hasSavedOpenAIKey {
                    QuickActionButton(label: "Remove") { removeOpenAIKey() }
                }
            }

            if let openAIError {
                Text(openAIError).font(.caption).foregroundStyle(PulseColors.danger)
            } else if AIService.shared.hasAPIKey {
                Text("Using your OpenRouter key for OpenAI voices — no extra key needed. (Optional: save a dedicated OpenAI key below to call OpenAI directly.) Stored only in your device Keychain.")
                    .font(.caption).foregroundStyle(PulseColors.textMuted)
            } else if hasSavedOpenAIKey {
                Text("OpenAI key saved. OpenAI voices are unlocked. Stored only in your device Keychain.")
                    .font(.caption).foregroundStyle(PulseColors.textMuted)
            } else {
                Text("OpenAI voices are cloud (not offline). They use your OpenRouter key automatically, or save a dedicated OpenAI key here. Stored only in your device Keychain.")
                    .font(.caption).foregroundStyle(PulseColors.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private func saveOpenAIKey() {
        openAIError = nil
        do {
            try openAIKeyStore.saveKey(openAIKeyDraft)
            openAIKeyDraft = ""
            hasSavedOpenAIKey = true
            voiceServices.prepare(tts: .openai)
        } catch {
            openAIError = error.localizedDescription
        }
    }

    private func removeOpenAIKey() {
        openAIError = nil
        do {
            try openAIKeyStore.deleteKey()
            hasSavedOpenAIKey = false
            // Only fall back if OpenAI TTS is now fully unavailable (no OpenRouter
            // key to route through either).
            if ttsEngine == .openai, !TTSEngine.openai.isAvailable {
                ttsEngine = .sherpa
                VoicePreferences.ttsEngine = .sherpa
            }
        } catch {
            openAIError = error.localizedDescription
        }
    }

    /// Model status for the selected STT engine: Ready / Downloading / Download.
    @ViewBuilder private var sttStatusRow: some View {
        let id = sttEngine.engineID
        if id != .apple {
            engineStatusRow(
                ready: voiceServices.sttReady[id] ?? voiceServices.isReady(stt: id),
                preparing: voiceServices.preparingSTT.contains(id),
                onDownload: { voiceServices.prepare(stt: id) }
            )
        }
    }

    /// Model status for the selected TTS engine.
    @ViewBuilder private var ttsStatusRow: some View {
        let id = ttsEngine.engineID
        // OpenAI is a cloud engine (no model to download); its readiness is shown
        // by the key field instead, so skip the download-style status row.
        if id != .apple, id != .openai {
            engineStatusRow(
                ready: voiceServices.ttsReady[id] ?? voiceServices.isReady(tts: id),
                preparing: voiceServices.preparingTTS.contains(id),
                onDownload: { voiceServices.prepare(tts: id) }
            )
        }
    }

    @ViewBuilder
    private func engineStatusRow(ready: Bool, preparing: Bool, onDownload: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            if ready {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(PulseColors.success)
                Text("Built in · runs on-device")
                    .foregroundStyle(PulseColors.textMuted)
            } else if preparing {
                ProgressView().controlSize(.small).tint(PulseColors.accent)
                Text("Loading model… using Apple until ready")
                    .foregroundStyle(PulseColors.textMuted)
            } else {
                Image(systemName: "arrow.clockwise.circle")
                    .foregroundStyle(PulseColors.textSecondary)
                Button("Load model") { onDownload() }
                    .font(PulseFont.bodyMedium(12))
                    .foregroundStyle(PulseColors.accent)
            }
            Spacer()
        }
        .font(PulseFont.body(12))
        .padding(.top, 2)
    }
}

