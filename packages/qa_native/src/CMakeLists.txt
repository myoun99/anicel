# The native core's ONE build description, shared by every consumer:
# the plugin's per-platform build files include this (Windows included —
# the 2A migration is complete), and CI builds it standalone for the
# parity suites.
#
# Nothing platform-specific lives here except the compiler flags, because
# qa_engine.c is one portable C99 source by design.
# 3.16 for OBJC language support — the Apple video writer (AUDIO-PRO R7)
# is Objective-C because AVAssetWriter is.
cmake_minimum_required(VERSION 3.16)
project(qa_engine LANGUAGES C)

if(APPLE)
  enable_language(OBJC)
endif()

# qa_audio_decode.c is a second translation unit rather than more of
# qa_engine.c: it pulls in ~27k lines of vendored dr_libs, and compiling
# that alongside the hot loops would slow every build and mix third-party
# warnings into ours. qa_video_encode.c is per-OS encoder glue (AUDIO-PRO
# R7) — Media Foundation / AVAssetWriter / NDK MediaCodec. qa_video_decode.c is its
# mirror: the Source Reader half, so a movie can answer "the picture at
# frame N" the way every other source already does.
add_library(qa_engine SHARED
  "${CMAKE_CURRENT_LIST_DIR}/qa_engine.c"
  "${CMAKE_CURRENT_LIST_DIR}/qa_audio_decode.c"
  "${CMAKE_CURRENT_LIST_DIR}/qa_audio_denoise.c"
  "${CMAKE_CURRENT_LIST_DIR}/qa_audio_device.c"
  "${CMAKE_CURRENT_LIST_DIR}/qa_video_encode.c"
  "${CMAKE_CURRENT_LIST_DIR}/qa_video_decode.c"
  "${CMAKE_CURRENT_LIST_DIR}/qa_image_encode.c"
  "${CMAKE_CURRENT_LIST_DIR}/qa_compress.c"
  "${CMAKE_CURRENT_LIST_DIR}/third_party/zstd/zstd.c"
)
if(APPLE)
  target_sources(qa_engine PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/qa_video_apple.m")
  # 🚨ARC, as the pod compiles it. CocoaPods turns ARC on by default and this
  # file is written for it: it keeps AVFoundation objects in globals with no
  # retain. Built here without the flag, `g_decode_asset` held an autoreleased
  # asset that was freed when the open's pool drained, and the next reader
  # built on it crashed inside -[AVAssetReader initWithAsset:] — the tests on
  # a Mac died of a segmentation fault the app on the iPad never had
  # (Codemagic, 2026-09-11). The file refuses to compile without ARC, so the
  # two builds cannot drift apart again.
  set_source_files_properties(
    "${CMAKE_CURRENT_LIST_DIR}/qa_video_apple.m"
    PROPERTIES COMPILE_OPTIONS "-fobjc-arc")
endif()
# ⛔WIN32 only, for the same reason the Apple source above is: an
# `IMFByteStream` over a range is Media Foundation's problem and nobody
# else's, and a translation unit that compiles to nothing elsewhere is a
# warning waiting to happen.
if(WIN32)
  target_sources(qa_engine PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/qa_win_range_stream.c")
endif()
# ⛔ANDROID only, for the same reason: the NDK media table is libmediandk's
# answer and nobody else's (see qa_ndk_media.h for why there is one of it).
if(ANDROID)
  target_sources(qa_engine PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/qa_ndk_media.c")
endif()

set_target_properties(qa_engine PROPERTIES
  C_STANDARD 99
  C_STANDARD_REQUIRED ON
)

# 🚨★★★**THE FIRST NATIVE CODE CI ACTUALLY RUNS.**
#
# The portability job built this library with two compilers and then printed
# a directory listing — a real check for「does it compile everywhere」and no
# check at all for「is the arithmetic right」. That was not laziness: until
# the decode law was lifted out of the per-OS `#if` blocks, there was nothing
# a Linux runner could execute. Now there is, and the rules it covers are
# exactly the ones the three decoders had disagreed about.
#
# ⚠️Built only where the target is the host, because it is meant to be RUN.
# ⛔Not linked against qa_engine: the law is `static`, and the test includes
# the translation unit instead — see the file's own header.
if(NOT ANDROID AND NOT IOS)
  add_executable(qa_video_decode_law_test
    "${CMAKE_CURRENT_LIST_DIR}/qa_video_decode_law_test.c")
  set_target_properties(qa_video_decode_law_test PROPERTIES
    C_STANDARD 99
    C_STANDARD_REQUIRED ON
  )
  # ⛔NO PLATFORM UNDER IT. The first try let the host's backend come along
  # and paid for it per host — Media Foundation libraries on Windows, and on
  # Apple a link failure, because that backend lives in a `.m` this target
  # does not compile. The law is the same everywhere; the test that proves
  # it compiles the same everywhere.
  target_compile_definitions(qa_video_decode_law_test
    PRIVATE QA_DECODE_LAW_ONLY=1)
  # /utf-8 for the same reason qa_engine has it: these sources carry Korean
  # comments, and without it MSVC reads them in the machine's code page and
  # floods C4819 on every Japanese or Korean Windows build.
  if(MSVC)
    target_compile_options(qa_video_decode_law_test PRIVATE /utf-8)
  endif()
  enable_testing()
  add_test(NAME qa_video_decode_law COMMAND qa_video_decode_law_test)
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
    "${CMAKE_CURRENT_LIST_DIR}/qa_audio_decode.c")
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
    # The Windows range origin hands Media Foundation the video decoder's
    # byte stream, so the test needs that translation unit too.
    target_sources(qa_audio_range_test PRIVATE
      "${CMAKE_CURRENT_LIST_DIR}/qa_win_range_stream.c")
    target_link_libraries(qa_audio_range_test
      mfplat mfreadwrite mfuuid shlwapi ole32)
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
    "${CMAKE_CURRENT_LIST_DIR}/qa_win_range_stream.c")
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

# The pen sidecars (pen program) — Windows only, one DLL:
#   qa_tablet_win.c  PEN-2, talks to the tablet driver through wintab32.dll
#   qa_penraw_win.c  reads the HID digitizer report through Raw Input
# Both load their system DLL dynamically at runtime, so building needs no
# vendor SDK and no extra link libraries, and absence of a driver is a
# normal silent state. Same bundle-beside-the-exe + dart:ffi consumption
# pattern as qa_engine.
if(WIN32)
  add_library(qa_tablet SHARED
    "${CMAKE_CURRENT_LIST_DIR}/qa_tablet_win.c"
    "${CMAKE_CURRENT_LIST_DIR}/qa_penraw_win.c")
  set_target_properties(qa_tablet PROPERTIES
    C_STANDARD 99
    C_STANDARD_REQUIRED ON
  )
  if(MSVC)
    # Same UTF-8 sources, same C4819 story as qa_engine below.
    target_compile_options(qa_tablet PRIVATE /utf-8)
  endif()
endif()

# Vendored dr_libs emits a few benign conversion warnings. We do not edit
# those files (see third_party/dr_libs/PROVENANCE.md — updates must stay a
# straight overwrite), so the warnings are silenced on THIS translation
# unit only. Our own code keeps every warning it had.
if(MSVC)
  set_source_files_properties(
    "${CMAKE_CURRENT_LIST_DIR}/qa_audio_decode.c"
    "${CMAKE_CURRENT_LIST_DIR}/qa_audio_denoise.c"
    "${CMAKE_CURRENT_LIST_DIR}/qa_audio_device.c"
    "${CMAKE_CURRENT_LIST_DIR}/qa_image_encode.c"
  "${CMAKE_CURRENT_LIST_DIR}/qa_compress.c"
  "${CMAKE_CURRENT_LIST_DIR}/third_party/zstd/zstd.c"
    PROPERTIES COMPILE_OPTIONS "/wd4267;/wd4244;/wd4996;/wd4018;/wd4389")
  # rnnoise, compiled inside qa_audio_denoise.c, does its float arithmetic
  # with double literals: C4305, truncation it means, in files kept verbatim.
  # The clang/gcc branch below already drops it with -Wno-conversion.
  set_property(SOURCE "${CMAKE_CURRENT_LIST_DIR}/qa_audio_denoise.c"
    APPEND PROPERTY COMPILE_OPTIONS "/wd4305")
else()
  set_source_files_properties(
    "${CMAKE_CURRENT_LIST_DIR}/qa_audio_decode.c"
    "${CMAKE_CURRENT_LIST_DIR}/qa_audio_denoise.c"
    "${CMAKE_CURRENT_LIST_DIR}/qa_audio_device.c"
    "${CMAKE_CURRENT_LIST_DIR}/qa_image_encode.c"
  "${CMAKE_CURRENT_LIST_DIR}/qa_compress.c"
  "${CMAKE_CURRENT_LIST_DIR}/third_party/zstd/zstd.c"
    PROPERTIES COMPILE_OPTIONS "-Wno-conversion;-Wno-unused-function")
endif()

# miniaudio dlopens the platform audio APIs at runtime, so building needs
# no audio dev headers — that is what keeps CI's Linux job from needing an
# ALSA package. It does need the OS threading/dl primitives, and on Apple
# the CoreAudio frameworks at LINK time.
if(APPLE)
  # AVFoundation/CoreMedia/CoreVideo carry the video writer (R7);
  # Foundation is the Objective-C runtime half of it (NSString and
  # friends) — CoreFoundation alone does NOT provide those classes.
  target_link_libraries(qa_engine
    "-framework CoreFoundation" "-framework CoreAudio" "-framework AudioToolbox"
    "-framework AVFoundation" "-framework CoreMedia" "-framework CoreVideo"
    # CoreGraphics arrived with the DECODER: a CGImage from the image
    # generator is drawn into a bitmap context to come out as RGBA.
    "-framework CoreGraphics"
    "-framework Foundation")
elseif(UNIX AND NOT ANDROID)
  find_package(Threads REQUIRED)
  target_link_libraries(qa_engine Threads::Threads ${CMAKE_DL_LIBS})
elseif(ANDROID)
  # The NDK media stack (AAC decode) resolves via dlopen/dlsym at runtime,
  # so only OpenSLES (miniaudio) links here.
  target_link_libraries(qa_engine OpenSLES)
elseif(WIN32)
  # The OS decoder (AAC/m4a): Media Foundation source reader over an
  # in-memory stream. shlwapi carries SHCreateMemStream, ole32 the COM
  # runtime.
  target_link_libraries(qa_engine mfplat mfreadwrite mfuuid shlwapi ole32)
endif()

if(MSVC)
  # The engine must run OPTIMIZED even inside the app's Debug build (the
  # project's performance bar is debug mode). MSVC's Debug defaults
  # (/RTC1 /Od) conflict with /O2 - strip them for this directory only.
  string(REPLACE "/RTC1" "" CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG}")
  string(REPLACE "/Od" "" CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG}")
  string(REPLACE "/Ob0" "" CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG}")
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
