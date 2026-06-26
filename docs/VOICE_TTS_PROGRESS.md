# Voice / TTS Repair Progress

Tracker for `VOICE_TTS_LOOP_PROMPT.md`. Updated as the loop runs.

## Goal
1. Fix Kokoro static (synthesized samples are white noise, not playback bug).
2. Add multiple offline on-device TTS engines for the user to A/B test.

## Status legend: ✅ done · 🔄 in progress · ⏳ pending · ❌ blocked

## Steps
- ✅ STEP 1 — Verify current Kokoro `.all` (forceCPU=false): **still static** on sim
- ✅ STEP 2 — Root-cause: Kokoro Core ML emits white noise on simulator for BOTH
  `.cpuOnly` and `.all`. Objective test: `zcr=0.523`, `silent_frac=0.0`. The
  simulator has no real ANE and its Core ML GPU/CPU shim produces garbage for
  Kokoro's compiled graph. Not fixable via compute-unit flags alone.
- ✅ STEP 3+4 — Integrated **sherpa-onnx** (ONNX Runtime, not Core ML → works in
  simulator) via *vendored* xcframeworks (SPM hit a `module.modulemap` collision
  between sherpa-onnx + onnxruntime; stripped onnxruntime's headers/modulemap so
  only sherpa contributes a module). Sherpa is now the default TTS engine; Kokoro
  Core ML stays selectable for real devices.
- ✅ STEP 5 — Bundled **Piper (Amy, int8)** + **KittenTTS (nano, fp16)**. Shared a
  single `espeak-ng-data` at the Models root (identical across models) to avoid
  resource collisions. Models copied into the bundle via an rsync Run Script
  phase (Xcode 26 synchronized groups + folder refs both flatten nested dirs →
  `tokens.txt` collisions; rsync preserves the tree).
- ✅ STEP 6 — Settings: TTS engine picker + Sherpa **model** A/B picker + multi-
  speaker picker (Kitten has 8 voices), with per-engine **Preview voice**.
- ✅ STEP 7 — Build green. Objective tests **pass**: both Piper & Kitten produce
  clean speech on the simulator (`zcr < 0.30`, has silent gaps, valid 24kHz WAV
  dumped to `/tmp/sherpa_*.wav`). App installed + launched on simulator.

## Resolution
- **Static fixed by switching the default engine to sherpa-onnx (ONNX Runtime).**
  Unlike Kokoro's Core ML graph, ONNX Runtime runs correctly in the simulator.
- Engineering notes:
  - Vendored `Frameworks/sherpa-onnx.xcframework` + `onnxruntime.xcframework`
    (macOS slices trimmed). Removed onnxruntime's `Headers/module.modulemap` and
    its `HeadersPath` Info.plist keys to kill the modulemap collision.
  - `Models/` moved to repo root (out of the synchronized `PulseLoop` group) and
    copied via a `Copy TTS Models` rsync build phase; `ENABLE_USER_SCRIPT_SANDBOXING = NO`.
  - `SherpaOnnxAPI.swift` (Swift wrapper) copied locally; `SherpaTTSEngine.swift`
    hosts the model catalog and uses shared `PCMAudioPlayer`.

## Findings
- Static is in the samples: `zcr=0.471`, `silent_frac=0.00` (white-noise signature).
- WAV encoder + host synthesis are clean (afplay verified) — playback path is fine.
- `KokoroEngine`: frontend `.cpuOnly` (fixed); backend `.all` when `forceCPU=false`.
- Simulator has no ANE; an ANE-targeted compute plan can emit garbage there.
- mattmireles/kokoro-coreml: iPhone A-series rejects full-ANE plan (`ANECCompile FAILED`),
  needs staged policy (decoder-pre on ANE, rest CPU+GPU).
- Candidate multi-engine dep: `willwade/sherpa-onnx-spm` (offline, iOS16+,
  Piper/VITS/Matcha/Kokoro/KittenTTS, 1300+ models).

## Objective check (per iteration)
Pass = `zcr` ~0.05–0.20, `silent_frac` > 0.05, peak not clipped. White noise = zcr~0.5.

## Decisions
- **Default TTS engine: sherpa-onnx** (Piper Amy), chosen because ONNX Runtime
  works on both simulator and device. Kokoro Core ML kept as a device-only option.
- **Kokoro → sherpa auto-redirect on the simulator**: selecting Kokoro on the
  simulator transparently routes to sherpa-onnx at runtime (`resolvedTTS()`), so
  the user never hears static. On a real device Kokoro is used as selected.
- Bundled neural voices (all Apache-2.0/MIT, offline, no download, iPhone-ready):
  - Amy (US, female) · Ryan (US, male) · Cori (UK, female) · Alan (UK, male)
  - LibriTTS (US multi-voice, 8 curated speakers) · Kitten Nano (US, 8 voices)
