# RNNoise — ported to Rust

- Source: https://github.com/xiph/rnnoise (convenience copy of
  https://gitlab.xiph.org/xiph/rnnoise)
- Version: **v0.1.1** (tag), commit
  `6cbfd53eb348a8d394e0757b4025c6ded34eb2b6`
- What: the library's frame analysis, its network and its BUILT-IN model
  (`rnn_data.c` ≈ 428 KB), ported line for line into `src/` — the same
  operations in the same order, so the same samples. Not ported, for the
  app never reaches them: a model read from a file (`rnn_reader.c`), the
  voice probability, and the training scripts.
- License: **BSD-3-Clause** (`COPYING` beside this file — Mozilla,
  Jean-Marc Valin, Xiph.Org Foundation, Mark Borgerding). Binary
  distributions must reproduce that notice: the app shows it on its
  About ▸ licenses screen (`assets/licenses/LICENSE-RNNoise.txt`, a copy
  of `COPYING`, registered in `lib/main.dart`), and `THIRD_PARTY.md`
  lists it.
- History: vendored as C under `packages/qa_native/src/third_party/rnnoise/`
  and compiled into the engine through `qa_audio_denoise.c` until the
  connection round (connection-round-checklist H, 2026-11-08), which
  deleted both once this port answered every take as the C did, bit for
  bit, on Windows, macOS, Linux and Windows ARM64. The C carried three
  recorded deviations from upstream — `pitch.c`'s and `celt_lpc.c`'s VLAs
  as fixed-bound arrays (upstream `b61fb03`, backported because MSVC
  compiles no VLA), and a copy of `include/rnnoise.h` beside the sources;
  the port sizes those arrays as Rust does (`src/pitch.rs`).

Why v0.1.1 and not v0.2: v0.2 externalized the model weights into a
downloaded blob whose C form is 15–29 MB and would grow EVERY platform
binary by roughly that much. v0.1.1 is the classic built-in model — the
one OBS ships for its noise suppression — trained for voice, 428 KB,
and the quality reference most users mean by "RNNoise".

Why it is here at all: the recording program's noise-suppression round
(대사=on/발소리=off — the model is speech-specific and eats footsteps,
which is exactly why the toggle exists). Capture runs at 48 kHz when
suppression is on — RNNoise is a 48 kHz-native design — and the take
then conforms ONCE through the existing pipeline on placement.
