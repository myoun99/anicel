import 'dart:ffi';
import 'dart:io';

/// The `qa_engine` binary's ABI contract: **one version number, one
/// loader, one place to change either.**
///
/// The C exports a single `qa_engine_abi_version()` for the whole library,
/// so Dart holding two expectations of it was never two facts — across the
/// nine bumps from v16 to v24 the two copies never once differed. What the
/// duplication actually bought was a way to forget one, which is what
/// happened when a bump missed the audio copy and took thirteen parity
/// suites down with it (R26).
///
/// Loaders still live apart, and should: the mixer runs on the device's
/// realtime thread, the raster engine on the UI isolate's workers, and
/// they stand down independently. That is a reason for separate
/// *instances*, not for separate copies of "which file, and which
/// version".
///
/// ## Bumping the ABI
///
/// 1. `qa_engine_abi_version()` in `packages/qa_native/src/qa_engine.c`,
///    with a `// vNN:` line saying what moved.
/// 2. [kQaEngineAbiVersion] below, plus a changelog entry here.
/// 3. Rebuild the standalone test binary:
///    `cmake -S packages/qa_native/src -B build/native_standalone &&
///    cmake --build build/native_standalone --config Release`
///
/// There is no third Dart constant to remember — `qa_engine_abi_test.dart`
/// fails if step 1 and step 2 disagree, and it needs no binary to say so.
///
/// Raising the number breaks nothing by itself: it is a gate, and layout
/// changes are caught separately by the `qa_*_sizeof` cross-checks. App
/// builds recompile the C every time, so only the standalone test binary
/// can go stale — and then the parity suites fail loudly under
/// `QA_REQUIRE_NATIVE=1` rather than skipping.
///
/// `qa_tablet` is a DIFFERENT binary with its own `qat_abi_version`; none
/// of this covers it.
///
/// ## Changelog
///
/// - v12: fill raster RGB -> RGBX (R22-D flood SIMD).
/// - v13: `qa_flood_fill_wave` — wave-parallel flood (R22-E3).
/// - v14: `qa_fill_compose_batch` — pooled fill compose (R25-③).
/// - v15: `qa_grid_raster_tile` — timeline grid tile rasterizer (UI-R18).
/// - v16: `qa_audio_mix` + output stage — the audio mixer core (2B).
/// - v17: `qa_audio_resample` — the polyphase resampler (2B).
/// - v18: AUDIO-PRO R1 — pan factors, fade curves and volume envelopes in
///   the clip struct, plus the shared envelope key array.
/// - v19: AUDIO-PRO R5 — `qa_audio_capture_*` (the guide-voice recorder).
/// - v20: AUDIO-PRO R7 — `qa_video_export_*` (the OS video encoder).
/// - v21: EX4 — `qa_video_export_open` gains container/codec/alpha/
///   bitrate, `qa_video_export_probe`, and `qa_image_encode_jpg` (stb).
/// - v22: BB-N1 — the stroke-blend tile kernel and the alpha-bounds scan.
/// - v23: `qa_audio_denoise_f32` — RNNoise voice-take suppression.
/// - v24: the fused pre-blend — `qa_tile_span` gained base/stroke/mask/
///   premul fields and `qa_pre_blend_tiles` stages, blends and
///   premultiplies a whole frame's overlay tiles in one pooled call. The
///   mask field carries the selection, so "draw inside the selection
///   only" happens in the kernel instead of a painter clip.
/// - v25: `qa_resample_rgba` — the shared image resampler. One inverse
///   map, splitting at the accumulator: a tent mean, or the area argmax
///   that carries source words through untouched. The transform tool
///   resamples through it; FX transforms, import fit and screen
///   minification are still to move over.
///
///   The argmax has since been rewritten twice inside this version, from
///   a tent to a coverage box to a supersampled count of where the
///   subsamples land, and the number did not move: the exported signature
///   never changed, app builds recompile the C, and a stale standalone
///   test binary fails the parity suite loudly rather than quietly
///   resampling differently.
const int kQaEngineAbiVersion = 25;

/// Test hook: point EVERY engine loader at a locally built binary.
///
/// One switch, because "where the engine is" is one fact about the
/// process, not six. It used to be a static on each loader, and the cost
/// showed up immediately: the conform worker set two of the six and no
/// one noticed the other four were still resolving on their own.
///
/// Set it before the loaders resolve — each caches its instance on first
/// touch, so pair a change with the relevant `debugResetForTests()`
/// (those stay per class: the cached instance really is per class).
///
/// `qa_tablet` is a different binary and keeps its own override, on
/// `QA_TABLET_PATH`.
String? debugQaEngineLibraryPathOverride;

/// Opens the engine binary, or null when there is none here or the one
/// found does not speak [kQaEngineAbiVersion].
///
/// The version gate lives INSIDE the open on purpose: a loader that
/// forgets to check cannot be written, because there is no other way to
/// get a handle. Struct-layout checks stay with whoever declares the
/// structs — see `qaAudioStructLayoutsMatch` — since only they know what
/// the layout is supposed to be.
///
/// The path comes from [debugQaEngineLibraryPathOverride], else the
/// `QA_ENGINE_PATH` environment variable CI sets, else the platform
/// defaults. A bad override falls THROUGH to those defaults rather than
/// failing, so a stale path degrades to "no engine" instead of hiding a
/// working one.
///
/// Absence is graceful everywhere this is called: every caller keeps a
/// Dart reference, a platform fallback, or an honest stand-down.
DynamicLibrary? openQaEngineLibrary() {
  final library = _open(
    debugQaEngineLibraryPathOverride ??
        Platform.environment['QA_ENGINE_PATH'],
  );
  if (library == null) {
    return null;
  }
  return qaEngineAbiMatches(library) ? library : null;
}

/// Whether [library] reports [kQaEngineAbiVersion].
///
/// Exposed separately for the tests that hold a library opened by other
/// means and want to say WHY it was refused.
bool qaEngineAbiMatches(DynamicLibrary library) {
  try {
    return library
            .lookupFunction<Int32 Function(), int Function()>(
              'qa_engine_abi_version',
            )
            .call() ==
        kQaEngineAbiVersion;
  } on Object {
    return false;
  }
}

DynamicLibrary? _open(String? path) {
  if (path != null && path.isNotEmpty) {
    try {
      return DynamicLibrary.open(path);
    } on Object {
      // Fall through to the platform defaults.
    }
  }
  // Apple: the plugin compiles the engine INTO the app binary (iOS
  // forbids loading a standalone dylib from a bundle), so the symbols
  // live in the process.
  if (Platform.isIOS || Platform.isMacOS) {
    try {
      return DynamicLibrary.process();
    } on Object {
      // Fall through: a standalone dylib build is still honored below.
    }
  }
  for (final candidate in [
    if (Platform.isWindows) 'qa_engine.dll',
    if (Platform.isLinux || Platform.isAndroid) 'libqa_engine.so',
    if (Platform.isMacOS) 'libqa_engine.dylib',
  ]) {
    try {
      return DynamicLibrary.open(candidate);
    } on Object {
      continue;
    }
  }
  return null;
}
