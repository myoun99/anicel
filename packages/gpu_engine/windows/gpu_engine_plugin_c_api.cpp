#include "include/gpu_engine/gpu_engine_plugin_c_api.h"

#include <d3d11_1.h>
#include <dxgi.h>
#include <flutter_texture_registrar.h>
#include <flutter_windows.h>
#include <wrl/client.h>

#include <atomic>
#include <map>
#include <memory>
#include <mutex>

namespace {

using Microsoft::WRL::ComPtr;

FlutterDesktopTextureRegistrarRef g_textures = nullptr;
ComPtr<IDXGIAdapter> g_adapter;

// One registered texture. A slot's descriptor never changes after
// registration, so the raster thread reading slots[shown] races with
// nothing; only |shown| moves, atomically. Switching slots is what makes
// Flutter reopen the handle (external_texture_d3d.cc, handle !=
// last_surface_handle_) -- a cost the measurement weighs.
struct SharedTexture {
  FlutterDesktopGpuSurfaceDescriptor slots[2] = {};
  std::atomic<int32_t> shown{0};
};

std::mutex g_lock;
std::map<int64_t, std::unique_ptr<SharedTexture>> g_registered;

const FlutterDesktopGpuSurfaceDescriptor* Descriptor(size_t /*width*/,
                                                     size_t /*height*/,
                                                     void* user_data) {
  auto* texture = static_cast<SharedTexture*>(user_data);
  return &texture->slots[texture->shown.load()];
}

FlutterDesktopGpuSurfaceDescriptor MakeDescriptor(void* handle,
                                                  uint32_t width,
                                                  uint32_t height,
                                                  bool bgra) {
  FlutterDesktopGpuSurfaceDescriptor descriptor = {};
  descriptor.struct_size = sizeof(descriptor);
  descriptor.handle = handle;
  descriptor.width = width;
  descriptor.height = height;
  descriptor.visible_width = width;
  descriptor.visible_height = height;
  descriptor.format = bgra ? kFlutterDesktopPixelFormatBGRA8888
                           : kFlutterDesktopPixelFormatRGBA8888;
  return descriptor;
}

SharedTexture* Find(int64_t texture_id) {
  std::lock_guard<std::mutex> lock(g_lock);
  auto it = g_registered.find(texture_id);
  return it == g_registered.end() ? nullptr : it->second.get();
}

}  // namespace

void GpuEnginePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  g_textures = FlutterDesktopRegistrarGetTextureRegistrar(registrar);
  IDXGIAdapter* adapter = nullptr;
  if (FlutterDesktopPluginRegistrarGetGraphicsAdapter(registrar, &adapter)) {
    g_adapter.Attach(adapter);
  }
}

uint64_t gpu_engine_flutter_adapter_luid(void) {
  DXGI_ADAPTER_DESC desc = {};
  if (!g_adapter || FAILED(g_adapter->GetDesc(&desc))) {
    return 0;
  }
  return (static_cast<uint64_t>(
              static_cast<uint32_t>(desc.AdapterLuid.HighPart))
          << 32) |
         desc.AdapterLuid.LowPart;
}

int64_t gpu_engine_texture_register(void* front,
                                    void* back,
                                    uint32_t width,
                                    uint32_t height,
                                    bool bgra) {
  if (g_textures == nullptr || front == nullptr) {
    return -1;
  }
  auto texture = std::make_unique<SharedTexture>();
  texture->slots[0] = MakeDescriptor(front, width, height, bgra);
  texture->slots[1] =
      MakeDescriptor(back != nullptr ? back : front, width, height, bgra);
  FlutterDesktopTextureInfo info = {};
  info.type = kFlutterDesktopGpuSurfaceTexture;
  info.gpu_surface_config.struct_size =
      sizeof(FlutterDesktopGpuSurfaceTextureConfig);
  info.gpu_surface_config.type = kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle;
  info.gpu_surface_config.callback = Descriptor;
  info.gpu_surface_config.user_data = texture.get();
  const int64_t texture_id =
      FlutterDesktopTextureRegistrarRegisterExternalTexture(g_textures, &info);
  if (texture_id < 0) {
    return -1;
  }
  std::lock_guard<std::mutex> lock(g_lock);
  g_registered[texture_id] = std::move(texture);
  return texture_id;
}

bool gpu_engine_texture_show(int64_t texture_id, int32_t slot) {
  SharedTexture* texture = Find(texture_id);
  if (texture == nullptr) {
    return false;
  }
  texture->shown.store(slot == 1 ? 1 : 0);
  return FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable(
      g_textures, texture_id);
}

void gpu_engine_texture_unregister(int64_t texture_id) {
  std::unique_ptr<SharedTexture> texture;
  {
    std::lock_guard<std::mutex> lock(g_lock);
    auto it = g_registered.find(texture_id);
    if (it == g_registered.end()) {
      return;
    }
    texture = std::move(it->second);
    g_registered.erase(it);
  }
  // The raster thread may still read the descriptor until Flutter says it
  // is done, so it is freed in the completion callback, not here.
  FlutterDesktopTextureRegistrarUnregisterExternalTexture(
      g_textures, texture_id,
      [](void* user_data) { delete static_cast<SharedTexture*>(user_data); },
      texture.release());
}

bool gpu_engine_inspect_shared(void* handle,
                               uint32_t* format,
                               uint32_t* bind_flags,
                               uint32_t* misc_flags) {
  if (!g_adapter || handle == nullptr) {
    return false;
  }
  ComPtr<ID3D11Device> device;
  if (FAILED(D3D11CreateDevice(g_adapter.Get(), D3D_DRIVER_TYPE_UNKNOWN,
                               nullptr, 0, nullptr, 0, D3D11_SDK_VERSION,
                               &device, nullptr, nullptr))) {
    return false;
  }
  ComPtr<ID3D11Device1> device1;
  ComPtr<ID3D11Texture2D> texture;
  if (FAILED(device.As(&device1)) ||
      FAILED(device1->OpenSharedResource1(static_cast<HANDLE>(handle),
                                          IID_PPV_ARGS(&texture)))) {
    return false;
  }
  D3D11_TEXTURE2D_DESC desc = {};
  texture->GetDesc(&desc);
  *format = static_cast<uint32_t>(desc.Format);
  *bind_flags = desc.BindFlags;
  *misc_flags = desc.MiscFlags;
  return true;
}
