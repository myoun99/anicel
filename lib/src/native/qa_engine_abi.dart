import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import '../core/on_a_worker.dart';

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
///
/// - v26: `qa_resample_rgba` gained `clip_x` / `clip_y` — where the
///   destination buffer sits inside the FULL output rect the matrix was
///   built for. Zero is what every existing caller passes and means "the
///   buffer IS the rect".
///
///   It exists so a preview can resample only the pixels on screen. That
///   was tried before by recomputing the output rect, and abandoned
///   because the results differed: the destination pixel grid is anchored
///   to the rect's origin, so moving the origin moves every sample. The
///   offset keeps the grid and moves only the INDEX, which makes a window
///   bit-identical to the same window of the whole — the source position
///   comes out of the same multiply-add on the same operands rather than
///   out of an origin folded into `c`, and folding is where a position
///   sitting exactly on a pixel boundary rounds the other way.
///
/// - v27: `qa_video_decode_*` — the export path's mirror. A movie was the
///   one source that could not answer "the picture at frame N", which is
///   the question every media surface in this app is built on. Windows
///   reads through Media Foundation's Source Reader; the other platforms
///   answer `qa_video_decode_supported() == 0` until their reader is
///   written on a device that can verify it.
///
/// - v28: `qa_physical_memory_bytes` — the device's RAM, so the hot cel
///   budget scales to the machine instead of assuming a desktop-class one
///   (유저 확정 2026-08-16: RAM 비례 기본값 + 메모리 압박 반응). Zero when
///   the platform refuses to answer; callers treat that as "unknown" and
///   keep the desktop default.
///
/// - v29: `qa_process_footprint_bytes` and `qa_available_memory_bytes` —
///   what this PROCESS is holding, and what the OS will still let it
///   take. v28 answers neither: on iOS an app's allowance is neither the
///   device's free RAM nor a fraction of its total, so a budget scaled
///   from the machine can be double what the process is permitted, and
///   the app that dies has no way to say how big it had grown. The
///   footprint is the number a jetsam report calls `rpages × pageSize`.
///   🆕**2026-09-10 — every platform answers the footprint now**, and the
///   version did NOT move: the signature is unchanged, so an older binary
///   still returns 0 and the caller still reads that as "not measured".
///   The note that used to stand here — Windows and Linux report 0
///   because a per-process API would cost a link against psapi — was
///   wrong about the cost: kernel32 exports `K32GetProcessMemoryInfo`
///   (GetProcAddress, no import library) and Linux reads
///   `/proc/self/smaps_rollup`. All three arms now return the same
///   quantity: pages no other process shares, which is the number each
///   OS's own task manager shows.
/// - v30: `qa_zstd_*` — the cel compressor (vendored zstd 1.5.6). Cel
///   blobs are decompressed on the MAIN isolate in frame time whenever a
///   cold cel is promoted, and deflate was spending 3.35ms of a 16.7ms
///   frame on the median cel of a real project; zstd takes 0.11ms and is
///   5% smaller besides. ⛔deflate stays the floor — the blob carries a
///   codec byte and a build with no engine still writes and reads one.
/// - v31: `qa_dab_spec.aa_contrast` + `QA_DAB_FLAG_AA_THRESHOLD` — the
///   brush's own edge step (`BrushAntiAlias`). It HAD to reach the C
///   kernel: `qa_dab_blend_tiles` is what rasterizes a dab whenever the
///   engine is present, so an edge implemented only in Dart would be a
///   setting that does nothing in the shipped app.
/// - v32: `qa_dab_spec.dual_density` + `dual_one_minus_density` — how hard the
///   DUAL mask bites. The texture mask has had exactly this knob since it
///   shipped (`coverage *= (1 - d) + d * sample`) while the dual mask was an
///   unconditional multiply, all or nothing. Two masks doing the same job,
///   one of them dimmable and one not, is the whole reason. 1.0 is the old
///   behaviour, so every brush that never asks draws byte-identically.
/// - v33: `qa_dab_spec.reserved` becomes `dual_composite_mode` — how the dual
///   mask COMBINES with the coverage under it, through the same
///   `QA_STROKE_BLEND_*` ids and the same `qa_stroke_blend_channel` table
///   the stroke kernel reads. Both source formats carry one (Clip Studio's
///   `DualBrushCompositeMode`, Photoshop's `dualBrush.BlnM`) and ours only
///   multiplied. Multiply is the default and keeps its own line in every
///   transcription, so every brush that ever shipped draws byte-identically;
///   `add` gets a named combiner because it is not in the B(Cs, Cd) table.
///   Same slot, same size — `qa_dab_spec_sizeof` does not move.
///   ⚠️(Written a round late: the dual round bumped the number and left
///   this line out. The ABI test compares the two numbers, not the log.)
/// - v34: `qa_cel_pixel_spec` + `qa_cel_pixel_pass_tile` — the 색 변환 /
///   픽셀 비우기 pass over one tile, including the lazy copy. The Dart loop
///   in `cel_pixel_overwrite.dart` stays the reference and the no-engine
///   path. ⛔ONE TILE PER CALL: the originals stream is shared across
///   tiles in walk order, so a batched, pooled form would need every
///   tile's participation count before any tile could start — two passes
///   to save calls that cost tens of microseconds against a pass that
///   costs hundreds of milliseconds.
///   🚨The originals come back as RUNS and an undo reads its recipe at a
///   STEP (0 for a uniform one). The first shape — flat bytes out, a flat
///   stream in — left one Dart call per pixel on each side of the kernel,
///   and measured in one process it bought 1.6x on flat line art and
///   nothing on 4K. Written inside this version, before it landed.
/// - v35: the video decoder's document became a HANDLE. `qa_video_decode_open`
///   and `_open_range` answer one (0 is still 「could not」), `_info`,
///   `_frame` and `_close` take it, and `qa_video_decode_close_all` closes
///   the row of them. ONE native document meant whoever wanted a movie had
///   to put the other's back — measured ~111ms a switch — and a movie kept
///   as a reference put three more callers in the room at once: the canvas
///   it is shown on, the playback warmer filling the frames ahead, and
///   export walking a whole cut. Each backend still addresses exactly one
///   document; the law picks which slot before it calls a hook.
/// - v36: the memory tab's allowance reaches the engine (C-ipad-crash ②③,
///   유저 2026-09-16). `qa_tile_pool_set_byte_cap` sets the cap on the parked
///   tile blocks — a compile-time 512MB until then, so the one line of the
///   allowance the engine held sat outside it — and releases the excess when
///   lowered. `qa_app_memory_limit_bytes` answers what the OS lets THIS APP
///   hold, held plus still available, or 0 where an app has no limit of its
///   own: `qa_available_memory_bytes` on a desktop is the machine's free
///   memory, a different question, and the automatic allowance is half of
///   the app's limit where one exists and half the RAM where none does.
/// - v37: `qa_media_span_*` — ONE reader of a medium stored in a span of a
///   file, its own bytes or FRAMED (compressed in blocks), for every decoder
///   in the library and for Dart's own reads of a framed medium
///   (`QaMediaSpan`). `qa_video_decode_open_span` replaces `_open_range` and
///   takes `framed`; `qa_video_decode_framed_supported` says whether this
///   device's decoder can be fed a framed span (Android below API 28
///   cannot); `qa_audio_decode_span` replaces `_range`, and
///   `qa_audio_decode_memory` is gone with the in-memory origin it served.
///   Until this, a movie kept framed had no reader at all and a framed sound
///   was assembled whole in memory before anything decoded it (board
///   `carried-movie-compressed`, 유저 2026-09-24 「압축 유지 + 풀면서 디코더에
///   먹이는 리더를 플랫폼마다 만든다」).
/// - v38: `qa_dab_blend_batch` replaces `qa_dab_blend_tiles` — a call carries
///   every dab a route has (a frame of the live stroke, a run of the
///   commit): their specs, a clip each, and the tiles they cover staged
///   once. The kernel cuts those tiles into row bands and each band applies
///   every dab that reaches it, in order, so the bytes are the ones the dabs
///   made one at a time. At the 1% spacing the presets moved to (board
///   `preset-spacing-minimum`), one pooled call per dab woke the workers
///   once a dab — ~0.2 ms, as long as a 100 px dab takes alone — and the
///   pool bought nothing below 200 px.
/// - v39: `qa_dab_spec.tip_row_ink` — each tip mask row's first and last
///   inked column (`BrushTipMask.inkedColumns`) — and an unrotated tip's row
///   visits only the pixels whose texels can hold ink. Every brush dab
///   reaches the kernel as a mask prerendered per quantized size, and a
///   round one is bare in its corners, about a fifth of the box that was
///   sampled to a coverage of 0 and thrown away (board `brush-kernel-next`
///   ②). Skipped pixels are exactly those the loop would `continue` on, so
///   the bytes do not move. `qa_dab_spec_sizeof` moves.
/// - v40: `qa_tile_span.tile_wide` — the stroke tile's 16-bit plane — and
///   `qa_dab_blend_tile` takes it. A dab reads what is under it from the
///   plane and writes both planes from the same double (`qa_dab_store`), so
///   a soft tail that lays under half a level a dab piles up at last and the
///   rest stops piling up a rounding a dab (board
///   `one-pixel-steps-change-a-brush-with-its-size` Q2, 유저 2026-10-01 「a는
///   제안한대로 16비트?」). The bytes stay the view everything downstream
///   reads. `qa_tile_span_sizeof` moves.
/// - v41: `qa_dab_spec.evening` — the table a dab lays its share of one
///   stamp per tenth of its size through (`stampShareOf`, `qa_dab_even`) —
///   and the laid alpha reads it, so a brush piles up the same at every
///   size (board `one-pixel-steps-change-a-brush-with-its-size`, 유저
///   2026-10-01 「환산은 커널에서 — 모든 브러시」). The table is built once
///   per share in Dart and copied into the batch arena once per batch, so no
///   pixel pays a power and both kernels read the same numbers.
///   `qa_dab_spec_sizeof` moves.
/// - v42: `qa_audio_decode_span_window` — a window of a sound's frames, and
///   only those held: a piece cut from a long reel decodes from the start
///   but keeps the piece (board sound-lands-on-its-exact-sample-Q5, 유저
///   2026-10-09). `qa_audio_decode_span` is its whole window.
/// - v43: `qa_audio_stream_open` / `_read` / `_close` — a sound opened once
///   and read on, every decoder through one door (the window decode is that
///   stream, passed over to the window) — and `qa_audio_resampler_*`, the
///   resampler fed a piece at a time through the loop `qa_audio_resample`
///   runs. A long sound is conformed as it is decoded instead of whole in
///   memory (board long-sound-conform-memory-Q1, 유저 2026-10-10 「지금
///   한다 — 전 플랫폼」).
/// - v44: `qa_display_vblank` / `qa_display_wait_until_us` — the
///   compositor's vblank (Windows' DWM; 0 everywhere else) and a wait that
///   ends on a microsecond, for a clock's frame to be handed to the GPU
///   where it lands on the vblank it claimed (`QaDisplayTiming`, board
///   playback-frame-raster-is-the-whole-window, 유저 2026-10-11 「144hz든
///   몇이든 확실하게」).
/// - v45: `qa_display_compose_every_vblank` — the compositor kept composing
///   on every vblank while a clock runs, so a picture handed over between
///   two vblanks is taken at the second of them however idle the desktop
///   leaves it (`QaDisplayTiming.composeEveryVblank`; the same board card).
/// - v46: `qa_premultiply_rgba_rows` — the premultiplied copy between two
///   row strides, so the tiles of a cel nobody has pictured go up a block
///   at a time with one call a tile (`surfaceRegionPicture`,
///   board a-cold-cel-composes-tile-by-tile).
/// - v47: `qa_audio_capture_clock` / `qa_audio_capture_frames` — the
///   capture's own clock line, the playback's shape, so a take is placed by
///   what the microphone had taken in when its anchor was HEARD
///   (`AudioRecorder.capturedAt`, board take-head-trims-at-the-playback-start).
/// - v48: `qa_audio_buffer_new` / `_retain` / `_release` / `_holds`, and a
///   `qa_audio_device_set_schedule` that names buffers — the device's PCM
///   is made once in C memory and a schedule copies none of it
///   (`QaAudioDevice.setSchedule`, board play-press-first-frame-stall).
/// - v49: `qa_key_rgba` — a row's colour keys over straight pixels in
///   place, from tables the one definition makes (`CelColorKey`), so a cel
///   on a keyed row is shown at C speed — a live stroke's every tile, every
///   flush (`QaNativeEngine.keyRgba`, board a-stroke-on-a-keyed-row-shows-
///   its-tiles-unkeyed).
/// - v50: `qa_audio_device_play` gains `lead_samples` — a run started that
///   much silence ahead of its first sample, so the sample is heard as the
///   run's first picture is shown (`QaAudioDevice.play`, board a-start-is-
///   heard-ahead-of-its-first-picture).
/// - v51: the stroke kernel's mode ids 13–25 — the seven separable blends
///   Photoshop and Clip Studio add (linear burn … divide), which the dual
///   mask reads too, and the six that mix the three channels
///   (`strokeBlendModeNativeId`, board brush-fidelity). An older engine
///   would take an id it does not know for exclusion.
/// - v52: `qa_cel_pixel_spec` gains `threshold` — 2치화, the colour edit
///   list's fifth pixel verb: a byte under it is written 0 and the rest the
///   incoming byte, forward only (`CelPixelStage.threshold`, board I-13).
///   Sizeof moves.
/// - v54: the fill raster is premultiplied RGBA over nothing — no paper —
///   and every flood takes its seed as one packed RGBA pixel, the coverage
///   a lane like the colours (board F-416). `qa_fill_paper_rect` becomes
///   `qa_fill_clear_rect`; `qa_fill_compose_batch` loses the paper.
/// - v55: `qa_audio_device_play` returns the run it starts (it returned 1),
///   and `qa_audio_device_stop_run` silences unless another run holds the
///   device — a player's end stops only its own sound (board
///   a-cue-ending-silences-a-viewer-sound-it-did-not-make).
/// - v56: `qa_dab_spec` drops `hard_radius` and `edge_span` for an analytic
///   round tip's profile — `round_scale`, `round_reach`, `round_inner` and
///   the two tables `round_coverage` and `round_pile` — and
///   `QA_DAB_FLAG_EDGE_HELD`: a round tip is two ramps and a pixel's square
///   read along its radius (`RoundTipProfile`), not a mask the stamp cache
///   baked, and its edge does not pile (board
///   a-one-pixel-dab-drops-out-by-where-it-lies Q4, 유저 2026-10-25 「AA
///   가장자리는 쌓이지 않는다」). The tables are built once per tip in Dart
///   and copied into the batch arena once per batch. `qa_dab_spec_sizeof`
///   moves.
/// - v57: `qa_dab_spec` gains `round_row_length`: a small circle's round
///   tables are SQUARE — what each pixel's whole square covers, read at
///   (|dx|, |dy|) (`qa_round_square_at`) — so a dot lays the same ink
///   wherever it lies (board a-one-pixel-dab-drops-out-by-where-it-lies Q6,
///   유저 2026-10-25). 0 keeps them along the radius. `qa_dab_spec_sizeof`
///   moves.
/// - v58: `qa_blur_dab` and `qa_blur_result_tile` — the blur brush (I-75,
///   유저 Q1 「섞기 그룹에 「흐리기」」): a dab rewrites the picture under it,
///   read through a `qa_blur_tile` table (`qa_blur_tile_sizeof`), at the C
///   speed its finest step needs.
/// - v59: `qa_key_rgba` gains `originals`, and its `keeps` bitmask is
///   `restores` — a key gives back what its run erased of what it names,
///   AE's Keep Colors (`CelKeyOperation.restoreMatches`, I-132-Q2 유저
///   2026-10-27 「하나로 + AE 뜻」), where it erased what it did not name.
/// - v60: the second tip is a SECOND STROKE (an-imported-pencil-drops-its-
///   second-brush Q3 b, 유저 2026-10-25 「두 번째 획으로 다시 만든다」): its
///   dabs (`dabFlagSecond`) pile on `qa_tile_span.tile_second`, and
///   `qa_dab_blend_batch` takes the view's `dual_mode` and `dual_density`
///   and rebuilds a span's bytes from both planes (`qa_dual_view_rows`).
///   `qa_dab_spec` drops the per-dab dual mask. Both sizeofs move.
/// - v61: `qa_fx_plugin_*` — the fx plugin host (I-132-Q5 b · Q31): a
///   plugin opened from a native library or a WebAssembly module (Wasmtime
///   where the build linked it) and asked to describe, reach and render
///   (`qa_fx_render_job_sizeof` · `qa_fx_picture_sizeof`).
const int kQaEngineAbiVersion = 61;

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

/// [job] on a worker ([onAWorker]) that loads the binary this isolate
/// loads: a worker resolves every loader from scratch, and
/// [debugQaEngineLibraryPathOverride] is a static — statics do not cross
/// isolates.
///
/// ⚠️Written down once when opening the output ahead became the THIRD job to
/// carry the path (play-press-first-frame-stall, 10-16): a trimmed movie's
/// span and a trimmed sound's had each spelled the same two lines out.
Future<T> onAWorkerWithThisEngine<T>(FutureOr<T> Function() job) =>
    onAWorkerWithThisEngineReporting(null, (_) => job());

/// [onAWorkerWithThisEngine] for a job that says how far it is
/// ([onAWorkerReporting]).
Future<T> onAWorkerWithThisEngineReporting<T>(
  void Function(double fraction)? onProgress,
  FutureOr<T> Function(void Function(double fraction) report) job,
) {
  final library = debugQaEngineLibraryPathOverride;
  return onAWorkerReporting(onProgress, (report) {
    debugQaEngineLibraryPathOverride ??= library;
    return job(report);
  });
}

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
    debugQaEngineLibraryPathOverride ?? Platform.environment['QA_ENGINE_PATH'],
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

/// Whether [library]'s `[symbol]()` — the size the C lays a struct out at —
/// is [dartSize], what Dart lays it out at. Both sides must agree on every
/// byte, or every field read is garbage; whoever declares the struct asks.
/// Throws where [library] has no [symbol].
bool qaStructSizeMatches(
  DynamicLibrary library,
  String symbol,
  int dartSize,
) =>
    library.lookupFunction<Int32 Function(), int Function()>(symbol).call() ==
    dartSize;

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
