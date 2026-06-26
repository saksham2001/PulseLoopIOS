# VOICE / TTS REPAIR + MULTI-ENGINE LOOP PROMPT

**Role:** You are a senior AI/audio-systems architect working on PulseLoop (SwiftUI,
iOS 26.x, on-device AI). You own the on-device Text-to-Speech (TTS) stack end to end.

**Two goals (do both):**

1. **Fix the Kokoro static.** The user hears white-noise / static instead of speech
   from Kokoro Core ML. Diagnostics already proved the *synthesized samples
   themselves* are noise (ZCR ≈ 0.47, `silent_frac` = 0.00 — the white-noise
   signature), not a playback bug. Make Kokoro produce clean, intelligible speech
   — or, if it cannot be made reliable on this platform, demote it and make a
   different on-device engine the default. Clean audio is the bar, not "Kokoro
   specifically."
2. **Install multiple open-source on-device TTS engines for the user to A/B test.**
   They must run fully offline on iPhone/iOS Simulator (no server, no API key).
   The user picks the winner by ear in Settings → Voice.

Run autonomously in a loop until BOTH goals are met and verified. Do not stop to
ask the user except for the single subjective "which voice sounds best / does it
sound clean now" listening check (the assistant cannot hear simulator audio).

---

## Hard constraints

- **On-device & offline only.** No network at synthesis time. Models are bundled
  in the app (folder reference in `project.pbxproj`, like the existing
  `PulseLoop/Resources/Models/kokoro` and `…/whisper-base`). Cloud/server engines
  from the BentoML article (Fish Audio S2, VibeVoice, XTTS server, etc.) are OUT.
- **iPhone-compatible.** Must build & run for `iOS Simulator` (arm64) and a real
  device. iOS 16+ deployment floor for any new dependency.
- **Apache-2.0 / MIT only.** Reject non-commercial licenses (XTTS-v2 Coqui CPML,
  Fish open-weights paid license). Kokoro (Apache-2.0), Piper (MIT), VITS/MMS
  (MIT/CC), KittenTTS (Apache-2.0) are fine.
- **Don't break Apple fallback.** `AppleTTSEngine` (`AVSpeechSynthesizer`) stays the
  guaranteed always-available fallback. The coordinator (`VoiceServices`) must keep
  falling back to Apple when a selected engine isn't ready.
- **Don't regress STT.** Whisper STT and the `VoiceServices` STT path stay working.
- **Keep the existing protocol surface.** New engines conform to
  `TextToSpeechEngine` (`PulseLoop/Services/Voice/VoiceEngine.swift`). Add new cases
  to `TTSEngineID` + `TTSEngine` (`VoicePreferences.swift`) — raw values are
  persisted, never rename existing ones.

---

## Current architecture (already in place — reuse it)

- `PulseLoop/Services/Voice/VoiceEngine.swift` — `SpeechToTextEngine` /
  `TextToSpeechEngine` protocols, `STTEngineID` / `TTSEngineID` enums.
- `PulseLoop/Services/Voice/KokoroTTSEngine.swift` — Kokoro via `KokoroCoreML`
  (`jud/kokoro-coreml` SPM). Singleton `.shared`. Bundled model at
  `Resources/Models/kokoro`. Synthesizes `[Float]` @ 24 kHz, then plays via
  `AVAudioEngine`/`AVAudioPlayerNode` with an `AVAudioConverter` to the hardware rate.
  **This is the file emitting static.**
- `PulseLoop/Services/Voice/AppleTTSEngine.swift` — `AVSpeechSynthesizer` fallback.
- `PulseLoop/Services/VoiceServices.swift` — `@Observable` coordinator; owns active
  engines, eager-prepares selected engines in `init`, falls back to Apple.
- `PulseLoop/Services/VoicePreferences.swift` — `UserDefaults`-backed prefs:
  `ttsEngine`, `ttsVoiceID`, `ttsRate`, `ttsPitch`, `autoSpeakReplies`.
- `PulseLoop/Views/SettingsView.swift` — Voice section: engine pickers, voice
  picker, **Preview voice** button. Engine-aware voice list.
- `PulseLoop.xcodeproj/project.pbxproj` — model bundling via folder reference +
  `PBXFileSystemSynchronizedBuildFileExceptionSet` membership exception.
- Tests: `PulseLoopTests/VoiceEngineCoordinatorTests.swift` (includes a host WAV
  dump + non-silent assertion).

**Build/run facts:** Xcode 26.5 at `/Users/reytran/Downloads/Xcode.app`. Sim device
id `9B6A3F66-11A9-46B4-800C-0E317A845960` (iOS 26.5). Bundle id
`xyz.sakshambhutani.PulseLoop`. `SWIFT_APPROACHABLE_CONCURRENCY = NO` and
`SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated` are required (don't revert).

---

## Diagnostics already done (don't repeat from scratch)

- Static is in the **samples**, not playback: dumped the runtime clip to the app's
  Documents dir, pulled it with `simctl get_app_container`, and analyzed with a
  Python WAV stats script → `zcr=0.471`, `silent_frac=0.00`, continuous energy =
  white noise.
- The same WAV writer + a host-run synthesis produced *clean* audio via `afplay`,
  so the WAV encoder and host Core ML path are fine.
- `KokoroEngine` uses `feConfig.computeUnits = .cpuOnly` (frontend, fixed) and
  `beConfig.computeUnits = forceCPU ? .cpuOnly : .all` (backend). We just flipped
  `requiresCPUOnly` → `false` (backend `.all`) but **have not yet verified** whether
  `.all` on the simulator yields clean audio. **Step 1 of the loop is to verify this.**

### Objective audio check (use this every iteration instead of guessing)

Dump synthesized samples to the app Documents dir as WAV, then on the host:

```bash
DEV=9B6A3F66-11A9-46B4-800C-0E317A845960
C=$(xcrun simctl get_app_container $DEV xyz.sakshambhutani.PulseLoop data)
cp "$C/Documents/<dump>.wav" /tmp/x.wav
python3 - <<'PY'
import wave,struct,math
w=wave.open('/tmp/x.wav','rb'); n=w.getnframes(); fr=w.getframerate()
s=struct.unpack('<'+str(n)+'h', w.readframes(n))
peak=max(abs(x) for x in s); rms=math.sqrt(sum(x*x for x in s)/n)
zc=sum(1 for i in range(1,n) if (s[i-1]<0)!=(s[i]<0)); zcr=zc/n
win=240; sil=tot=0
for i in range(0,n-win,win):
    seg=s[i:i+win]; r=math.sqrt(sum(x*x for x in seg)/win); tot+=1
    if r<peak*0.02: sil+=1
print(f'dur={n/fr:.2f}s peak={peak} rms={rms:.0f} zcr={zcr:.3f} silent_frac={sil/tot:.2f}')
PY
```

**Pass criteria for "clean speech":** `zcr` roughly **0.05–0.20** AND `silent_frac`
**> 0.05** (real pauses) AND `peak` not clipped to a constant. White noise = `zcr`
near 0.5 and `silent_frac` ≈ 0. Only ask the user to *listen* after the objective
check passes.

---

## Loop steps (repeat until done)

**STEP 1 — Verify the current Kokoro `.all` fix.**
Build → install → launch → trigger a synth (Preview voice or a debug call) → dump →
run the objective check. If clean, Kokoro is fixed; record it and move to STEP 4.
If still noise, go to STEP 2.

**STEP 2 — Root-cause Kokoro on the simulator.** Investigate in order, testing the
objective check after each change:
  a. Compute units: try `.cpuAndGPU`, `.all`, `.cpuOnly` for the backend (and
     frontend) on the simulator vs device. The mattmireles/kokoro-coreml notes that
     **iPhone A-series rejects the full-ANE plan** (`ANECCompile() FAILED`) and needs
     a *staged* policy (decoder-pre on ANE, rest on CPU+GPU). The simulator has no
     ANE at all (it shims to CPU/GPU), so an ANE-targeted plan can silently emit
     garbage. The fix is likely a compute-unit policy that avoids ANE on simulator
     **without** falling back to the broken `.cpuOnly` path.
  b. G2P / tokenization: confirm phonemes aren't empty/garbage (an empty or wrong
     phoneme stream can make the vocoder emit noise). Log the phoneme string.
  c. Voice embedding: confirm the selected voice `.bin` loads and isn't all-zeros.
  d. Model packaging: confirm the bundled `.mlmodelc`/`.mlpackage` matches what the
     SPM build expects (compiled vs package, opset).
  If Kokoro can't be made clean on the simulator but the objective check passes on a
  real device, that's acceptable — document it and ensure the simulator falls back
  cleanly. But prefer a real fix.

**STEP 3 — If Kokoro stays broken, make a working engine the default** (see STEP 4)
and demote Kokoro to "experimental".

**STEP 4 — Add a multi-model on-device engine via sherpa-onnx.**
Integrate `willwade/sherpa-onnx-spm` (binary XCFramework, iOS 16+, offline). It
exposes a Swift API for **Piper / VITS / Matcha / Kokoro / KittenTTS** — 1300+
models, all offline. This gives the user several engines to A/B test from one
dependency.
  - Add the SPM dependency to `project.pbxproj` (or via `xcodebuild`/Package.swift).
  - Create `SherpaTTSEngine.swift` conforming to `TextToSpeechEngine`, returning
    `[Float]` samples and reusing the existing `AVAudioEngine` playback path
    (factor the playback out of `KokoroTTSEngine` into a shared `PCMAudioPlayer`
    helper so all engines share one clean, tested player).
  - Add a `selectedModel` concept (engine id + model folder) so one engine can host
    several bundled voices/models.

**STEP 5 — Bundle 2–3 small offline models for testing** under
`PulseLoop/Resources/Models/` as folder references:
  - **Piper** (e.g. `en_US-amy-medium` or `en_US-lessac-medium`) — fast, robust,
    MIT, the safest known-good baseline.
  - **KittenTTS** (~25 MB, Apache-2.0) — very small, good sanity check.
  - Optionally a **VITS/MMS English** model.
  Keep total bundle growth reasonable (prefer the smallest good models). Wire each
  as a selectable model in the engine + model picker.

**STEP 6 — Settings UX.** In `SettingsView` Voice section:
  - Engine picker now lists: Apple, Kokoro (Core ML), Sherpa (on-device).
  - When Sherpa is selected, show a **model picker** (Piper Amy, KittenTTS, VITS…).
  - **Preview voice** synthesizes a fixed sample sentence with the *currently
    selected* engine+model+voice, so the user can A/B each one by ear.
  - Persist engine + model + voice in `VoicePreferences` (new keys; never rename
    existing raw values). Update `onChange`/`onAppear` so switching engines resets
    voice/model to a valid default for that engine.

**STEP 7 — Verify.**
  - `xcodebuild build` succeeds (grep for `BUILD SUCCEEDED`, no `error:`).
  - Run `VoiceEngineCoordinatorTests` (add cases: each engine synthesizes
    non-silent audio passing the objective ZCR/silence check; bundled models
    present; engine/model enumeration correct).
  - Install + launch on the sim; no crash.
  - Dump + objective-check each engine's output.
  - Ask the user the single listening question: which engine sounds best / is it
    clean now. Set that as the default if they pick one.

---

## Definition of done

- [ ] At least **two** on-device TTS engines (besides Apple) build, run offline on
      the simulator, and produce audio that passes the objective ZCR/silence check.
- [ ] The static is gone for the default engine (clean speech, user-confirmed by ear).
- [ ] Settings → Voice lets the user pick engine + model + voice and Preview each.
- [ ] Apple fallback still works; STT (Whisper) still works; build is green; tests pass.
- [ ] DEBUG-only sample dumps removed (or gated behind a debug flag) before "done".
- [ ] `docs/VOICE_TTS_PROGRESS.md` updated with what was tried, what worked, and the
      final default.

## Logging / cleanup rules

- Use `OSLog` (`subsystem: "PulseLoop"`) with `.public` for diagnostics during the
  loop; remove the temporary `kokoro_runtime_dump.wav` write before declaring done.
- No narrating code comments. Comments explain non-obvious intent only.
- Run `ReadLints` after substantive edits; fix introduced lints.
