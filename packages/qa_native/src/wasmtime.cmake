# 🗣️I-132-Q31 (유저 2026-10-30): the fx plugins' WebAssembly engine is
# Wasmtime 48 LTS — its project's own prebuilt C library, pinned by version
# and SHA-256 and fetched ONCE PER MACHINE into a folder outside the
# repository (28 MB zipped; a binary in git stays in every clone for ever).
# Linked statically: 12.9 MB in an executable on Windows x64, where its DLL
# is 22 MB (measured 2026-10-30).
# 🗣️fx-plugin-sdk-publish-Q2 (유저 2026-11-04): 「애초에 모든플랫폼 플러그인
# 대응하게 하고, 그 다음 sdk만들고 공개」 — the prebuilt library on every
# platform its project publishes one for: Windows x64 · ARM64, macOS and
# Linux x86_64 · arm64, Android arm64 · x86_64.
# ⚠️iOS has none: an iPad makes no code as it runs, so its library is built
# here from the project's own source, to interpret (Pulley, qa_fx_plugin.c).
# 🗣️fx-plugin-sdk-publish-Q5 (유저 2026-11-04): 「웹뷰자체가 사본이란
# 느낌드니까. 다른 구현방식이란게」 — the same engine and host as everywhere
# else, not WebKit's WebAssembly beside them.
#
# Two kinds of reader: this core's CMakeLists.txt includes it, and the Apple
# apps' pods run it as a script for each library they link — CocoaPods
# builds those apps, not this CMake (macos/ and ios/qa_native.podspec).
set(QA_WASMTIME_VERSION "48.0.8")

# Sets [dir_var] to the folder of Wasmtime's C API for [target] — its
# project's own name for one, as aarch64-macos — and [library_var] to the
# library in it, fetching it once per machine; both empty for a target there
# is none for.
function(qa_wasmtime_fetch target dir_var library_var)
  set(${dir_var} "" PARENT_SCOPE)
  set(${library_var} "" PARENT_SCOPE)
  set(name "wasmtime-v${QA_WASMTIME_VERSION}-${target}-c-api")
  set(library "libwasmtime.a")
  set(archive "${name}.tar.xz")
  set(rust_target "")
  if(target STREQUAL "x86_64-windows")
    set(sha256 "31c2d97399b2555c06233a5fe0d2ba7373d020dae584107b1e3f459dd1756c42")
  elseif(target STREQUAL "aarch64-windows")
    set(sha256 "2dd5ec2f86b9d50da93e4f29985472c0520ee3545e5ab9e8771430f39011c269")
  elseif(target STREQUAL "aarch64-macos")
    set(sha256 "2c7c4e75ca41f505867ef7c836c942c6b1190f708939753d10d1927585eaed59")
  elseif(target STREQUAL "x86_64-macos")
    set(sha256 "07dc84f84debc1cca9f79c5b75200799296bb53d83f2e9d0e8dc83fe05245a63")
  elseif(target STREQUAL "aarch64-linux")
    set(sha256 "3bb7d77fcbf0da214b7d56fc1f244e77b6dbb51b740c63ff7cbd8ece398308dc")
  elseif(target STREQUAL "x86_64-linux")
    set(sha256 "6cd2e5a976d68932afb546c2d14d89ba9e5578127a9716a13500dde40fc1e0e6")
  elseif(target STREQUAL "aarch64-android")
    set(sha256 "0954e8b9e1b05461645821621464aef94b60a1b148e0cc0cb00ddaaf3353c0f9")
  elseif(target STREQUAL "x86_64-android")
    set(sha256 "ddeb32ac16c43cba8a9c104c44912a7bce76e95731e6b0b6cf43570ae363a6e4")
  elseif(target STREQUAL "aarch64-ios")
    set(rust_target "aarch64-apple-ios")
  elseif(target STREQUAL "aarch64-ios-sim")
    set(rust_target "aarch64-apple-ios-sim")
  else()
    return()
  endif()
  if(target MATCHES "-windows$")
    set(archive "${name}.zip")
    set(library "wasmtime.lib")
  endif()
  if(rust_target)
    # The project's source with every crate it needs, as it publishes it.
    set(archive "wasmtime-v${QA_WASMTIME_VERSION}-src.tar.gz")
    set(sha256 "fb04995afe5e938322b8f848a3e5614360301dbe31b14df5d4b705dd26ee7bef")
  endif()
  # The HOST's folder for things fetched once per machine.
  if(CMAKE_HOST_WIN32)
    file(TO_CMAKE_PATH "$ENV{LOCALAPPDATA}" home)
  elseif(DEFINED ENV{XDG_CACHE_HOME})
    set(home "$ENV{XDG_CACHE_HOME}")
  else()
    set(home "$ENV{HOME}/.cache")
  endif()
  set(cache "${home}/anicel/third_party/wasmtime-v${QA_WASMTIME_VERSION}")
  set(archive_path "${cache}/${archive}")
  set(sum "")
  if(EXISTS "${archive_path}")
    file(SHA256 "${archive_path}" sum)
  endif()
  if(NOT sum STREQUAL sha256)
    file(DOWNLOAD
      "https://github.com/bytecodealliance/wasmtime/releases/download/v${QA_WASMTIME_VERSION}/${archive}"
      "${archive_path}"
      EXPECTED_HASH SHA256=${sha256}
      STATUS status)
    list(GET status 0 code)
    if(NOT code EQUAL 0)
      message(FATAL_ERROR "Wasmtime ${QA_WASMTIME_VERSION} did not download: ${status}")
    endif()
    # ⛔Only this one's: a machine that builds for two targets keeps both.
    file(REMOVE_RECURSE "${cache}/x/${name}")
  endif()
  if(NOT EXISTS "${cache}/x/${name}/lib/${library}")
    if(rust_target)
      qa_wasmtime_build("${cache}" "${archive_path}" "${rust_target}"
        "${cache}/x/${name}")
    else()
      file(ARCHIVE_EXTRACT INPUT "${archive_path}" DESTINATION "${cache}/x")
    endif()
  endif()
  set(${dir_var} "${cache}/x/${name}" PARENT_SCOPE)
  set(${library_var} "${cache}/x/${name}/lib/${library}" PARENT_SCOPE)
endfunction()

# Builds the C API for [rust_target] from the project's source [archive] into
# [prefix], by the project's own CMake (crates/c-api) — Rust's and Xcode's
# tools, so a Mac. Only what this host asks of the engine (qa_fx_plugin.c):
# WASI with nothing behind it, and Cranelift writing Pulley's bytecode for
# the interpreter — fewer crates on a target the project names Tier 3, and a
# smaller app.
function(qa_wasmtime_build cache archive rust_target prefix)
  set(source "${cache}/x/wasmtime-v${QA_WASMTIME_VERSION}-src")
  if(NOT EXISTS "${source}/crates/c-api/CMakeLists.txt")
    file(ARCHIVE_EXTRACT INPUT "${archive}" DESTINATION "${cache}/x")
  endif()
  set(build "${cache}/build/${rust_target}")
  file(MAKE_DIRECTORY "${cache}/build")
  qa_wasmtime_step("${build}.log" rustup target add ${rust_target})
  qa_wasmtime_step("${build}.log" "${CMAKE_COMMAND}"
    -S "${source}/crates/c-api" -B "${build}"
    -DCMAKE_BUILD_TYPE=Release
    -DWASMTIME_TARGET=${rust_target}
    -DWASMTIME_DISABLE_ALL_FEATURES=ON
    -DWASMTIME_FEATURE_WASI=ON
    -DWASMTIME_FEATURE_CRANELIFT=ON
    -DWASMTIME_FEATURE_PULLEY=ON
    "-DCMAKE_INSTALL_PREFIX=${prefix}")
  qa_wasmtime_step("${build}.log" "${CMAKE_COMMAND}"
    --build "${build}" --config Release --target install)
endfunction()

# Runs one step of that build with its words in [log], not on stdout — the
# script's two lines are a pod's answer. A failure ends with the log's end.
function(qa_wasmtime_step log)
  execute_process(COMMAND ${ARGN}
    OUTPUT_FILE "${log}" ERROR_FILE "${log}" RESULT_VARIABLE code)
  if(NOT code EQUAL 0)
    file(READ "${log}" said)
    string(LENGTH "${said}" length)
    if(length GREATER 4000)
      math(EXPR from "${length} - 4000")
      string(SUBSTRING "${said}" ${from} -1 said)
    endif()
    list(JOIN ARGN " " step)
    message(FATAL_ERROR "Wasmtime ${QA_WASMTIME_VERSION}: ${step} failed (${code}), its log ${log} ends:\n${said}")
  endif()
endfunction()

# `cmake -DQA_WASMTIME_TARGET=<target> -P wasmtime.cmake` fetches it and
# prints the folder, then the library, a line each — what a pod asks.
if(CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE)
  qa_wasmtime_fetch("${QA_WASMTIME_TARGET}" dir library)
  if(NOT dir)
    message(FATAL_ERROR
      "Wasmtime ${QA_WASMTIME_VERSION} has no C API for '${QA_WASMTIME_TARGET}'")
  endif()
  # message() writes to stderr; echo is the one way out to stdout.
  execute_process(COMMAND "${CMAKE_COMMAND}" -E echo "${dir}")
  execute_process(COMMAND "${CMAKE_COMMAND}" -E echo "${library}")
endif()
