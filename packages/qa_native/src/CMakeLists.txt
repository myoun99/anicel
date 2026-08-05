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
# R7) — Media Foundation / AVAssetWriter / NDK MediaCodec.
add_library(qa_engine SHARED
  "${CMAKE_CURRENT_LIST_DIR}/qa_engine.c"
  "${CMAKE_CURRENT_LIST_DIR}/qa_audio_decode.c"
  "${CMAKE_CURRENT_LIST_DIR}/qa_audio_denoise.c"
  "${CMAKE_CURRENT_LIST_DIR}/qa_audio_device.c"
  "${CMAKE_CURRENT_LIST_DIR}/qa_video_encode.c"
  "${CMAKE_CURRENT_LIST_DIR}/qa_image_encode.c"
)
if(APPLE)
  target_sources(qa_engine PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/qa_video_apple.m")
endif()

set_target_properties(qa_engine PROPERTIES
  C_STANDARD 99
  C_STANDARD_REQUIRED ON
)

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
    PROPERTIES COMPILE_OPTIONS "/wd4267;/wd4244;/wd4996;/wd4018;/wd4389")
else()
  set_source_files_properties(
    "${CMAKE_CURRENT_LIST_DIR}/qa_audio_decode.c"
    "${CMAKE_CURRENT_LIST_DIR}/qa_audio_denoise.c"
    "${CMAKE_CURRENT_LIST_DIR}/qa_audio_device.c"
    "${CMAKE_CURRENT_LIST_DIR}/qa_image_encode.c"
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
