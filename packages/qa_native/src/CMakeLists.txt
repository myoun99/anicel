# The native core's ONE build description, shared by every consumer:
# the plugin's per-platform build files include this (Windows included —
# the 2A migration is complete), and CI builds it standalone for the
# parity suites.
#
# Nothing platform-specific lives here except the compiler flags, because
# qa_engine.c is one portable C99 source by design.
# ↩️3.16 was for OBJC language support, which the Apple video writer and
# reader (`qa_video_apple.m`) needed; they went to the Rust engine in the
# connection round (connection-round-checklist H, 2026-11-08), and nothing
# here is Objective-C now.
cmake_minimum_required(VERSION 3.16)
project(qa_engine LANGUAGES C)

# ↩️The sound decoder (qa_audio_decode.c, with its vendored dr_libs and
# stb_vorbis), the span reader (qa_media_span.c, with the zstd amalgamation)
# and the OS media glue (qa_win_range_stream.c, qa_win_media_foundation.c,
# qa_ndk_media.c) were translation units of their own here, and the movie
# encoder and decoder two more, until the connection round moved them to the
# Rust engine (native/audio, native/media, native/video;
# connection-round-checklist H, 2026-11-08).
add_library(qa_engine SHARED
  "${CMAKE_CURRENT_LIST_DIR}/qa_engine.c"
)

set_target_properties(qa_engine PROPERTIES
  C_STANDARD 99
  C_STANDARD_REQUIRED ON
)

# ↩️THE FIRST NATIVE CODE CI ACTUALLY RAN was the decode law's test
# (qa_video_decode_law_test.c): the portability job had built this library
# with two compilers and printed a directory listing, until the law was
# lifted out of the per-OS `#if` blocks and a Linux runner had something to
# execute. It went with the decoder in the connection round
# (connection-round-checklist H, 2026-11-08); the law is held in Rust now
# (native/video `decode/tests.rs`), where every host runs it.

# ↩️The span reader's test (qa_media_span_test.c), the range decode's
# (qa_audio_range_test.c) and the Media Foundation byte stream's
# (qa_win_range_stream_test.c) went with what they tested in the connection
# round; they are Rust's now (native/media `span/tests.rs` and
# `tests/span_stream.rs`, native/audio `tests/movies.rs`).

# ↩️The hardware law's test (card surface-engine-mp4-pieces-fail-to-
# finalize) went with the encoder in the connection round; the law and its
# cases are Rust's now (native/video `hardware_law.rs`).

# ↩️The last test here (qa_engine_pool_test.c) held several callers at once
# on the engine's one worker pool (card clip-import-hangs-on-three-samples);
# it went with the pool and the brush kernels the pool spread (ABI 80,
# 2026-11-12). Nothing the C still does has a test of its own in C: its
# premultiply is held from Dart.

# ↩️Vendored dr_libs and zstd emitted a few benign conversion warnings, which
# were silenced on their translation units alone, until the connection round
# deleted both: what is compiled here is ours, and keeps every warning.

# Nothing of the OS is linked. 🪦The C's sound device (miniaudio) linked
# CoreAudio here and OpenSLES on Android, and the C's sound decoder and movie
# codecs linked AudioToolbox and CoreFoundation (Apple), mediandk (Android)
# and Media Foundation with ole32 (Windows), until the connection round moved
# them into the GPU engine's library (connection-round-checklist H,
# 2026-11-08). 🪦shlwapi went before them, with the in-memory audio origin it
# served (SHCreateMemStream, 2026-09-24). 🪦The threads and dl libraries went
# last (ABI 82, 2026-11-12): the lock on the tile blocks' lists was the last
# thing here that waited on another thread, and libm went with them — the
# float kernels it served left at ABI 80.

if(MSVC)
  # The engine must run OPTIMIZED even inside the app's Debug build (the
  # project's performance bar is debug mode). MSVC's Debug defaults
  # (/RTC1 /Od /Ob0) conflict with /O2 - strip them for this directory
  # only, from EVERY language the engine is compiled in.
  # ↩️Only C's were stripped until 2026-10-13: the compose unit made the
  # engine C++ as well (bd01a2a91), its file kept /RTC1 beside /O2, and the
  # app's Windows Debug build stopped building (cl D8016) — profile and
  # release, which have no /RTC1, said nothing.
  get_property(qa_languages GLOBAL PROPERTY ENABLED_LANGUAGES)
  foreach(qa_language IN LISTS qa_languages)
    foreach(qa_flag IN ITEMS /RTC1 /Od /Ob0)
      string(REPLACE "${qa_flag}" "" CMAKE_${qa_language}_FLAGS_DEBUG
        "${CMAKE_${qa_language}_FLAGS_DEBUG}")
    endforeach()
  endforeach()
  # /utf-8: the sources ARE UTF-8 (em-dash and Korean comments). Without
  # it MSVC reads them in the SYSTEM code page and floods C4819 on
  # Japanese/Korean Windows (CP932/949) - harmless here (non-ASCII lives
  # only in comments, and UTF-8 never emits a 0x5C byte) but noisy on
  # every app build.
  target_compile_options(qa_engine PRIVATE /O2 /fp:precise /utf-8)
else()
  # -O3 auto-vectorizes the pixel loops (SSE/AVX on x86, NEON on ARM);
  # no hand-written intrinsics needed.
  #
  # -ffp-contract=off is the byte-parity contract, not a micro-tuning
  # knob: clang fuses `a*b + c` into a single FMA whenever the target has
  # one, and an FMA rounds ONCE where Dart rounds twice. On x86 that
  # never fired (no FMA in the baseline target) so five rounds of engine
  # work looked fine — the first parity run on Apple silicon came back
  # 182 where the reference says 181. Contraction stays off so the same
  # source produces the same pixels on every CPU.
  target_compile_options(qa_engine PRIVATE -O3 -ffp-contract=off)
endif()

# 🚨EVERY COMPILER REFUSES WHAT THE STRICTEST ONE REFUSES.
#
# 2026-09-10: a splice left three lines of a function body above the file's
# first comment, and `coverage = 1.0;` at file scope is an implicit-int
# declaration — an error for Apple clang and for the NDK's clang, and a
# warning MSVC does not even print at its default level. Every Windows build
# and every test on the development machine stayed green for over a day
# while the iPad build could not compile, and the only thing that noticed
# was the build shipping to TestFlight.
#
# So the two things clang refuses by default in C99 are refused here on
# every compiler: a declaration with no type (C4431), and a call to a
# function nothing declared (C4013).
if(MSVC)
  target_compile_options(qa_engine PRIVATE /we4431 /we4013)
else()
  target_compile_options(qa_engine PRIVATE
    -Werror=implicit-int -Werror=implicit-function-declaration)
endif()
