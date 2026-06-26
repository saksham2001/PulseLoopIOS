# PulseLoop → On-Device, Open-Source Voice (STT + TTS) — Loop Prompt

> **How to use this file.** Paste the section titled **"THE LOOP PROMPT"** (§4) into Claude (Cursor agent) as a single message at the start of each working session. Claude does exactly one iteration, updates the tracker `docs/VOICE_PROGRESS.md`, and stops. Re-run to advance. Everything else here (Context, Architecture, Roadmap, Guardrails) is the reference the prompt points Claude at — keep it in the repo.

---

## 0. North-Star Vision (the fixed mission — never changes between iterations)

Give PulseLoop **best-in-class, fully on-device, open-source voice** — Speech-to-Text (STT) and Text-to-Speech (TTS) — that integrates **flawlessly and intuitively** into every voice surface of the app, with **zero servers, zero API keys, zero per-use cost, and full privacy** (audio never leaves the phone).

1. **On-device only, privacy-first, free.** All STT and TTS run locally via bundled/on-demand open-source models. No audio or transcript is sent to any server. No API key required for voice. Works fully offline, in airplane mode.

2. **Switchable open-source STT engines (DECIDED STACK).** Ship on-device STT the user can switch between in Settings:
   - **Whisper via WhisperKit** (`argmaxinc/argmax-oss-swift`, MIT, SwiftPM) — Core ML, runs on the Apple Neural Engine/GPU, ships **pre-converted** weights and auto-downloads the right model for the device. Use `tiny`/`base` (`openai_whisper-base`, ~80 MB) as the small default and allow `small` for stronger domain-vocabulary coverage (peptides, supplement/drug names). This is the **primary open-source engine** — no manual model conversion, mature, streaming-capable.
   - **Moonshine** (edge-built, English, tiny footprint) — **optional/secondary**. There is no first-class Swift package as mature as WhisperKit; treat Moonshine as a stretch engine (ONNX Runtime/Core ML port). WhisperKit `tiny` already covers the "tiny & fast" niche, so do NOT block the project on Moonshine — ship WhisperKit first, add Moonshine only if a clean on-device Swift path exists.
   - **Apple `SFSpeechRecognizer`** remains the always-available fallback (no model download, guaranteed to work).
   A clean `SpeechToTextEngine` protocol abstracts all engines; the active engine is a user preference. Switching never breaks any caller.

3. **Open-source on-device TTS — Kokoro (DECIDED STACK).** Augment `AVSpeechSynthesizer` with **Kokoro-82M** (Apache-2.0) running on-device via a Core ML Swift package — primary candidate **`jud/kokoro-coreml`** (Apache-2.0, SwiftPM, ~99 MB models auto-downloaded on first run, `AsyncStream` streaming, 24 kHz mono PCM, built-in Misaki G2P, no Python/MLX), with **`mweinbach/kokoro-swift`** as the alternate. Use it for natural narration of the Morning Brief and any read-aloud. **Apple's built-in voices remain the always-available fallback** when the Kokoro model isn't present yet (e.g. while downloading, or below the package's min OS). Note `jud/kokoro-coreml` targets iOS 18+; gate Kokoro behind an availability check and fall back to Apple on older OS.

4. **Flawless, intuitive integration across the whole app.** Every place that already uses voice — quick voice capture (`VoiceCaptureView`/`VoiceServices`), note dictation (`NoteEditorView`), the global mic (`CommandPaletteView`), and the Morning Brief read-aloud (`MorningBriefView`) — uses the **one** voice layer. No duplicate STT implementations. Consistent permission, waveform, partial-result, and error UX everywhere.

5. **Production-ready: every voice feature works without bugs.** Permission flows, model download/availability, offline, mid-speech cancellation, backgrounding/interruptions (calls, other audio), empty/short input, and engine switching are all handled gracefully. Never crashes, never hangs the mic, never leaks an audio session.

**Non-negotiables across every iteration:**
- The app must **always build and run** at the end of each iteration. Never leave the working tree broken.
- **On-device + open-source only for the new engines.** No cloud STT/TTS, no paid API for voice. Models must be open-source with commercially-usable licenses. **Decided stack: WhisperKit (`argmaxinc/argmax-oss-swift`, MIT) for STT; Kokoro Core ML (`jud/kokoro-coreml` or `mweinbach/kokoro-swift`, Apache-2.0) for TTS — both added via SwiftPM.** No model with a non-commercial license (e.g. XTTS-v2 Coqui CPML) and no server/GPU-class model (Dia2, Fish S2 Pro, Canary-Qwen, VibeVoice).
- **Apple APIs stay as the guaranteed fallback.** If a model is missing, downloading, or unsupported on the device, voice still works via `SFSpeechRecognizer` / `AVSpeechSynthesizer`. Voice is never fully broken.
- **One voice layer.** All STT goes through the `SpeechToTextEngine` abstraction and a single coordinator (extend `VoiceServices`); all TTS through one `TextToSpeechEngine` abstraction. **Delete/retire the duplicate `SFSpeechRecognizer` block in `NoteEditorView`** in favor of the shared layer. Do not fork parallel voice managers.
- **Design system is law.** Every screen uses `PulseColors` / `PulseFont` / `PulseRadius` / `PulseLayout` and components from `App/AppTheme.swift` + `DesignSystem/Components.swift`. Follow `.cursor/rules/design-system.mdc`. **SF Symbols only, no emoji in rendered UI. Primary buttons black, accent used sparingly, hairline-bordered cards, calm whitespace.**
- **Privacy + permissions.** Reuse the existing `NSMicrophoneUsageDescription` / `NSSpeechRecognitionUsageDescription` strings; on-device engines need no new network entitlement. Never log raw audio or transcripts.
- **Bump the module version.** Voice spans the platform; bump the relevant sub-app/module version via the existing `SubApp` / `SubAppRegistry` / `SemanticVersion` flow and record it so the per-module update flow surfaces it.
- **Backward-compatible + additive.** New services, a new settings preference, optional model assets. Never break existing capture/dictation/brief flows. Old notes/tasks/logs untouched.

---

## 1. Codebase Context (real anchors — verified; do not invent file names)

**Stack:** SwiftUI + SwiftData. Entry `PulseLoop/PulseLoopApp.swift` → `RootAppView` (`Views/RootViews.swift`). Voice is a cross-cutting platform feature, not a single tab.

### Voice — current state (the thing we're upgrading)
- **`Services/VoiceServices.swift`** — the central voice service today. `@MainActor @Observable final class VoiceServices: NSObject`.
  - **STT:** `requestSpeechAuthorization() async -> Bool`, `startListening()`, `stopListening()`; published `isListening`, `transcribedText`, `audioLevel`, `elapsedSeconds`. Uses `SFSpeechRecognizer()` + `AVAudioEngine` input-tap; partial results via `recognitionTask`; computes a crude `audioLevel` from the buffer; a `levelTimer` ticks `elapsedSeconds`.
  - **TTS:** `speak(_ text:rate:)` and `stopSpeaking()` using a single `AVSpeechSynthesizer` with `AVSpeechSynthesisVoice(language: "en-US")`; published `isSpeaking`. **This is the seam to extend with the engine abstraction — do NOT add a parallel manager.**
- **`Views/VoiceCaptureView.swift`** — the quick-capture sheet (global mic + Command Palette). Owns its own `@State private var voiceServices = VoiceServices()`; calls `requestSpeechAuthorization` → `startListening` on appear, `stopListening` on disappear; reads `transcribedText`; routes the captured text through `VoiceCaptureRouter.CapturePlan`. Has a waveform animation driven by `barLevels`/`animationTimer`.
- **`Views/NoteEditorView.swift`** — **has its OWN duplicate STT implementation** (~lines 1664–2102): private `SFSpeechRecognizer(locale:)`, `SFSpeechAudioBufferRecognitionRequest`, `SFSpeechRecognitionTask`, `transcribedText`, its own `SFSpeechRecognizer.requestAuthorization` call and start/stop dictation helpers. **This is the duplication to remove** — route note dictation through the shared `VoiceServices`/engine layer.
- **`Views/CommandPaletteView.swift`** — global mic button (`Image(systemName: "mic.fill")`, line ~335) presents `VoiceCaptureView` via `showVoiceCapture` sheet (line ~66). Onboarding row advertises "Supports voice input and natural language" (~line 862).
- **`Views/MorningBriefView.swift`** — the read-aloud surface. **Currently the player is a STUB:** `playerCard`'s button just does `isPlaying.toggle()` (line ~59) and there is a static `transcriptCard` string (~line 99). It does **not** actually call `VoiceServices.speak`. Wiring real TTS (Kokoro → Apple fallback) of the brief text here is part of the mission.
- **`Info.plist`** — already declares `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription`. Reuse them; on-device model inference needs no new usage string.

### AI / services — current state (reference only; voice must NOT depend on these for inference)
- **`Services/AIService.swift`** — `complete`, `stream`, vision; key in Keychain. **Voice STT/TTS must stay independent of any network AIService** (the whole point is on-device + offline). AIService is fine for *post-transcription* understanding (it already powers `VoiceCaptureRouter`), but never for the audio→text or text→audio step itself.

### Module / versioning — current state
- **`Platform/SubApp.swift`** — `protocol SubApp` with `var version: String { get }` (default `"1.0.0"` via extension at line ~118). `ProtocolSubApp` already declares `var version: String { "1.1.0" }` (line ~17) — mirror this pattern when bumping.
- **`Platform/SubAppRegistry.swift`** — installed-version ledger, `availableUpdate(for:)`, `modulesWithUpdates`, `applyUpdate`, version backfill. `Platform/SubAppSpec.swift` has `SemanticVersion`. **Use this existing system for the version bump; do not invent a new one.**
- **`Views/SettingsView.swift`** — `struct SettingsView`. Sections built with `SectionHeader(title:action:)` + `Picker` bound to `@AppStorage` (e.g. `appAppearance`, `WeightUnit.storageKey`). **This is where the STT engine picker + TTS toggle go** — add a "Voice" section mirroring the existing sections; persist the choice with `@AppStorage`.

### Known gaps (the work)
- STT is **forked**: `VoiceServices` and `NoteEditorView` each implement `SFSpeechRecognizer` separately (`NoteEditorView` lines ~1667/1669/2014). One canonical layer needed.
- **No open-source on-device engines wired** — only Apple's `SFSpeechRecognizer` (STT) and `AVSpeechSynthesizer` (TTS). WhisperKit/Kokoro are NOT yet added as SwiftPM dependencies (`project.pbxproj` has no `XCRemoteSwiftPackageReference`). The runtime work has not started.
- **Engine choice is half-built:** `Services/VoicePreferences.swift` already defines `STTEngine` (`appleOnDevice`/`whisper`/`moonshine`) and `TTSEngine` (`appleOnDevice`/`kokoro`) enums with `isAvailable` (currently Apple-only) + persisted prefs (engine, voice, rate, pitch, autoSpeakReplies). `SettingsView` already shows a "VOICE (STT & TTS)" section with pickers/sliders that render the non-Apple options as "— soon". **Reuse these; the loop's job is to make the "soon" engines real, then flip `isAvailable`.**
- **`VoiceServices` already honors prefs + has an `AVSpeechSynthesizerDelegate`** for accurate `isSpeaking`, plus `speak(_:rate:pitch:voiceID:)`, `stopSpeaking()`, `toggleSpeaking(_:)`. The chat bubble (`CoachView`) already has a TTS "Listen" button and optional auto-speak. **This is the seam to make multi-engine — do NOT add a parallel manager.**
- **Morning Brief TTS is a stub** — `MorningBriefView` line ~59 just does `isPlaying.toggle()`; the `transcriptCard` (~line 98) is static. It does not call `VoiceServices.speak`.
- No model packaging/availability/download wiring for the real engines; no graceful "model missing/downloading → Apple fallback" path beyond the static `isAvailable` flag.
- Module versions don't record this voice upgrade.

---

## 2. Architecture Target (what we are building toward)

### 2.1 One STT abstraction, three engines, user-switchable
- **`SpeechToTextEngine` protocol** (new, in `Services/Voice/`): a small async-streaming contract every engine implements, e.g.
  - `func requestAuthorization() async -> Bool`
  - `func startStreaming(onPartial: @escaping (String) -> Void) throws`
  - `func stop() -> String` (final transcript)
  - `var isAvailable: Bool` (model present + device supported)
  - `var displayName: String`, `var id: STTEngineID`
- **Three conformers:**
  1. `AppleSpeechEngine` — wraps the existing `SFSpeechRecognizer` + `AVAudioEngine` path lifted out of `VoiceServices`. **Always available; the guaranteed fallback.**
  2. `MoonshineEngine` — on-device Moonshine (Core ML / ONNX Runtime). **Default when its model is present.** English. Tiny footprint.
  3. `WhisperEngine` — on-device `whisper.cpp` (Core ML / Metal), e.g. `base`. Better domain-vocabulary coverage.
- **`VoiceServices` becomes the coordinator**, not the implementation: it holds the active `SpeechToTextEngine` (chosen from the user preference), exposes the SAME public surface it does today (`startListening`/`stopListening`/`transcribedText`/`audioLevel`/`isListening`) so **all existing callers keep working unchanged**, and delegates to the selected engine. If the selected engine is unavailable, it transparently falls back to `AppleSpeechEngine`.
- **Engine selection** persisted via `@AppStorage` (e.g. `"sttEngine"`), default Moonshine-if-available else Apple. A `STTEngineID` enum with stable raw values.

### 2.2 One TTS abstraction, Kokoro + Apple fallback
- **`TextToSpeechEngine` protocol** (new): `func speak(_ text: String) async`, `func stop()`, `var isSpeaking: Bool`, `var isAvailable: Bool`.
- **Two conformers:** `AppleTTSEngine` (wraps current `AVSpeechSynthesizer`, always available) and `KokoroTTSEngine` (on-device Kokoro via Core ML / ONNX). `VoiceServices.speak/stopSpeaking` delegate to the active TTS engine; Kokoro when its model is present, else Apple. Same public API as today.

### 2.3 Model packaging + availability (the on-device story — DECIDED)
- **Runtime is decided: Core ML via the chosen SwiftPM packages.** WhisperKit and Kokoro-CoreML both ship pre-converted Core ML weights and **auto-download** their model files on first use into their own caches (Application Support / HuggingFace cache). **Do not hand-convert models or vendor weights into the app bundle** — let the packages manage download. This keeps the default install small (the `.app` ships no large model) and never blocks launch.
- **Availability gating:** each engine's `isAvailable` means "package present + device OS supported + model downloaded (or downloadable)". Surface download state in Settings: a row can show "Whisper — Downloading… / Ready / Download (≈80 MB)". Until a model finishes downloading, that engine reports not-ready and the coordinator uses Apple. WhisperKit min iOS 17; `jud/kokoro-coreml` min iOS 18 — gate accordingly and fall back on older OS.
- **No secrets, no inference network.** The only network is the one-time HTTPS model download performed by the package. Audio→text and text→audio run 100% locally and work offline once the model is cached. No API key for voice, ever.
- **First-run UX:** trigger model download lazily (when the user first selects/uses the engine, or via an explicit "Download" button in Settings) on a background task; show progress; never spin the main thread; persist that the model is ready.

### 2.4 Flawless integration across every surface (the "intuitive" mission)
- **`VoiceCaptureView`** — unchanged public usage; now benefits from engine switching + better accuracy automatically. Waveform keeps working off `audioLevel`.
- **`NoteEditorView`** — **delete its private `SFSpeechRecognizer` block** and route dictation through the shared `VoiceServices`/engine layer. Identical or better UX, one code path.
- **`CommandPaletteView`** global mic — unchanged entry point, now on the unified layer.
- **`MorningBriefView`** — wire the real player: the "Brief me" button calls `VoiceServices.speak(briefText)` (Kokoro → Apple fallback), reflects `isSpeaking`, supports pause/stop, and reads the actual brief content (not the static stub string).
- **Consistent UX primitives:** one permission prompt path, one waveform/level treatment, one partial-result style, one error/empty/short-input treatment, shared across all surfaces.

### 2.5 Settings surface (already exists — extend, don't rebuild)
- `SettingsView` already has a **"VOICE (STT & TTS)"** section bound to `VoicePreferences`: STT engine picker (Apple / Whisper "— soon" / Moonshine "— soon"), TTS engine picker (Apple / Kokoro "— soon"), voice picker, Speed + Pitch sliders, auto-speak toggle, and a preview button. The loop's job is to:
  - Flip each engine's `isAvailable` to a real readiness check as the engine lands, and **drop the "— soon"** suffix once selectable.
  - Add a **Download / Downloading… / Ready** affordance per non-Apple engine (driven by the package's model state) using existing row patterns.
  - Show Kokoro's named voices when Kokoro is selected; Apple voices when Apple is selected. Changing the engine stays instant and safe (next capture/utterance uses it).

### 2.6 Version bump + update flow
- Bump the relevant module version (the platform-level/most-appropriate sub-app that owns voice; mirror `ProtocolSubApp`'s explicit `var version`). Record it so `SubAppRegistry.availableUpdate` / the module-updates UI surface it. Migrations are additive/no-op (new services + a preference don't migrate data).

### 2.7 Shared principles
- Extend `VoiceServices`; do not fork voice managers. Engines hide behind protocols.
- Apple APIs are the permanent fallback; the app's voice is never fully broken.
- Additive only: new services, one `@AppStorage` preference, optional model assets. No data migrations.
- On-device + offline for inference; no API key for voice.

---

## 2.8 Implementation Playbook (concrete recipes — this is the part that makes the models actually run)

> These are decided, copy-pasteable starting points. The exact package API may drift between versions — **read the package README/headers after adding it and adapt symbol names**; never invent API. Treat the snippets as the shape of the solution, not verbatim truth.

### Recipe S0 — Engine protocols (do this first, Phase A)
Create `Services/Voice/SpeechToTextEngine.swift` and `TextToSpeechEngine.swift`:

```swift
enum STTEngineID: String, Codable, CaseIterable { case apple, whisper, moonshine }
enum TTSEngineID: String, Codable, CaseIterable { case apple, kokoro }

@MainActor protocol SpeechToTextEngine: AnyObject {
    var id: STTEngineID { get }
    var isAvailable: Bool { get }                  // package + OS + model ready
    func requestAuthorization() async -> Bool
    func startStreaming(onPartial: @escaping (String) -> Void,
                        onLevel: @escaping (Float) -> Void) throws
    func stop() -> String                          // returns final transcript
    func prepareModelIfNeeded() async               // triggers download; no-op for Apple
}

@MainActor protocol TextToSpeechEngine: AnyObject {
    var id: TTSEngineID { get }
    var isAvailable: Bool { get }
    var isSpeaking: Bool { get }
    func speak(_ text: String, rate: Float, pitch: Float, voiceID: String?) async
    func stop()
    func prepareModelIfNeeded() async
}
```
`AppleSpeechEngine`/`AppleTTSEngine` are the existing `SFSpeechRecognizer`+`AVAudioEngine` and `AVSpeechSynthesizer` code lifted verbatim out of `VoiceServices`. `isAvailable` is always `true`. `VoiceServices` keeps its EXACT current public surface and delegates to `activeSTT`/`activeTTS`, falling back to the Apple engine whenever the selected engine's `isAvailable == false`.

### Recipe S1 — Whisper STT via WhisperKit (Phase B, primary)
1. **Add SwiftPM dep** `https://github.com/argmaxinc/argmax-oss-swift`, product **WhisperKit** (or `ArgmaxOSS`). MIT. Min iOS 17.
2. WhisperKit transcribes an **audio buffer/file**, not a live `SFSpeechAudioBufferRecognitionRequest`. So `WhisperEngine` captures mic audio with `AVAudioEngine` (reuse the existing tap that already computes `audioLevel`), accumulates 16 kHz mono `Float` samples, and:
   - **Streaming-ish UX:** periodically (e.g. every ~1–2 s of audio, or on a VAD pause) run `whisperKit.transcribe(audioArray:)` on the buffer so far and emit the text via `onPartial`. On `stop()`, run a final transcribe and return the full text. (WhisperKit also exposes streaming helpers in its CLI/AudioStreamTranscriber — prefer them if the package version exposes a public streaming API.)
   - Convert the input-node format to 16 kHz mono Float (WhisperKit's expected input) with `AVAudioConverter`.
3. **Model:** `WhisperKitConfig(model: "base")` (small default) or `"small"` for accuracy; let WhisperKit auto-download from `argmaxinc/whisperkit-coreml`. Kick the download from `prepareModelIfNeeded()` and report `isAvailable` once the pipeline initializes.
4. **Init shape:**
```swift
import WhisperKit
let pipe = try await WhisperKit(WhisperKitConfig(model: "base"))
let result = try await pipe.transcribe(audioArray: floatSamples16kMono)
let text = result.first?.text ?? ""
```
5. **Fallback:** if init/transcribe throws or OS < 17, `isAvailable=false` → coordinator uses Apple.

### Recipe S2 — Moonshine STT (Phase B, optional/stretch)
- No mature first-class Swift package. If pursued: use ONNX Runtime Swift (`onnxruntime-swift-package-manager`) with the Moonshine ONNX encoder/decoder, or a Core ML conversion. **Gate behind `isAvailable=false` until a clean on-device path is verified.** Do NOT block the project; WhisperKit `tiny` already serves the "tiny & fast" niche. It's acceptable to ship with Moonshine permanently marked "coming soon" if no good path exists.

### Recipe T1 — Kokoro TTS via Core ML (Phase C)
1. **Add SwiftPM dep** `https://github.com/jud/kokoro-coreml` (Apache-2.0, from `0.8.0`, min iOS 18) — primary; or `https://github.com/mweinbach/kokoro-swift` as alternate. Models (~99 MB) auto-download on first run; built-in Misaki G2P (no Python/espeak).
2. **`KokoroTTSEngine`** owns a `KokoroEngine`/pipeline, picks a voice (e.g. `"af_heart"`), supports speed 0.5–2.0 (map the app's rate slider into this range), streams 24 kHz mono PCM via `AsyncStream`, and plays it with `AVAudioPlayerNode`/`AVAudioEngine` (or the package's own playback if provided). Reflect `isSpeaking` from stream start→finish; `stop()` cancels the stream + stops the player node.
3. **Shape:**
```swift
import KokoroCoreML // confirm module name from package
let engine = try KokoroEngine()
for await chunk in try engine.speak("…brief text…", voice: "af_heart", speed: 1.0) {
    audioPlayer.scheduleBuffer(chunk) // or collect samples → PCM buffer
}
```
4. **Voice mapping:** the existing Settings TTS-voice picker is built around `AVSpeechSynthesisVoice` (Apple). For Kokoro, present its named voices (af_heart, etc.) when Kokoro is selected; keep Apple voices when Apple is selected. Don't crash if a stored voiceID doesn't match the active engine — fall back to the engine's default.
5. **Fallback:** OS < 18, model still downloading, or any throw → `isAvailable=false` → `VoiceServices.speak` uses `AppleTTSEngine`. The Coach "Listen" button and Morning Brief must keep working throughout.

### Recipe W1 — Morning Brief real player (Phase C2)
- Replace `MorningBriefView`'s `isPlaying.toggle()` (line ~59) with `voiceServices.toggleSpeaking(briefText)` where `briefText` is the actual composed brief (not the static `transcriptCard` string). Bind the play/pause icon to `voiceServices.isSpeaking`. On disappear, `stopSpeaking()`.

### Recipe U1 — Unify NoteEditorView dictation (Phase D1)
- Delete the private block at `NoteEditorView` ~1667–2014 (`speechRecognizer`, `recognitionTask`, `SFSpeechRecognizer.requestAuthorization`, start/stop dictation). Replace with a shared `VoiceServices` instance: call `requestSpeechAuthorization()` → `startListening()`, observe `transcribedText`, insert it into the note on stop. One code path, identical-or-better UX.

### Audio-session discipline (applies to every engine)
- STT uses `.record`; TTS uses `.playback`/`.spokenAudio`. When switching between dictation and speaking, deactivate/reactivate cleanly. Handle `AVAudioSession.interruptionNotification` (calls/other audio): on `.began` stop the mic/speech and release the session; never leave a hung tap or a stuck `isListening`/`isSpeaking`.

---

## 3. Roadmap (ordered; each item is one safe, shippable iteration)

**Phase A — Abstraction foundation (low risk, no behavior change, unblocks everything)**
- A1. Introduce `SpeechToTextEngine` + `TextToSpeechEngine` protocols and the `STTEngineID`/`TTSEngineID` enums (in `Services/Voice/`, see Recipe S0). Implement `AppleSpeechEngine` and `AppleTTSEngine` by lifting the existing `SFSpeechRecognizer`/`AVAudioEngine` and `AVSpeechSynthesizer` code out of `VoiceServices` — behavior identical. Build green; UI unchanged.
- A2. Refactor `VoiceServices` into a **coordinator** that owns the active engines and keeps its exact current public API (`startListening`/`stopListening`/`transcribedText`/`audioLevel`/`isListening`/`speak`/`stopSpeaking`/`toggleSpeaking`/`isSpeaking`). Drive engine selection from the EXISTING `VoicePreferences.sttEngine`/`ttsEngine`. With only Apple engines registered, every existing caller behaves identically. Unit-test the coordinator's fallback logic (selected-but-unavailable → Apple).
- A3. Bump the owning module's `version` explicitly via the existing `SubApp`/`SubAppRegistry`/`SemanticVersion` flow; verify `availableUpdate`/module-updates UI surface it; no-op `migrate`. Add a version-compare test.

**Phase B — On-device STT (WhisperKit primary; Moonshine optional)**
- B1. Add the **WhisperKit** SwiftPM dependency (`argmaxinc/argmax-oss-swift`, product WhisperKit/ArgmaxOSS) to the Xcode project; raise the STT engine's min-OS gate (iOS 17). No engine wired to the mic yet — just the dependency + a `prepareModelIfNeeded()` that initializes a `WhisperKit(model:"base")` pipeline off the main thread and reports readiness. Build green on simulator + device.
- B2. Implement `WhisperEngine` per **Recipe S1**: capture mic via `AVAudioEngine`, convert to 16 kHz mono Float, transcribe buffers with WhisperKit (periodic partials + final on `stop()`), emit `audioLevel`. Register it; flip `STTEngine.whisper.isAvailable` to reflect real readiness; make it selectable in the existing Settings picker (remove its "— soon"). Falls back to Apple when the model isn't ready. Smoke-test real dictation end to end (capture sheet + chat mic).
- B3. (Optional/stretch) Attempt `MoonshineEngine` per **Recipe S2**. If no clean on-device Swift path is verified this iteration, leave `STTEngine.moonshine.isAvailable=false` ("coming soon") and record the blocker in the tracker — do NOT hold up the project.

**Phase C — On-device TTS (Kokoro)**
- C1. Add the **Kokoro Core ML** SwiftPM dependency (`jud/kokoro-coreml`, Apache-2.0; alternate `mweinbach/kokoro-swift`); implement `KokoroTTSEngine` per **Recipe T1** behind `TextToSpeechEngine` (streamed 24 kHz PCM playback, speed mapping, voice selection, OS≥18 gate). Register with Apple fallback + availability/download gating; flip `TTSEngine.kokoro.isAvailable` for real and remove its "— soon". `VoiceServices.speak` uses Kokoro when present, Apple otherwise. Verify the Coach "Listen" button works on both engines.
- C2. Wire **`MorningBriefView`** to real TTS per **Recipe W1**: the player speaks the actual brief text via `VoiceServices.toggleSpeaking` (Kokoro → Apple), with working play/pause reflecting `isSpeaking`. Remove the stubbed `isPlaying.toggle()`-only behavior and the static transcript.

**Phase D — Unify all voice surfaces**
- D1. **Remove `NoteEditorView`'s private `SFSpeechRecognizer` block** and route note dictation through the shared `VoiceServices`/engine layer. Identical-or-better UX, one code path. Verify save flow unchanged.
- D2. Audit the global mic (`CommandPaletteView` → `VoiceCaptureView`) and any other caller; ensure all use the unified layer with consistent permission/waveform/partial/error UX. Remove any lingering duplication.

**Phase E — Settings, hardening, polish**
- E1. Add the **Voice** section to `SettingsView`: STT engine picker + TTS picker/toggle, each with availability + Download action, persisted via `@AppStorage`. Switching is instant and safe.
- E2. Production hardening: permission-denied path, model-missing/downloading path, offline (airplane mode) works on-device, mid-speech cancel, audio-session interruptions (incoming call / other audio) release the mic cleanly, empty/short input, rapid start/stop. No crashes, no stuck mic, no leaked `AVAudioSession`.
- E3. Accessibility (Dynamic Type, VoiceOver labels on mic/play controls, 44pt targets) + tests (engine fallback, availability gating, settings persistence, Morning Brief speaks) + a final full-surface smoke pass (capture, note dictation, command-palette mic, morning brief) all working without bugs.

## 4. THE LOOP PROMPT (paste this each session)

```
You are continuing a long-running project to give PulseLoop best-in-class,
fully ON-DEVICE, OPEN-SOURCE voice. DECIDED STACK: Speech-to-Text via WhisperKit
(argmaxinc/argmax-oss-swift, MIT, SwiftPM, Core ML; model "base"/"small",
auto-downloaded) — Moonshine is an optional stretch engine, not a blocker — and
Text-to-Speech via Kokoro Core ML (jud/kokoro-coreml or mweinbach/kokoro-swift,
Apache-2.0, SwiftPM), with Apple SFSpeechRecognizer / AVSpeechSynthesizer as the
guaranteed fallback. Everything integrates flawlessly and intuitively into EVERY
voice surface of the app with zero servers, zero API keys, zero per-use cost, and
full privacy (audio never leaves the phone). Your single source of truth is
docs/VOICE_LOOP_PROMPT.md (mission §0, code anchors §1, architecture §2,
IMPLEMENTATION PLAYBOOK §2.8 with concrete per-engine recipes, roadmap §3,
guardrails §5) and the live tracker docs/VOICE_PROGRESS.md.

Do EXACTLY ONE iteration, then stop. Follow this loop:

1. ORIENT. Read docs/VOICE_LOOP_PROMPT.md and docs/VOICE_PROGRESS.md. If
   VOICE_PROGRESS.md does not exist, create it from the §3 roadmap with every item
   set to "pending", then treat iteration A1 as current.

2. SELECT. Pick the single highest-priority "pending" iteration (top-to-bottom in
   §3). Restate it in one sentence. If it is too big for one safe, shippable step,
   split it: do the first sub-step now and add the remainder as new pending items.

3. PLAN. Write a short todo list for this iteration only. Verify the exact real
   files/types from §1 by reading them — never invent file paths, types, or APIs.
   Confirm the real VoiceServices public surface (startListening/stopListening/
   transcribedText/audioLevel/isListening/speak/stopSpeaking/toggleSpeaking/
   isSpeaking), the EXISTING VoicePreferences enums (STTEngine/TTSEngine +
   isAvailable) and SettingsView "VOICE (STT & TTS)" section, the NoteEditorView
   dictation block (~1667–2014), VoiceCaptureView usage, MorningBriefView player
   (~line 59), CommandPaletteView mic, and the SubApp / SubAppRegistry /
   SemanticVersion API before using them. For any engine work, follow the matching
   recipe in §2.8 and READ the just-added package's README/headers to confirm real
   symbol names before calling them.

4. IMPLEMENT. Make the change, reusing existing patterns:
   - ON-DEVICE + OPEN-SOURCE ONLY for the new engines. No cloud STT/TTS, no paid
     API for voice, no API key. Inference is 100% local and works offline. Use the
     DECIDED packages (WhisperKit MIT for STT, Kokoro Core ML Apache-2.0 for TTS),
     added via SwiftPM; let them auto-download their Core ML models (do NOT
     hand-convert or bundle large weights). NEVER a non-commercial (XTTS Coqui CPML)
     or server/GPU-class model (Dia2, Fish S2 Pro, Canary-Qwen, VibeVoice).
   - ABSTRACTION: all STT behind one SpeechToTextEngine protocol; all TTS behind one
     TextToSpeechEngine protocol (Recipe S0). VoiceServices is the COORDINATOR
     holding the active engine, driven by VoicePreferences, keeping its EXACT current
     public API so all callers keep working. Engines: AppleSpeechEngine/AppleTTSEngine
     (always available fallback), WhisperEngine, KokoroTTSEngine, optional
     MoonshineEngine.
   - FALLBACK IS SACRED: if a selected engine's model is missing/downloading/
     unsupported (OS too old, package init throws), set isAvailable=false and
     transparently fall back to the Apple engine. Voice is NEVER fully broken.
   - REUSE existing groundwork: VoicePreferences enums/prefs, the Settings VOICE
     section, the AVSpeechSynthesizerDelegate, and the Coach "Listen" button already
     exist — make the "— soon" engines real and flip isAvailable; don't rebuild them.
   - UNIFY: remove NoteEditorView's private SFSpeechRecognizer block (Recipe U1) and
     route note dictation through the shared layer. Do not fork voice managers.
   - MODELS: never block launch; download lazily off the main thread with progress;
     report isAvailable accurately; Settings shows availability + a Download action.
   - MORNING BRIEF: wire the real player (Recipe W1) to VoiceServices.toggleSpeaking
     of the actual brief text (Kokoro -> Apple), play/pause reflecting isSpeaking.
   - AUDIO SESSION: .record for STT, .playback/.spokenAudio for TTS; handle
     interruptions (calls/other audio); never leak a session or hang the mic.
   - VERSIONING: bump the owning module's version explicitly; ship via the existing
     SubApp/SubAppRegistry/SemanticVersion flow; migrations additive/no-op.
   - PRIVACY: never log raw audio or transcripts; reuse existing mic/speech
     Info.plist usage strings; on-device inference needs no new entitlement.
   - Design system is law: PulseColors/PulseFont/PulseRadius/PulseLayout, components
     from AppTheme.swift + Components.swift, .cursor/rules/design-system.mdc. SF
     Symbols only, no emoji in UI, primary buttons black, accent sparingly.

5. VERIFY. Build and resolve errors before finishing:
   xcodebuild -project PulseLoop.xcodeproj -scheme PulseLoop \
     -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
   Run ReadLints on edited files. Add/adjust tests where §3 calls for them. The app
   MUST build at the end of the iteration. (Note: Core ML engines may only run real
   inference on device/newer simulators — guard so the build + Apple fallback always
   work even where a model can't load.)

6. RECORD. Update docs/VOICE_PROGRESS.md: mark this iteration done with a 1–3 line
   summary (what changed + which files + any new services/engines/preferences/
   packages), list any follow-ups you spun off, and clearly name the NEXT pending
   iteration.

7. STOP. Post a concise summary: what you did, build status, the next iteration. Do
   not start the next iteration. Do not create a git commit unless I ask.

Rules of engagement:
- Keep the build green; never leave a broken state.
- Prefer small, reversible steps; add engines/services/packages additively so old
  paths keep working and existing capture/dictation/brief flows never break.
- On-device + open-source + offline for inference; Apple APIs are the permanent
  guaranteed fallback. Voice is never fully broken.
- One voice layer: extend VoiceServices behind protocols; remove duplicate STT in
  NoteEditorView; do not fork parallel voice managers.
- Privacy: audio/transcripts never leave the device and are never logged.
- The module version MUST be bumped as part of this project (Phase A3) and recorded.
- Follow §2.8 recipes; after adding a package, read its real API before calling it.
- If a decision has real product trade-offs (which model size, default engine,
  jud vs mweinbach Kokoro package, whether to pursue Moonshine), state your default,
  proceed, and note it in the tracker rather than blocking.
- If you find the roadmap is wrong, propose the fix in the tracker and adjust, but
  still complete one concrete shippable step this iteration.
```

---

## 5. Guardrails (referenced by the loop — the hard rules)

- **Build green every iteration.** End state compiles and runs; Xcode build + ReadLints are the gate.
- **On-device, open-source, offline, free.** New STT/TTS engines run 100% locally with no API key and work in airplane mode once the model is cached. **Decided commercially-usable stack: WhisperKit (MIT) for STT, Kokoro Core ML (Apache-2.0) for TTS, both via SwiftPM.** **Never** a non-commercial license (XTTS-v2 Coqui CPML) or a server/GPU-class model (Dia2, Fish S2 Pro, Canary-Qwen, Granite, VibeVoice).
- **Apple is the permanent fallback.** `SFSpeechRecognizer` / `AVSpeechSynthesizer` always work with no download. If a chosen engine's model is missing/downloading/unsupported, fall back transparently. Voice is never fully broken.
- **One voice layer.** All STT behind `SpeechToTextEngine`, all TTS behind `TextToSpeechEngine`; `VoiceServices` is the single coordinator keeping its current public API. **Remove the duplicate `SFSpeechRecognizer` in `NoteEditorView`.** No parallel voice managers.
- **Privacy is absolute.** Audio and transcripts never leave the device and are never logged. Reuse existing mic/speech Info.plist strings; no new network entitlement for inference.
- **Small footprint, never block launch.** The `.app` ships no large model; WhisperKit and Kokoro Core ML auto-download their Core ML weights on first use (lazily, off the main thread, with progress). Report `isAvailable` accurately; Settings exposes availability + Download. Never hand-convert or vendor weights into the bundle.
- **Additive only.** New services, one `@AppStorage` preference, optional model assets. No SwiftData migrations; existing notes/tasks/logs untouched; existing capture/dictation/brief flows keep working.
- **One versioning system.** Bump the owning module's version and ship via the existing `SubApp`/`SubAppRegistry`/`SemanticVersion` flow (mirror `ProtocolSubApp`'s explicit `var version`). Migrations forward-only and data-preserving.
- **Intuitive, consistent UX.** One permission path, one waveform/level treatment, one partial-result style, one error/empty treatment across every voice surface. Switching engines is instant and obvious in Settings.
- **Design system is law.** `PulseColors`/`PulseFont`/`PulseRadius`/`PulseLayout` + components from `App/AppTheme.swift` + `DesignSystem/Components.swift`; obey `.cursor/rules/design-system.mdc`. SF Symbols only (no emoji in rendered UI). Primary buttons black, accent sparingly, hairline-bordered cards, calm whitespace.
- **Resilience.** Handle permission-denied, model-missing/downloading, offline, mid-speech cancel, audio-session interruptions (calls/other audio), empty/short input, rapid start/stop. Never crash, never hang the mic, never leak an `AVAudioSession`.
- **Accessibility & quality.** Dynamic Type, VoiceOver labels on mic/play controls, 44pt tap targets on every voice surface; add tests for engine fallback, availability gating, settings persistence, and Morning Brief read-aloud.
- **One iteration at a time.** A single shippable step, then stop — keeping the project reviewable.
