cmake_minimum_required(VERSION 3.13)

set(PROJECT_NAME "gpu_engine")
project(${PROJECT_NAME} LANGUAGES CXX)

# The texture shim only: it keeps the registrar Flutter hands a plugin and
# shows the engine's dma-bufs as GL textures. The engine itself is Rust,
# built by hook/build.dart.
set(PLUGIN_NAME "gpu_engine_plugin")

add_library(${PLUGIN_NAME} SHARED
  "gpu_engine_plugin.cc"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
# EGL and GL through libepoxy, as Flutter's own Linux embedder calls them
# (fl_egl_image.cc), so both resolve against the context it made.
find_package(PkgConfig REQUIRED)
pkg_check_modules(EPOXY REQUIRED IMPORTED_TARGET epoxy)
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter PkgConfig::GTK
  PkgConfig::EPOXY)

set(gpu_engine_bundled_libraries
  ""
  PARENT_SCOPE
)
