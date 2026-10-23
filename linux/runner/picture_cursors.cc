#include "picture_cursors.h"

#include <cairo.h>
#include <gtk/gtk.h>

#include <cstdint>
#include <cstring>

// UNVERIFIED-ON-DEVICE: authored on the Windows workstation; the Linux
// build is the release workflow's, not every push's.

namespace {

FlMethodChannel* g_cursor_channel = nullptr;

// Every picture made, by name — kept for the life of the window, as the
// engine of Windows keeps the ones it is handed.
GHashTable* g_cursors = nullptr;

// The window the engine wears its own cursors on (fl_view.cc's
// cursor_changed_cb): the view's toplevel. A picture worn anywhere else
// would lie under the engine's.
GdkWindow* window_of(FlView* view) {
  return gtk_widget_get_window(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

FlValue* lookup(FlValue* args, const char* key, FlValueType type) {
  FlValue* value = fl_value_lookup_string(args, key);
  return value != nullptr && fl_value_get_type(value) == type ? value
                                                               : nullptr;
}

// The picture handed over — premultiplied RGBA in the screen's pixels, its
// hot spot in the same, and the screen's pixels a logical one — as a cursor
// at the screen's scale, or null when it is not one.
GdkCursor* cursor_of(FlView* view, FlValue* args) {
  FlValue* buffer = lookup(args, "buffer", FL_VALUE_TYPE_UINT8_LIST);
  FlValue* width_value = lookup(args, "width", FL_VALUE_TYPE_INT);
  FlValue* height_value = lookup(args, "height", FL_VALUE_TYPE_INT);
  FlValue* hot_x = lookup(args, "hotX", FL_VALUE_TYPE_FLOAT);
  FlValue* hot_y = lookup(args, "hotY", FL_VALUE_TYPE_FLOAT);
  FlValue* scale_value = lookup(args, "scale", FL_VALUE_TYPE_FLOAT);
  if (buffer == nullptr || width_value == nullptr || height_value == nullptr ||
      hot_x == nullptr || hot_y == nullptr || scale_value == nullptr) {
    return nullptr;
  }
  const int64_t width = fl_value_get_int(width_value);
  const int64_t height = fl_value_get_int(height_value);
  const double scale = fl_value_get_float(scale_value);
  if (width <= 0 || height <= 0 || scale <= 0 ||
      fl_value_get_length(buffer) !=
          static_cast<size_t>(width * height * 4)) {
    return nullptr;
  }
  cairo_surface_t* surface = cairo_image_surface_create(
      CAIRO_FORMAT_ARGB32, static_cast<int>(width), static_cast<int>(height));
  if (cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS) {
    cairo_surface_destroy(surface);
    return nullptr;
  }
  cairo_surface_flush(surface);
  // Cairo's ARGB32 is premultiplied too, one native-endian word a pixel
  // with alpha at the top — so each RGBA quad is packed into one.
  const uint8_t* rgba = fl_value_get_uint8_list(buffer);
  uint8_t* rows = cairo_image_surface_get_data(surface);
  const int stride = cairo_image_surface_get_stride(surface);
  for (int64_t y = 0; y < height; y++) {
    for (int64_t x = 0; x < width; x++) {
      const uint8_t* in = rgba + (y * width + x) * 4;
      const uint32_t argb = static_cast<uint32_t>(in[3]) << 24 |
                            static_cast<uint32_t>(in[0]) << 16 |
                            static_cast<uint32_t>(in[1]) << 8 |
                            static_cast<uint32_t>(in[2]);
      std::memcpy(rows + y * stride + x * 4, &argb, sizeof argb);
    }
  }
  cairo_surface_mark_dirty(surface);
  // The surface is in the screen's pixels: said so, it is worn at the
  // logical size, its hot spot in the same logical units.
  cairo_surface_set_device_scale(surface, scale, scale);
  GdkWindow* window = window_of(view);
  GdkDisplay* display = window != nullptr ? gdk_window_get_display(window)
                                          : gdk_display_get_default();
  GdkCursor* cursor = gdk_cursor_new_from_surface(
      display, surface, fl_value_get_float(hot_x) / scale,
      fl_value_get_float(hot_y) / scale);
  cairo_surface_destroy(surface);
  return cursor;
}

void on_method_call(FlMethodChannel* channel, FlMethodCall* call,
                    gpointer user_data) {
  FlView* view = FL_VIEW(user_data);
  FlValue* args = fl_method_call_get_args(call);
  const gchar* method = fl_method_call_get_name(call);
  FlValue* name = fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                      ? lookup(args, "name", FL_VALUE_TYPE_STRING)
                      : nullptr;
  g_autoptr(FlMethodResponse) response = nullptr;
  if (name == nullptr) {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  } else if (strcmp(method, "createCustomCursor") == 0) {
    GdkCursor* cursor = cursor_of(view, args);
    if (cursor == nullptr) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "argument", "not a cursor's picture", nullptr));
    } else {
      g_hash_table_replace(g_cursors, g_strdup(fl_value_get_string(name)),
                           cursor);
      g_autoptr(FlValue) made = fl_value_new_string(fl_value_get_string(name));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(made));
    }
  } else if (strcmp(method, "setCustomCursor") == 0) {
    GdkCursor* cursor = static_cast<GdkCursor*>(
        g_hash_table_lookup(g_cursors, fl_value_get_string(name)));
    GdkWindow* window = window_of(view);
    if (cursor == nullptr || window == nullptr) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "argument", "no cursor is named so", nullptr));
    } else {
      gdk_window_set_cursor(window, cursor);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

}  // namespace

void anicel_picture_cursors_register(FlView* view) {
  g_cursors =
      g_hash_table_new_full(g_str_hash, g_str_equal, g_free, g_object_unref);
  FlBinaryMessenger* messenger =
      fl_engine_get_binary_messenger(fl_view_get_engine(view));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_cursor_channel = fl_method_channel_new(messenger, "anicel/cursor",
                                           FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(g_cursor_channel, on_method_call,
                                            view, nullptr);
}
