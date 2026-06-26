# Kokoro Voice Distinctness — Progress

## Status: DONE

## Goal
Every selectable Kokoro voice produces audibly distinct speech; male voices
sound male, female sound female — on both the simulator (redirected) and device.

## Findings
- ROOT CAUSE (confirmed): On the simulator Kokoro is redirected to sherpa-onnx.
  The Kokoro voice id (`af_heart`, `am_michael`, …) is a *string*, but sherpa
  parsed voiceID as an `Int` speaker index (`SherpaTTSEngine.speak`:
  `Int(voiceID ?? "") ?? VoicePreferences.sherpaSpeaker`). `"af_heart"` → nil →
  always fell back to the one loaded sherpa model+speaker. So every Kokoro voice
  played the SAME sherpa voice on the simulator → "all sound the same".
- The real Kokoro engine threads the voice correctly (`resolveVoice →
  engine.synthesize(voice:)`), and `KokoroCoreML.VoiceStore` loads a distinct
  embedding per `.bin` voice — so on a real device voices already differ.
  54 Kokoro voices are bundled (af/am/bf/bm/… prefixes).

## Fix
- `SherpaModel.target(forKokoroVoice:)` translates a Kokoro voice id → a matching
  bundled sherpa model + speaker, preserving gender + accent:
  - UK (`b*`) → Alan (male) / Cori (female) Piper voices (British accent kept).
  - US + other → an ordered list of distinct "voice slots" (Joe/Amy + LibriTTS +
    Kitten speakers), indexed by the voice's stable rank among its same-gender
    peers so two Kokoro voices never collapse to one sound.
- `SherpaTTSEngine.speak` detects a Kokoro-style id (`isKokoroVoiceID`) and loads
  the translated model ephemerally (`loadModelIfNeeded`, without clobbering the
  user's sherpa A/B preference) and uses the translated speaker.

## Objective check (PASS)
- `testKokoroVoicesTranslateToDistinctSherpaTargets`: 4 same-gender voices → 4
  distinct (model#speaker) signatures; UK male → Alan, UK female → Cori.
- `testKokoroRedirectVoicesProduceDistinctAudio`: 5 Kokoro voices → >=4 distinct
  audio fingerprints through the actual synth path.
- `testKokoroRedirectMaleSoundsLowerThanFemale`: Kokoro male (->Joe) ZCR < female
  (->Amy) ZCR — gender preserved.
- Full suite: 21 passed, 1 skipped (Kokoro-direct-on-sim is static by design — the
  reason we redirect; validated on device instead), 0 failures.

## Decisions
- On the simulator, translate the selected Kokoro voice id → a sherpa model+
  speaker that matches gender/accent. On device, native Kokoro voices are used
  unchanged. The user's sherpa A/B model preference is never clobbered by the
  ephemeral redirect load.
