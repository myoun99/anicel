cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "gpu_engine")
project(${PROJECT_NAME} LANGUAGES CXX)

cmake_policy(VERSION 3.14...3.25)

# The texture shim only: it keeps the registrar Flutter hands a plugin and
# registers the engine's shared handles as external textures. The engine
# itself is Rust, built by hook/build.dart.
set(PLUGIN_NAME "gpu_engine_plugin")

add_library(${PLUGIN_NAME} SHARED
  "include/gpu_engine/gpu_engine_plugin_c_api.h"
  "gpu_engine_plugin_c_api.cpp"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter d3d11.lib dxgi.lib)

set(gpu_engine_bundled_libraries
  ""
  PARENT_SCOPE
)
