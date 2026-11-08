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

# qa_audio_decode.c is a second translation unit rather than more of
# qa_engine.c: it pulls in ~27k lines of vendored dr_libs, and compiling
# that alongside the hot loops would slow every build and mix third-party
# warnings into ours. ↩️The movie encoder and decoder (qa_video_encode.c,
# qa_video_decode.c) were two more, until the connection round moved them
# to the Rust engine (native/video).
add_library(qa_engine SHARED
  "${CMAKE_CURRENT_LIST_DIR}/qa_engine.c"
  "${CMAKE_CURRENT_LIST_DIR}/qa_audio_decode.c"
  "${CMAKE_CURRENT_LIST_DIR}/qa_media_span.c"
    "${CMAKE_CURRENT_LIST_DIR}/third_party/zstd/zstd.c"
)
# ⛔WIN32 only: an `IMFByteStream` over a range — and starting Media
# Foundation at all — is Media Foundation's problem and nobody else's, and
# a translation unit that compiles to nothing elsewhere is a warning
# waiting to happen.
if(WIN32)
  target_sources(qa_engine PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/qa_win_range_stream.c"
    "${CMAKE_CURRENT_LIST_DIR}/qa_win_media_foundation.c")
endif()
# ⛔ANDROID only, for the same reason: serving a span to MediaExtractor is
# libmediandk's business and nobody else's (see qa_ndk_media.h for why there
# is one of it).
if(ANDROID)
  target_sources(qa_engine PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/qa_ndk_media.c")
endif()

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

# The span reader — plain and framed — with nothing platform-specific in it,
# so it runs on every host CI has. See qa_media_span_test.c for why it
# COUNTS blocks rather than only comparing bytes.
if(NOT ANDROID AND NOT IOS)
  add_executable(qa_media_span_test
    "${CMAKE_CURRENT_LIST_DIR}/qa_media_span_test.c"
    "${CMAKE_CURRENT_LIST_DIR}/qa_media_span.c"
    "${CMAKE_CURRENT_LIST_DIR}/third_party/zstd/zstd.c")
  set_target_properties(qa_media_span_test PROPERTIES
    C_STANDARD 99
    C_STANDARD_REQUIRED ON
  )
  if(MSVC)
    target_compile_options(qa_media_span_test PRIVATE /utf-8)
  endif()
  enable_testing()
  add_test(NAME qa_media_span COMMAND qa_media_span_test)
endif()

# Decoding a container that is a RANGE of a file. ⚠️This one carries the
# WHOLE decoder — dr_libs, stb_vorbis and whatever OS stack the host has —
# because the thing under test is the dispatch itself: the same chain has to
# reach the same answer whether the bytes are in memory or in the middle of a
# project file. The fixture is a WAV it writes itself, so the checks are the
# same everywhere even though the platforms underneath are not.
if(NOT ANDROID AND NOT IOS)
  add_executable(qa_audio_range_test
    "${CMAKE_CURRENT_LIST_DIR}/qa_audio_range_test.c"
    "${CMAKE_CURRENT_LIST_DIR}/qa_audio_decode.c"
    "${CMAKE_CURRENT_LIST_DIR}/qa_media_span.c"
    "${CMAKE_CURRENT_LIST_DIR}/third_party/zstd/zstd.c")
  set_target_properties(qa_audio_range_test PROPERTIES
    C_STANDARD 99
    C_STANDARD_REQUIRED ON
  )
  # ⚠️stb_vorbis calls `sin`, `pow`, `log`. On Linux those live in libm and
  # nothing pulls it in implicitly — qa_engine has always linked it, and the
  # first CI run of this target found out the hard way that a target which
  # compiles the same source needs the same libraries.
  if(APPLE)
    target_link_libraries(qa_audio_range_test
      "-framework CoreFoundation" "-framework AudioToolbox")
  elseif(WIN32)
    # The Windows range origin hands Media Foundation the span's
    # byte stream, and starts Media Foundation the engine's one way, so the
    # test needs those translation units too.
    target_sources(qa_audio_range_test PRIVATE
      "${CMAKE_CURRENT_LIST_DIR}/qa_win_range_stream.c"
      "${CMAKE_CURRENT_LIST_DIR}/qa_win_media_foundation.c")
    target_link_libraries(qa_audio_range_test
      mfplat mfreadwrite mfuuid ole32)
  else()
    find_library(QA_M_LIB m)
    if(QA_M_LIB)
      target_link_libraries(qa_audio_range_test ${QA_M_LIB})
    endif()
  endif()
  if(MSVC)
    target_compile_options(qa_audio_range_test
      PRIVATE /utf-8 /wd4267 /wd4244 /wd4996 /wd4018 /wd4389)
  else()
    target_compile_options(qa_audio_range_test
      PRIVATE -Wno-conversion -Wno-unused-function)
  endif()
  enable_testing()
  add_test(NAME qa_audio_range COMMAND qa_audio_range_test)
endif()

# The range byte stream, driven for real. ⚠️Unlike the law test above, this
# one WANTS its platform: the object under test IS Media Foundation's
# interface, so there is nothing portable to check and the MF libraries are
# exactly what it needs.
if(WIN32)
  add_executable(qa_win_range_stream_test
    "${CMAKE_CURRENT_LIST_DIR}/qa_win_range_stream_test.c"
    "${CMAKE_CURRENT_LIST_DIR}/qa_win_range_stream.c"
    "${CMAKE_CURRENT_LIST_DIR}/qa_win_media_foundation.c"
    "${CMAKE_CURRENT_LIST_DIR}/qa_media_span.c"
    "${CMAKE_CURRENT_LIST_DIR}/third_party/zstd/zstd.c")
  set_target_properties(qa_win_range_stream_test PROPERTIES
    C_STANDARD 99
    C_STANDARD_REQUIRED ON
  )
  target_link_libraries(qa_win_range_stream_test mfplat mfuuid ole32)
  if(MSVC)
    target_compile_options(qa_win_range_stream_test PRIVATE /utf-8)
  endif()
  enable_testing()
  add_test(NAME qa_win_range_stream COMMAND qa_win_range_stream_test)
endif()

# ↩️The hardware law's test (card surface-engine-mp4-pieces-fail-to-
# finalize) went with the encoder in the connection round; the law and its
# cases are Rust's now (native/video `hardware_law.rs`).

# Several callers at once on the engine's one pool and one wave arena (card
# clip-import-hangs-on-three-samples): every isolate calls the engine from a
# thread of its own, and nothing else that runs here calls it from more than
# one. It includes the engine's translation unit. ↩️As the law tests and
# the transport test included theirs, until the connection round moved the
# movie laws and the sound device to the Rust engine.
if(NOT ANDROID AND NOT IOS)
  add_executable(qa_engine_pool_test
    "${CMAKE_CURRENT_LIST_DIR}/qa_engine_pool_test.c")
  set_target_properties(qa_engine_pool_test PROPERTIES
    C_STANDARD 99
    C_STANDARD_REQUIRED ON
  )
  if(UNIX)
    find_package(Threads REQUIRED)
    target_link_libraries(qa_engine_pool_test Threads::Threads m)
  endif()
  if(MSVC)
    target_compile_options(qa_engine_pool_test PRIVATE /utf-8)
  endif()
  enable_testing()
  add_test(NAME qa_engine_pool COMMAND qa_engine_pool_test)
endif()

# Vendored dr_libs emits a few benign conversion warnings. We do not edit
# those files (see third_party/dr_libs/PROVENANCE.md — updates must stay a
# straight overwrite), so the warnings are silenced on THIS translation
# unit only. Our own code keeps every warning it had.
if(MSVC)
  set_source_files_properties(
    "${CMAKE_CURRENT_LIST_DIR}/qa_audio_decode.c"
    "${CMAKE_CURRENT_LIST_DIR}/third_party/zstd/zstd.c"
    PROPERTIES COMPILE_OPTIONS "/wd4267;/wd4244;/wd4996;/wd4018;/wd4389")
else()
  set_source_files_properties(
    "${CMAKE_CURRENT_LIST_DIR}/qa_audio_decode.c"
    "${CMAKE_CURRENT_LIST_DIR}/third_party/zstd/zstd.c"
    PROPERTIES COMPILE_OPTIONS "-Wno-conversion;-Wno-unused-function")
endif()

# The OS threading/dl primitives, and on Apple the frameworks the audio
# decoder links. 🪦The C's sound device (miniaudio) linked CoreAudio here
# and OpenSLES on Android, until the device moved into the GPU engine's
# library (connection-round-checklist H, 2026-11-08).
if(APPLE)
  # AudioToolbox carries the OS audio decoder (qa_audio_decode.c).
  # ↩️AVFoundation, CoreMedia, CoreVideo, CoreGraphics and Foundation
  # carried the movie writer and reader (`qa_video_apple.m`), which went to
  # the Rust engine in the connection round (connection-round-checklist H,
  # 2026-11-08).
  target_link_libraries(qa_engine
    "-framework CoreFoundation" "-framework AudioToolbox")
elseif(UNIX AND NOT ANDROID)
  find_package(Threads REQUIRED)
  target_link_libraries(qa_engine Threads::Threads ${CMAKE_DL_LIBS})
elseif(ANDROID)
  # mediandk: the NDK media stack — the OS audio decoder (AAC); ↩️the movie
  # decoder and encoder too, until the connection round moved them to the
  # Rust engine.
  # ↩️mediandk was resolved via dlopen/dlsym at runtime until 2026-10-24,
  # when the minSdk 29 floor left the headers nothing to hide (qa_ndk_media.h).
  target_link_libraries(qa_engine mediandk)
elseif(WIN32)
  # The OS decoder (AAC/m4a; ↩️and every movie, until the connection round):
  # Media Foundation source readers over the span stream
  # (qa_win_range_stream.c). ole32 carries the COM runtime. 🪦shlwapi went
  # with the in-memory audio origin it served (SHCreateMemStream,
  # 2026-09-24).
  target_link_libraries(qa_engine mfplat mfreadwrite mfuuid ole32)
endif()

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
  find_library(QA_M_LIB m)
  if(QA_M_LIB)
    target_link_libraries(qa_engine ${QA_M_LIB})
  endif()
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
