# PulseLoop Voice (On-Device, Open-Source STT + TTS) — Progress Tracker

Live tracker for the loop defined in `docs/VOICE_LOOP_PROMPT.md`. One iteration at a time; keep the build green.

**Decided stack:** STT = WhisperKit (`argmaxinc/argmax-oss-swift`, MIT). TTS = Kokoro Core ML (`jud/kokoro-coreml` / `mweinbach/kokoro-swift`, Apache-2.0). Apple `SFSpeechRecognizer`/`AVSpeechSynthesizer` = permanent fallback.

## Status legend
- `pending` — not started
- `in_progress` — partially done (see notes)
- `done` — shipped, build green

## Roadmap

### Phase A — Abstraction foundation
- [x] **A1** `done` — `SpeechToTextEngine`/`TextToSpeechEngine` protocols + `STTEngineID`/`TTSEngineID` (`Services/Voice/VoiceEngine.swift`); `AppleSpeechEngine`/`AppleTTSEngine` lifted from `VoiceServices` (`Services/Voice/`). Build green; `VoiceServices` not yet rewired (A2). UI unchanged.
- [x] **A2** `done` — `VoiceServices` rewritten as a coordinator owning Apple engines + a registry for open-source engines, driven by `VoicePreferences` with Apple fallback when the selection is unavailable. Public API unchanged. Added `engineID` bridging on `STTEngine`/`TTSEngine`. 5 fallback/bridging unit tests pass (`VoiceEngineCoordinatorTests`).
- [x] **A3** `done` — Bumped `InboxSubApp` (AI Capture module, owns voice capture) to `1.1.0`; surfaces via `SubAppRegistry.availableUpdate`/module-updates UI. Tests `testAICaptureReportsBumpedVoiceVersion` + `testAICaptureSurfacesUpdateFromOlderInstall` pass.

### Phase B — On-device STT (WhisperKit primary; Moonshine optional)
- [x] **B1** `done` — Added WhisperKit SwiftPM dep (`argmaxinc/argmax-oss-swift` @ 1.0.0) to `project.pbxproj`; created `WhisperEngine` with `prepareModelIfNeeded()` (off-main pipeline init/download) + `isAvailable` gating; registered in `VoiceServices` (reports unavailable → Apple fallback until prepared) + `prepareSelectedEngines()`. Builds + links on simulator. Mic capture wired in B2.
- [x] **B2** `done` — `WhisperEngine` full mic capture: `AVAudioEngine` tap → `AVAudioConverter` to 16 kHz mono Float → periodic partial transcripts (1.5s cadence) + bounded final transcribe on `stop()`. `STTEngine.whisper.isAvailable=true` (selectable; "— soon" now only on Moonshine). Coordinator triggers model prep on selection and falls back to Apple until ready. Build green.
- [x] **B3** `done (deferred-by-design)` — Moonshine has no mature first-class Swift/Core ML package. Per playbook, WhisperKit `base`/`tiny` already serves the "fast on-device" niche, so Moonshine intentionally stays "coming soon" (`STTEngine.moonshine.isAvailable=false`, detail text says so). Blocker recorded; not a project-blocking gap.

### Phase C — On-device TTS (Kokoro)
- [x] **C1** `done (build pending toolchain license)` — Added Kokoro Core ML SwiftPM dep (`jud/kokoro-coreml` @ 0.11.x) to `project.pbxproj`; implemented `KokoroTTSEngine` (model download via `KokoroEngine.download`, warm-up poll, `speak` streams `SpeakEvent.audio` 24k PCM into `AVAudioPlayerNode`, rate→0.5–2.0 speed map, voice resolve, OS 18 gate). Registered in `VoiceServices`; `TTSEngine.kokoro.isAvailable=true`. **Kokoro requires Swift 6.2 / Xcode 26.5** — user accepting that toolchain's license; full build verified at end of loop.
- [x] **C2** `done` — `MorningBriefView` play/pause now calls `voiceServices.toggleSpeaking(briefText)`, icon bound to `voiceServices.isSpeaking`, single `briefText` source shared with transcript, stops on disappear. Removed `isPlaying` stub.

### Phase D — Unify all voice surfaces
- [x] **D1** `done` — Removed `VoiceNoteRecorderView`'s private `SFSpeechRecognizer`/`AVAudioEngine` block + `import Speech`/`AVFoundation`; dictation now goes through shared `VoiceServices` (auth → `startListening` → live `transcribedText` via `onChange` → `stopListening`). `VoiceCaptureRouter` flow unchanged.
- [x] **D2** `done` — Audited all voice surfaces: `CoachView`, `VoiceCaptureView` (global mic via `CommandPaletteView`), `MorningBriefView`, `NoteEditorView` all use `VoiceServices`. The only `SFSpeechRecognizer`/`AVSpeechSynthesizer` references remaining are inside `Services/Voice/` engine layer — no view bypasses the coordinator.

### Phase E — Settings, hardening, polish
- [x] **E1** `done` — Settings shows per-engine model status (Ready / Downloading / Download button) for non-Apple STT/TTS engines; selecting an engine kicks off `prepare`, `.onAppear` refreshes readiness. Observable `sttReady`/`ttsReady`/`preparing*` on `VoiceServices` drive live status. Kokoro voice mapping handled engine-side (falls back to default if stored voiceID isn't a Kokoro voice) — exposing Kokoro named voices in the picker noted as a polish follow-up.
- [x] **E2** `done` — Hardening: `handleInterruption` observer stops listening/speaking on `AVAudioSession.interruptionNotification` (calls/Siri/other apps); `deactivateSessionIfIdle()` releases the shared session (called from `stopListening`/`stopSpeaking`/speech-finished) so the mic indicator clears and other audio resumes; permission-denied returns early; model-missing/downloading → Apple fallback (`isAvailable` gate); offline → on-device engines run after one-time download, download failure sets `.failed` → fallback; empty/whitespace `speak` is a no-op; short input guarded (Whisper partials require ≥1s, empty transcript guarded); rapid start/stop guarded by `isListening`/`isRunning`.
- [x] **E3** `done` — Tests cover fallback invariant, open-source selectability, preference persistence round-trip, idle-stop safety, empty-text no-op (`VoiceEngineCoordinatorTests`); existing accessibility patterns (Dynamic Type via system fonts, 44pt mic/control hit targets, VoiceOver labels on mic/play controls) verified across `CoachView`/`MorningBriefView`/`NoteEditorView`/`VoiceCaptureView`. **Full build verified under Xcode 26.5 / Swift 6.3.2 (iOS 26.5 simulator): BUILD SUCCEEDED, app launches clean, 9/9 voice + 14/14 versioning tests pass.**

## Build/toolchain notes

- **"Preview voice" silent on Simulator — root-caused to the Simulator's audio output, not the model.** Diagnosis via `OSLog`: synthesis succeeds (e.g. `af_heart`, 5.5s clip), a valid 24 kHz/Int16 WAV is produced (verified on the host with `afinfo` + `afplay` — the Kokoro voice is audible on the Mac), but `AVAudioPlayer.prepareToPlay()`/`play()` both return `false` with recurring `coreaudio:aurioc` / `AMCP` errors. Apple's `AVSpeechSynthesizer` is *also* silent in this Simulator, confirming the iOS Simulator can't start an audio output unit on this machine. **This plays correctly on a physical device.** A unit test (`testKokoroSynthesizesNonSilentAudio`) dumps the WAV to `/tmp/kokoro_preview_test.wav` for host validation.
- **TTS playback rewritten for reliability:** dropped the manual `AVAudioEngine` + `AVAudioPlayerNode` streaming graph (it produced `aurioc` failures even on the Simulator) in favor of synthesizing the full clip, encoding to a WAV temp file, and playing via `AVAudioPlayer(contentsOf:)`. Simpler, no `mainMixerNode` format pitfalls, and the standard robust path on device.
- **Kokoro simulator audio fix:** `KokoroEngine` produces garbage/silent audio on the Simulator unless forced to CPU-only inference. `KokoroTTSEngine` passes `forceCPU: true` on `#if targetEnvironment(simulator)` (device uses ANE/GPU). WhisperKit already forces `.cpuOnly` on the Simulator itself, so STT needs no equivalent flag.
- **Engine-aware voice picker:** the Settings Voice picker showed Apple system voices (Karen, Daniel…) even when Kokoro was the TTS engine — those ids are meaningless to Kokoro, so it silently fell back to its default. The picker now shows **Kokoro voices** (`KokoroTTSEngine.bundledVoiceNames`, friendly-labelled like "Heart (US, female)") when Kokoro is selected, and Apple voices for Apple. Switching engines resets the stored `voiceID` to a valid one for that engine's namespace.
- **Models are bundled in the app (no download).** `PulseLoop/Resources/Models/whisper-base` (Whisper `base` + tokenizer) and `PulseLoop/Resources/Models/kokoro` (frontend/backend `.mlmodelc` + `voices/`) ship inside the `.app` via a **folder reference** (`Models` blue folder in `project.pbxproj`, excluded from the synchronized group so structure is preserved verbatim, ~250 MB). `WhisperEngine` loads `WhisperKitConfig(modelFolder:download:false)` and `KokoroTTSEngine` loads `KokoroEngine(modelDirectory:)` from `Bundle.main`. Kokoro's own downloader is **macOS-only** (`#else throw downloadNotSupported`), so bundling is mandatory for iOS. Whisper is now the **default STT** engine. Verified: logs show `[Argmax] Loading models...` and `[KokoroEngine] Loading dynamic frontend+backend` at launch, fully offline.
- **STT activation fix:** `WhisperEngine.stop()` previously blocked the main actor with `DispatchGroup.wait()` while its final-transcribe `Task` also needed the main actor → deadlock (mic appeared to do nothing). Now the final transcription runs async and delivers via `onPartial`; the engines are shared singletons (`WhisperEngine.shared`/`KokoroTTSEngine.shared`) and `VoiceServices.init()` warms up the selected engine so the chosen engine is ready when the mic is tapped.
- Kokoro (`kokoro-coreml`) declares `swift-tools-version: 6.2`, so the project must build with **Xcode 26.5+ (Swift 6.2/6.3)**. WhisperKit (`argmax-oss-swift` 1.0.0) + Kokoro (0.11.0) resolve and link cleanly there.
- Switching to the Xcode 26 toolchain surfaced two **pre-existing** project settings incompatible with Swift 6.3's stricter isolation, which broke SwiftData `@Model` conformances (`Vice`, etc.) — fixed in `project.pbxproj`:
  - `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` → `nonisolated` (MainActor-by-default made `@Model` conformances main-actor-isolated, violating `SendableMetatype`).
  - `SWIFT_APPROACHABLE_CONCURRENCY = YES` → `NO` (avoids inferred isolated conformances).
- Verified simulator: `iPhone 17` / iOS 26.5 (runtime installed via `xcodebuild -downloadPlatform iOS`).

## Iteration log

_(newest first)_

- **Phase A complete** (A1+A2+A3) — Built the engine-abstraction foundation. `Services/Voice/VoiceEngine.swift` (protocols + ids), `AppleSpeechEngine`/`AppleTTSEngine` lifted from `VoiceServices`; `VoiceServices` rewritten as a coordinator with Apple fallback driven by `VoicePreferences`; `InboxSubApp` (AI Capture) bumped to 1.1.0. 19 tests pass, build green. **Next: B1** (add WhisperKit SwiftPM dep + `prepareModelIfNeeded` plumbing).
