# What a pod reads of wasmtime.cmake (macos/ and ios/qa_native.podspec take
# its stdout as the answer): exactly two lines, the engine's folder and then
# its library inside it — and for a target with none, a failure with nothing
# on stdout. Asked of this machine's own target, as ctest runs it:
#   cmake -DQA_WASMTIME_TARGET=<target> -P wasmtime_script_test.cmake
set(script "${CMAKE_CURRENT_LIST_DIR}/wasmtime.cmake")

execute_process(
  COMMAND "${CMAKE_COMMAND}" "-DQA_WASMTIME_TARGET=${QA_WASMTIME_TARGET}"
    -P "${script}"
  OUTPUT_VARIABLE out ERROR_VARIABLE err RESULT_VARIABLE code)
if(NOT code EQUAL 0)
  message(FATAL_ERROR "the script failed for ${QA_WASMTIME_TARGET}:\n${err}")
endif()
string(REGEX MATCHALL "[^\n]+" lines "${out}")
list(LENGTH lines count)
if(NOT count EQUAL 2)
  message(FATAL_ERROR "the script printed ${count} lines, not 2:\n${out}")
endif()
list(GET lines 0 folder)
list(GET lines 1 library)
if(NOT IS_DIRECTORY "${folder}/include")
  message(FATAL_ERROR "the first line is no engine's folder: ${folder}")
endif()
string(FIND "${library}" "${folder}/lib/" at)
if(NOT at EQUAL 0 OR NOT EXISTS "${library}")
  message(FATAL_ERROR "the second line is no library in ${folder}: ${library}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" -DQA_WASMTIME_TARGET=no-such-target -P "${script}"
  OUTPUT_VARIABLE out ERROR_VARIABLE err RESULT_VARIABLE code)
if(code EQUAL 0 OR NOT out STREQUAL "")
  message(FATAL_ERROR
    "an unknown target answered ${code} with stdout '${out}'")
endif()
message("wasmtime.cmake answers ${QA_WASMTIME_TARGET} as a pod reads it")
