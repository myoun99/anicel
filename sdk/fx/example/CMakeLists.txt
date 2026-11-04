# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PARK GUNWOO -- the Anicel fx plugin SDK's LICENSE.
#
# Builds the example plugin as a WebAssembly module and as a native library
# of this machine, and packs both into shadow.anifx -- the file a person opens
# in Anicel. README.md says what each step is.
#
#   cmake -S . -B build -DANICEL_FX_CLANG=<a clang with the wasm32 target>
#   cmake --build build --config Release
cmake_minimum_required(VERSION 3.20)

# One macos.dylib serves both Mac chips.
if(CMAKE_HOST_APPLE AND NOT DEFINED CMAKE_OSX_ARCHITECTURES)
  set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64" CACHE STRING "")
endif()

project(anicel_fx_example C)

set(ANICEL_FX_INCLUDE "${CMAKE_CURRENT_LIST_DIR}/../include"
  CACHE PATH "The folder of anicel_fx_plugin.h")
find_program(ANICEL_FX_CLANG clang
  DOC "A clang with the wasm32 target, wasm-ld beside it")
set(ANICEL_FX_WASI_SYSROOT "" CACHE PATH
  "WASI SDK's sysroot, to build the module with the C library")
option(ANICEL_FX_NATIVE "Also build this machine's native library" ON)

set(plugin shadow)
set(source "${CMAKE_CURRENT_LIST_DIR}/${plugin}.c")

if(NOT ANICEL_FX_CLANG)
  message(FATAL_ERROR "No clang found: pass -DANICEL_FX_CLANG=<path> -- "
    "one with the wasm32 target (LLVM's, WASI SDK's; Apple's has none)")
endif()

# The module, which every device runs. Without a C library it starts with
# nothing to run first (--no-entry); with WASI SDK's it is a reactor, whose
# C library the host starts before asking it anything.
if(ANICEL_FX_WASI_SYSROOT)
  set(wasm_flags --target=wasm32-wasip1 "--sysroot=${ANICEL_FX_WASI_SYSROOT}"
    -mexec-model=reactor)
else()
  set(wasm_flags --target=wasm32 -nostdlib -Wl,--no-entry)
endif()
add_custom_command(OUTPUT plugin.wasm
  COMMAND "${ANICEL_FX_CLANG}" ${wasm_flags} -O2 -mbulk-memory
    "-I${ANICEL_FX_INCLUDE}" -Wl,--strip-all -o plugin.wasm "${source}"
  DEPENDS "${source}" "${ANICEL_FX_INCLUDE}/anicel_fx_plugin.h"
  VERBATIM)
set(packed plugin.wasm)

# The native build, named as the app looks for it in the file.
if(ANICEL_FX_NATIVE)
  if(WIN32 AND CMAKE_C_COMPILER_ARCHITECTURE_ID STREQUAL "ARM64")
    set(native_name windows-arm64)
  elseif(WIN32)
    set(native_name windows-x64)
  elseif(APPLE)
    set(native_name macos)
  elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$")
    set(native_name linux-arm64)
  else()
    set(native_name linux-x64)
  endif()
  add_library(native SHARED "${source}")
  target_include_directories(native PRIVATE "${ANICEL_FX_INCLUDE}")
  set_target_properties(native PROPERTIES
    OUTPUT_NAME ${native_name} PREFIX "" C_VISIBILITY_PRESET hidden)
  list(APPEND packed native)
  set(copy_native
    COMMAND "${CMAKE_COMMAND}" -E copy "$<TARGET_FILE:native>" pack/native/)
endif()

# The file: a zip of plugin.wasm and native/<name>.
add_custom_command(OUTPUT ${plugin}.anifx
  COMMAND "${CMAKE_COMMAND}" -E rm -rf pack
  COMMAND "${CMAKE_COMMAND}" -E make_directory pack/native
  COMMAND "${CMAKE_COMMAND}" -E copy plugin.wasm pack/
  ${copy_native}
  COMMAND "${CMAKE_COMMAND}" -E chdir pack
    "${CMAKE_COMMAND}" -E tar cf ../${plugin}.anifx --format=zip plugin.wasm native
  DEPENDS ${packed}
  VERBATIM)
add_custom_target(anifx ALL DEPENDS ${plugin}.anifx)
