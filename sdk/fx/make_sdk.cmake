# Packs the Anicel fx plugin SDK into the one zip the site offers
# (fx-plugin-sdk-publish: the site's developer page and an SDK zip, no link
# to this repository):
#   cmake -DOUT=<folder> -P sdk/fx/make_sdk.cmake
# writes <folder>/anicel-fx-sdk-<spec>.zip. The header is the app's own
# (packages/qa_native/src/anicel_fx_plugin.h) — the spec the app is built
# against, copied in as it packs, so there is never a second one to drift.
if(NOT OUT)
  message(FATAL_ERROR "OUT is the folder the zip goes to: -DOUT=<folder>")
endif()
set(sdk "${CMAKE_CURRENT_LIST_DIR}")
set(header "${sdk}/../../packages/qa_native/src/anicel_fx_plugin.h")
file(STRINGS "${header}" spec_line REGEX "^#define ANICEL_FX_SPEC_VERSION ")
string(REGEX REPLACE "^#define ANICEL_FX_SPEC_VERSION ([0-9]+)u$" "\\1"
  spec "${spec_line}")
if(NOT spec MATCHES "^[0-9]+$")
  message(FATAL_ERROR "No spec version in ${header}")
endif()

set(name "anicel-fx-sdk-${spec}")
set(stage "${OUT}/${name}")
file(REMOVE_RECURSE "${stage}")
file(COPY "${sdk}/LICENSE" "${sdk}/README.md" DESTINATION "${stage}")
file(COPY "${header}" DESTINATION "${stage}/include")
file(COPY "${sdk}/example/CMakeLists.txt" "${sdk}/example/shadow.c"
  DESTINATION "${stage}/example")
file(REMOVE "${OUT}/${name}.zip")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E tar cf "${name}.zip" --format=zip "${name}"
  WORKING_DIRECTORY "${OUT}" RESULT_VARIABLE code)
if(NOT code EQUAL 0)
  message(FATAL_ERROR "The zip did not pack (${code})")
endif()
file(REMOVE_RECURSE "${stage}")
message("${OUT}/${name}.zip")
