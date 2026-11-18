//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <gpu_engine/gpu_engine_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) gpu_engine_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "GpuEnginePlugin");
  gpu_engine_plugin_register_with_registrar(gpu_engine_registrar);
}
