# Kokoro Voice Distinctness — AI Voice-Engineer Loop

You are an AI engineer specializing in voice/LLM TTS. Goal: **every Kokoro voice
must sound distinct** (and, by extension, every voice the user can pick must
actually be applied end-to-end). Run the loop until the objective checks pass.

## Symptom
"All of the voices on Kokoro sound the same."

## Hypotheses (rank + prove with data, don't guess)
1. **Simulator redirect masks Kokoro**: on the simulator, selecting Kokoro is
   redirected to sherpa-onnx. The Kokoro voice id (e.g. `af_heart`) is not a
   valid sherpa speaker int, so sherpa ignores it and always speaks the same
   model/speaker → every "Kokoro voice" sounds identical. (Most likely.)
2. **Kokoro engine ignores the `voice:` argument** (same class of bug as the
   sherpa `selectModel` clobber) — the model loads one voice embedding and reuses
   it regardless of the requested voice.
3. **Voice embeddings not bundled / not loaded**: `engine.availableVoices` is a
   single voice, so `resolveVoice` always falls back to the default.

## Constraints
- On-device, offline, no downloads, iPhone-compatible.
- Don't break the Apple fallback or STT.
- Don't reintroduce the sherpa "male sounds female" regression.
- Keep the redirect's intent (no static on simulator) but make voice choice work.

## Objective check (the loop's pass condition)
Synthesize the SAME sentence with several distinct voices and compute an audio
"fingerprint" per voice (zero-crossing rate as a pitch proxy + RMS envelope).
- Voices that are supposed to differ (e.g. female `af_*` vs male `am_*`/`bm_*`)
  MUST have measurably different fingerprints.
- At minimum: the set of fingerprints for N>=4 voices must have N distinct
  values (no two identical), and male vs female ZCR must differ clearly.

## Loop steps
1. Diagnose: dump per-voice ZCR/RMS for Kokoro (direct, no redirect) AND for the
   path the user actually hears (with redirect). Identify which hypothesis holds.
2. Fix the real cause:
   - If redirect masks Kokoro: translate the Kokoro voice → an equivalent sherpa
     model/speaker so gender/identity is preserved on the simulator; on device use
     real Kokoro voices.
   - If Kokoro ignores `voice:`: thread the voice through synthesize correctly.
3. Add a regression test asserting N voices have N distinct fingerprints + a
   male/female pitch separation.
4. Build green, run tests, reinstall on simulator, verify.
5. Repeat until the objective check passes for both the simulator (redirected)
   and the direct-Kokoro path.

## Progress
See `KOKORO_VOICE_PROGRESS.md`.
