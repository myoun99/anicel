#include "include/gpu_engine/gpu_engine_plugin.h"

#include <epoxy/egl.h>
#include <epoxy/gl.h>
#include <unistd.h>

#include <map>
#include <mutex>
#include <vector>

// The Linux half of the GPU engine's way to the screen
// (gpu-engine-skeleton): the engine's dma-buf, imported into Flutter's EGL
// as the GL texture an FlTextureGL hands over — no copy. Flutter's GL
// context is EGL on X11 and Wayland alike (fl_opengl_manager.cc), current
// on the raster thread while it populates a texture (fl_texture_gl.h).

namespace {

// The plane rust/src/platform/linux.rs describes a surface by (`DmaBuf`,
// #[repr(C)]).
struct DmaBuf {
  int32_t fd;
  uint32_t fourcc;
  uint64_t offset;
  uint64_t stride;
  uint64_t modifier;
};

// A slot's plane holds a descriptor of the plugin's own until the import,
// so the engine may free its surface first; the EGLImage and its GL
// texture are made on the raster thread, on first show.
struct Slot {
  DmaBuf plane;
  EGLImageKHR image;
  GLuint texture;
};

struct Retired {
  EGLDisplay display;
  EGLImageKHR image;
  GLuint texture;
};

// ⚠️An FlTextureGL is told nothing when Flutter stops drawing its GL
// texture — it has no destruction callback (fl_texture_gl.cc leaves it
// null) — and it is unregistered on the platform thread, where Flutter's
// context is not current. So an unregistered texture's GL texture and
// EGLImage are kept here and freed by the next populate of any texture,
// on the raster thread with that context current. That is sound because
// Flutter must no longer show a texture that is unregistered (Dart's
// SharedTexture.unregister); what one leaves waits for the next texture
// Flutter draws.
std::mutex g_retired_lock;
std::vector<Retired> g_retired;

GQuark Domain() { return g_quark_from_static_string("gpu_engine"); }

void FreeRetired() {
  std::vector<Retired> retired;
  {
    std::lock_guard<std::mutex> lock(g_retired_lock);
    retired.swap(g_retired);
  }
  for (const Retired& slot : retired) {
    if (slot.texture != 0) {
      glDeleteTextures(1, &slot.texture);
    }
    if (slot.image != EGL_NO_IMAGE_KHR) {
      eglDestroyImageKHR(slot.display, slot.image);
    }
  }
}

}  // namespace

G_DECLARE_FINAL_TYPE(GpuEngineTexture,
                     gpu_engine_texture,
                     GPU_ENGINE,
                     TEXTURE,
                     FlTextureGL)

// One registered texture: two slots, of which Flutter shows the one
// |shown| names. Only |shown| moves after registration, atomically — as
// the Windows shim's slots do (windows/gpu_engine_plugin_c_api.cpp).
struct _GpuEngineTexture {
  FlTextureGL parent_instance;
  Slot slots[2];
  gint shown;
  uint32_t width;
  uint32_t height;
  EGLDisplay display;
};

G_DEFINE_TYPE(GpuEngineTexture, gpu_engine_texture, fl_texture_gl_get_type())

namespace {

// Makes |slot|'s GL texture from its plane, on Flutter's current EGL.
gboolean Import(GpuEngineTexture* self, Slot* slot, GError** error) {
  EGLDisplay display = eglGetCurrentDisplay();
  if (display == EGL_NO_DISPLAY) {
    g_set_error(error, Domain(), 0, "no EGL display is current");
    return FALSE;
  }
  if (!epoxy_has_egl_extension(display, "EGL_EXT_image_dma_buf_import")) {
    g_set_error(error, Domain(), 0, "EGL imports no dma-buf here");
    return FALSE;
  }
  const DmaBuf& plane = slot->plane;
  std::vector<EGLint> attributes = {
      EGL_WIDTH,
      static_cast<EGLint>(self->width),
      EGL_HEIGHT,
      static_cast<EGLint>(self->height),
      EGL_LINUX_DRM_FOURCC_EXT,
      static_cast<EGLint>(plane.fourcc),
      EGL_DMA_BUF_PLANE0_FD_EXT,
      plane.fd,
      EGL_DMA_BUF_PLANE0_OFFSET_EXT,
      static_cast<EGLint>(plane.offset),
      EGL_DMA_BUF_PLANE0_PITCH_EXT,
      static_cast<EGLint>(plane.stride),
  };
  // The engine's plane is LINEAR, which every importer takes; it is named
  // where EGL lets a modifier be named.
  if (epoxy_has_egl_extension(display,
                              "EGL_EXT_image_dma_buf_import_modifiers")) {
    attributes.insert(attributes.end(),
                      {
                          EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT,
                          static_cast<EGLint>(plane.modifier & 0xffffffff),
                          EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT,
                          static_cast<EGLint>(plane.modifier >> 32),
                      });
  }
  attributes.push_back(EGL_NONE);
  EGLImageKHR image =
      eglCreateImageKHR(display, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT,
                        nullptr, attributes.data());
  if (image == EGL_NO_IMAGE_KHR) {
    g_set_error(error, Domain(), 0, "eglCreateImageKHR: 0x%x", eglGetError());
    return FALSE;
  }
  GLuint texture = 0;
  glGenTextures(1, &texture);
  glBindTexture(GL_TEXTURE_2D, texture);
  glEGLImageTargetTexture2DOES(GL_TEXTURE_2D, image);
  // The image holds the buffer; EGL does not take the descriptor
  // (EGL_EXT_image_dma_buf_import), so it is closed here.
  close(slot->plane.fd);
  slot->plane.fd = -1;
  slot->image = image;
  slot->texture = texture;
  self->display = display;
  return TRUE;
}

}  // namespace

static gboolean gpu_engine_texture_populate(FlTextureGL* texture,
                                            uint32_t* target,
                                            uint32_t* name,
                                            uint32_t* width,
                                            uint32_t* height,
                                            GError** error) {
  GpuEngineTexture* self = GPU_ENGINE_TEXTURE(texture);
  FreeRetired();
  Slot* slot = &self->slots[g_atomic_int_get(&self->shown)];
  if (slot->texture == 0 && !Import(self, slot, error)) {
    return FALSE;
  }
  *target = GL_TEXTURE_2D;
  *name = slot->texture;
  *width = self->width;
  *height = self->height;
  return TRUE;
}

static void gpu_engine_texture_dispose(GObject* object) {
  GpuEngineTexture* self = GPU_ENGINE_TEXTURE(object);
  for (Slot& slot : self->slots) {
    if (slot.plane.fd >= 0) {
      close(slot.plane.fd);
      slot.plane.fd = -1;
    }
    if (slot.texture != 0 || slot.image != EGL_NO_IMAGE_KHR) {
      std::lock_guard<std::mutex> lock(g_retired_lock);
      g_retired.push_back({self->display, slot.image, slot.texture});
      slot.image = EGL_NO_IMAGE_KHR;
      slot.texture = 0;
    }
  }
  G_OBJECT_CLASS(gpu_engine_texture_parent_class)->dispose(object);
}

static void gpu_engine_texture_class_init(GpuEngineTextureClass* klass) {
  FL_TEXTURE_GL_CLASS(klass)->populate = gpu_engine_texture_populate;
  G_OBJECT_CLASS(klass)->dispose = gpu_engine_texture_dispose;
}

static void gpu_engine_texture_init(GpuEngineTexture* self) {
  for (Slot& slot : self->slots) {
    slot.plane.fd = -1;
  }
}

namespace {

// Every call below comes on the platform thread, where Dart runs: the
// platform and UI threads are one by default (fl_engine.cc,
// FL_UI_THREAD_POLICY_DEFAULT).
FlTextureRegistrar* g_textures = nullptr;
std::map<int64_t, FlTexture*> g_registered;

// |source|, with a descriptor of the slot's own.
gboolean Take(const DmaBuf* source, Slot* slot) {
  slot->plane = *source;
  slot->plane.fd = dup(source->fd);
  return slot->plane.fd >= 0;
}

}  // namespace

void gpu_engine_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  g_textures = fl_plugin_registrar_get_texture_registrar(registrar);
}

int64_t gpu_engine_texture_register(void* front,
                                    void* back,
                                    uint32_t width,
                                    uint32_t height,
                                    bool /*bgra*/) {
  if (g_textures == nullptr || front == nullptr) {
    return -1;
  }
  GpuEngineTexture* texture = GPU_ENGINE_TEXTURE(
      g_object_new(gpu_engine_texture_get_type(), nullptr));
  texture->width = width;
  texture->height = height;
  const auto* planes = static_cast<const DmaBuf*>(front);
  const auto* back_planes =
      static_cast<const DmaBuf*>(back != nullptr ? back : front);
  if (!Take(planes, &texture->slots[0]) ||
      !Take(back_planes, &texture->slots[1]) ||
      !fl_texture_registrar_register_texture(g_textures,
                                             FL_TEXTURE(texture))) {
    g_object_unref(texture);
    return -1;
  }
  const int64_t texture_id = fl_texture_get_id(FL_TEXTURE(texture));
  g_registered[texture_id] = FL_TEXTURE(texture);
  return texture_id;
}

bool gpu_engine_texture_show(int64_t texture_id, int32_t slot) {
  auto it = g_registered.find(texture_id);
  if (it == g_registered.end()) {
    return false;
  }
  g_atomic_int_set(&GPU_ENGINE_TEXTURE(it->second)->shown, slot == 1 ? 1 : 0);
  return fl_texture_registrar_mark_texture_frame_available(g_textures,
                                                           it->second);
}

void gpu_engine_texture_unregister(int64_t texture_id) {
  auto it = g_registered.find(texture_id);
  if (it == g_registered.end()) {
    return;
  }
  FlTexture* texture = it->second;
  g_registered.erase(it);
  fl_texture_registrar_unregister_texture(g_textures, texture);
  g_object_unref(texture);
}
