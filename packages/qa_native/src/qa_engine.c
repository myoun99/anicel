// Anicel native engine core (R18 A-track) - nothing is left of it but the
// number below. Every kernel that drew is the GPU engine's, and the last two
// things the app took from here went to that engine's library: the tile
// blocks' lists (native/tile_blocks) and the premultiplied copy
// (native/premultiply) - the ABI history at the foot of this file. The
// package goes next (board connection-round-checklist).

#include <stdint.h>

#if defined(_WIN32)
#define QA_EXPORT __declspec(dllexport)
#else
#define QA_EXPORT __attribute__((visibility("default")))
#endif

// Engine ABI version - ONE number for this whole binary, and the Dart
// loader refuses a mismatched one.
//
// The changelog and the bump checklist live in the single place Dart
// reads this from: lib/src/native/qa_engine_abi.dart. Bumping here
// without bumping there fails qa_engine_abi_test.dart, which compares the
// literal below against kQaEngineAbiVersion and needs no binary to do it.
// v25: qa_resample_rgba - the shared image resampler (tent mean / coverage
// argmax) behind the transform tool, FX transforms, import fit and screen
// minification.
// v26: qa_resample_rgba gained clip_x/clip_y - where the destination
// buffer sits inside the full output rect, so a caller can compute one
// window of it bit-identically. Zero is the whole rect.
// v27: qa_video_decode_* - the export path's mirror (qa_video_decode.c).
// v28: qa_physical_memory_bytes - the device's RAM, for the hot cel
// budget.
// v29: qa_process_footprint_bytes / qa_available_memory_bytes - what this
// process is actually holding, and what the OS will still let it take.
// v31: qa_dab_spec gains aa_contrast + QA_DAB_FLAG_AA_THRESHOLD (brush edge).
// v32: qa_dab_spec gains dual_density + dual_one_minus_density.
// v33: qa_dab_spec's `reserved` int32 becomes dual_composite_mode - how the
// dual mask COMBINES with the coverage under it, through the same
// QA_STROKE_BLEND_* ids and the same qa_stroke_blend_channel table the
// stroke kernel reads. Multiply is the default and keeps its own line, so
// every brush that ever shipped draws byte-identically. Same slot, same
// size: sizeof does not move.
// v34: qa_cel_pixel_spec + qa_cel_pixel_pass_tile - the 색 변환 / 픽셀
// 비우기 pass over one tile, lazy copy included. One tile per call: the
// originals stream is shared across tiles in walk order, so a batched,
// pooled form would need every tile's count before any could start.
// Originals come back as RUNS, and an undo reads its recipe at a step
// (0 for a uniform one) - the flat-bytes shape left a Dart call per pixel on
// each side of the kernel. Changed inside this version, before it landed.
// v35: the video decoder's document became a HANDLE. `qa_video_decode_open`
// and `_open_range` answer one (0 is still failure), `_info`, `_frame` and
// `_close` take it, and `qa_video_decode_close_all` closes the lot. One
// native document meant a ~111ms re-open per switch, and a movie kept as a
// reference put three callers in the room at once — the canvas where it is
// shown, the playback warmer ahead of it, and export walking the cut.
// v36: qa_tile_pool_set_byte_cap + qa_app_memory_limit_bytes - the memory
// tab's allowance reaches the parked tile blocks (C-ipad-crash).
// v37: qa_media_span_* - ONE reader of a medium stored in a span, plain or
// framed, for every decoder and for Dart. `qa_video_decode_open_span`
// replaces `_open_range` and takes `framed`; `qa_video_decode_framed_
// supported` says whether this device can be fed a framed span;
// `qa_audio_decode_span` replaces `_range`, and `qa_audio_decode_memory` is
// gone with the in-memory origin it served.
// v38: qa_dab_blend_batch replaces qa_dab_blend_tiles - a call carries
// every dab it has (specs, and a clip each), the tiles they cover once, and
// the kernel cuts those tiles into row bands, each applying every dab that
// reaches it in order. One wake of the pool a call instead of one a dab.
// v39: qa_dab_spec gains tip_row_ink - each tip mask row's first and last
// inked column - and an unrotated tip's row visits only the pixels whose
// texels can hold ink (qa_tip_row_reach). Sizeof moves.
// v40: qa_tile_span gains tile_wide - the stroke tile's 16-bit plane - and
// qa_dab_blend_tile takes it: a dab reads what is under it from the plane
// and writes both planes (qa_dab_store). Sizeof moves.
// v41: qa_dab_spec gains evening - the table a dab lays its share of one
// stamp per tenth of its size through (qa_dab_even) - and the laid alpha
// reads it in qa_dab_source_alpha and the pair path. Sizeof moves.
// v42: qa_audio_decode_span_window - a window of a sound's frames, and only
// those held.
// v43: qa_audio_stream_open/_read/_close - a sound opened once and read on,
// every decoder through one door - and qa_audio_resampler_* - the resampler
// fed a piece at a time, through the loop qa_audio_resample runs.
// v44: qa_display_vblank / qa_display_wait_until_us - the compositor's
// vblank and a wait that ends on a microsecond, for a clock's frame to be
// handed to the GPU where it lands on the vblank it claimed.
// v45: qa_display_compose_every_vblank - the compositor kept composing on
// every vblank while a clock runs, so a picture handed over between two
// vblanks is taken at the second of them however idle the desktop is.
// v46: qa_premultiply_rgba_rows - the premultiplied copy between two row
// strides, so a block of tiles becomes one picture with one call a tile.
// v47: qa_audio_capture_clock / qa_audio_capture_frames - the capture's own
// clock line, so a take is placed by what the microphone had taken in when
// its anchor was heard.
// v48: qa_audio_buffer_new / _retain / _release / _holds, and a set_schedule
// that names buffers - the device's PCM is made once in C memory, and a
// schedule copies none of it.
// v49: qa_key_rgba - a row's colour keys over straight pixels in place,
// from tables the Dart definition makes, so a keyed cel is shown at C speed.
// v50: qa_audio_device_play gains lead_samples - a run started that much
// silence ahead of its first sample, so that sample is heard as its first
// picture is shown.
// v51: the stroke kernel's mode ids 13-25 - seven separable blends Photoshop
// and Clip Studio add (linear burn ... divide), which the dual mask reads
// too, and six that mix the three channels (qa_stroke_blend_triple). An
// older engine would take an id it does not know for exclusion.
// v52: qa_cel_pixel_spec gains threshold - 2치화: a byte under it is written
// 0 and the rest the incoming byte, forward only. Sizeof moves.
// v53: QA_DAB_FLAG_TEXTURE_HEIGHT - the paper's height cuts a dab's
// coverage (F-451). An older engine would multiply it.
// v54: the fill raster is premultiplied RGBA over nothing - no paper -
// and every flood takes its seed as one packed RGBA pixel, the coverage
// a lane like the colours (F-416). qa_fill_paper_rect becomes
// qa_fill_clear_rect; qa_fill_compose_batch loses the paper.
// v55: qa_audio_device_play returns the run it starts (it returned 1), and
// qa_audio_device_stop_run silences unless another run holds the device -
// a player's end stops only its own sound.
// v56: qa_dab_spec drops hard_radius and edge_span for an analytic round
// tip's profile - round_scale, round_reach, round_inner and the tables
// round_coverage and round_pile - and QA_DAB_FLAG_EDGE_HELD: a round tip is
// its profile read along its radius (qa_round_profile_at), and its edge does
// not pile (qa_dab_source_alpha's ceiling). Sizeof moves.
// v57: qa_dab_spec gains round_row_length: a small circle's round tables
// are square, what each pixel's whole square covers (qa_round_square_at),
// so a dot lays the same ink wherever it lies. Sizeof moves.
// v58: qa_blur_dab and qa_blur_result_tile - the blur brush (I-75): a dab
// rewrites the picture under it, read through a qa_blur_tile table.
// v59: qa_key_rgba gains originals, and its keeps bitmask is restores - a
// key gives back what its run erased of what it names (AE's Keep Colors,
// I-132-Q2) instead of erasing what it does not name.
// v60: the second tip is a second stroke - QA_DAB_FLAG_SECOND dabs pile on
// qa_tile_span's new tile_second plane, and qa_dab_blend_batch takes the
// view's dual_mode and dual_density and rebuilds the bytes of a span that
// carries it from both planes (qa_dual_view_rows). qa_dab_spec drops the
// per-dab dual mask - dual_density, dual_one_minus_density, dual_size,
// dual_composite_mode and its lattices. Sizeof moves, both structs.
// v62: stroke blend ids 26 and 27, Clip Studio's two 発光 modes, and id 1
// (add) reads a B and mixes by alpha - the saturating add it was is id 27.
// v63: qa_display_window_screens - the vblanks of the screens the app's
// window lies on, which the compositor's own clock is not when one of them
// is slower than it.
// v64: qa_fx_plugin_* leave - the fx plugin host is the Rust engine's
// (native/fx_plugin), which the app opens in the GPU engine's library.
// v65: qa_display_* and Apple's qa_pen_ledger_* leave - the display's timing
// and the pen ledger are the Rust engine's (native/display, native/pen),
// which the app opens in the GPU engine's library.
// v66: qa_audio_resample*, qa_audio_resampler_* and qa_audio_denoise_f32
// leave - the conform's resampler and the voice take's denoiser are the
// Rust engine's (native/audio_mix, native/audio_denoise), which the app
// opens in the GPU engine's library.
// v67: qa_image_encode_jpg and qa_image_encode_free leave - the JPEG encoder
// is the Rust engine's (native/image_encode), which the app binds in the GPU
// engine's library.
// v68: qa_zstd_compress_bound, qa_zstd_compress, qa_zstd_decompressed_size
// and qa_zstd_decompress leave - the cel compressor is the Rust engine's
// (native/compress), which the app binds in the GPU engine's library. The
// span reader keeps its own zstd decoder.
// v69: qa_physical_memory_bytes, qa_process_footprint_bytes,
// qa_available_memory_bytes and qa_app_memory_limit_bytes leave - the memory
// questions are the Rust engine's (native/memory), which the app binds in
// the GPU engine's library.
// v70: qa_audio_device_*, qa_audio_capture_*, qa_audio_buffer_*,
// qa_audio_clock_now_us and the mixer - qa_audio_mix, qa_audio_bus_to_* and
// the three qa_audio_*_sizeof - leave: the sound device and its mixer are
// the Rust engine's (native/audio_device, native/audio_mix), which the app
// binds in the GPU engine's library.
// v71: qa_video_export_* and qa_video_decode_* leave - the movie writer and
// reader are the Rust engine's (native/video), which the app binds in the GPU
// engine's library, as it binds native/media's span reader there. The C's
// qa_media_span_* stay, for the C's audio decoder alone, until it moves.
// v72: qa_audio_decode_*, qa_audio_stream_* and qa_media_span_* leave - the
// sound decoder is the Rust engine's (native/audio), which the app binds in
// the GPU engine's library with native/media's span reader. The engine is
// its raster half alone: no media, no zstd, no OS codec stack.
// v74: qa_alpha_bounds_tiles leaves - a cel's ink is found by the GPU engine.
// v75: qa_cel_pixel_spec and qa_cel_pixel_pass_tile leave - a cel's colour
// verbs run on the GPU engine's kernel.
// v76: qa_resample_rgba leaves - every resample is the GPU engine's R1 (a
// float's warps, a posed row a fill reads), and the C resamples nothing.
// v77: qa_tile_alpha_bounds and qa_premultiply_rgba leave - nothing bound
// the first and nothing called the second - and qa_stamp_blend_row,
// qa_dab_blend_tile, qa_stamp_blend_tile and qa_stroke_blend_tile are
// exported no longer: each is called by a batch here and by nothing outside.
// v78: qa_fill_clear_rect, qa_fill_compose_tile, qa_fill_compose_batch (with
// qa_compose_blend_sizeof and qa_compose_tile_item_sizeof),
// qa_flood_fill_wave, qa_fill_gap_close_run and qa_fill_finish_mask leave -
// the bucket's fill reads the frame's picture, floods, closes gaps and is
// finished on the GPU engine (kernels/flood, kernels/mask), and the C
// fills nothing.
// v79: qa_key_rgba leaves - a row's colour keys are the GPU engine's key
// run, wherever a plugin stands in its chain, and the C keys nothing.
// v80: the brush leaves - qa_dab_blend_batch (with qa_dab_spec_sizeof and
// qa_tile_span_sizeof), qa_stamp_blend_tiles, qa_stroke_blend_tiles,
// qa_pre_blend_tiles, qa_blur_dab and qa_blur_result_tile (with
// qa_blur_tile_sizeof), qa_copy_bytes and qa_widen_bytes, and the worker
// pool they spread over. A stroke is the GPU engine's on its grid
// (kernels/dab, kernels/blend) and the Dart kernel's on any other, and the
// C draws nothing: it premultiplies a copy and hands out tile blocks.
// v81: qa_premultiply_rgba_rows leaves - an export's sheet ink, its last
// caller, is premultiplied on a Dart worker (export-on-engine) - and
// qa_zero_bytes with it: the tiles' compose was the last to zero here.
// v82: the tile allocator leaves - qa_tile_alloc, qa_tile_free,
// qa_tile_pool_cached_bytes, qa_tile_pool_trim and
// qa_tile_pool_set_byte_cap are the GPU engine library's (native/tile_blocks),
// the same five names and the same lists. Bound there by name, a block is
// the process's whichever isolate asks for it, and a build without this
// binary parks its blocks as any other does.
// v83: qa_premultiply_rgba_copy leaves - a tile's premultiplied copy is the
// GPU engine library's (native/premultiply), the same name and the same
// four-pixel steps, bound there by name. Nothing is exported from here but
// this number, and nothing in the app opens this binary.
QA_EXPORT int32_t qa_engine_abi_version(void) { return 83; }
