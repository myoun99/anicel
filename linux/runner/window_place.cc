#include "window_place.h"

#include <cstring>

// UNVERIFIED-ON-DEVICE: authored on the Windows workstation; the Linux
// build is the release workflow's, not every push's.
//
// ⚠️On Wayland a client cannot place its own window: the size comes back,
// the place is the compositor's.

namespace {

// How long the window is to stand still before it is said: a drag sends a
// configure-event at every step.
constexpr guint kSettleMs = 500;

FlMethodChannel* g_place_channel = nullptr;
guint g_settle_source = 0;

// The last normal frame, the one a maximized window comes back to.
gint g_left = 0;
gint g_top = 0;
gint g_width = 0;
gint g_height = 0;
gboolean g_maximized = FALSE;
gboolean g_full_screen = FALSE;

void report() {
  if (g_width <= 0 || g_height <= 0 || g_full_screen) {
    return;
  }
  g_autoptr(FlValue) frame = fl_value_new_map();
  fl_value_set_string_take(frame, "left", fl_value_new_float(g_left));
  fl_value_set_string_take(frame, "top", fl_value_new_float(g_top));
  fl_value_set_string_take(frame, "width", fl_value_new_float(g_width));
  fl_value_set_string_take(frame, "height", fl_value_new_float(g_height));
  fl_value_set_string_take(frame, "maximized", fl_value_new_bool(g_maximized));
  fl_method_channel_invoke_method(g_place_channel, "placeChanged", frame,
                                  nullptr, nullptr, nullptr);
}

gboolean on_settled(gpointer user_data) {
  g_settle_source = 0;
  GtkWindow* window = GTK_WINDOW(user_data);
  if (!g_maximized && !g_full_screen) {
    gtk_window_get_position(window, &g_left, &g_top);
    gtk_window_get_size(window, &g_width, &g_height);
  }
  report();
  return G_SOURCE_REMOVE;
}

gboolean on_configure(GtkWidget* widget, GdkEvent* event, gpointer user_data) {
  if (gtk_widget_get_visible(widget)) {
    if (g_settle_source != 0) {
      g_source_remove(g_settle_source);
    }
    g_settle_source = g_timeout_add(kSettleMs, on_settled, widget);
  }
  return FALSE;
}

gboolean on_window_state(GtkWidget* widget, GdkEventWindowState* event,
                         gpointer user_data) {
  const GdkWindowState state = event->new_window_state;
  g_full_screen = (state & GDK_WINDOW_STATE_FULLSCREEN) != 0;
  if (event->changed_mask & GDK_WINDOW_STATE_MAXIMIZED) {
    g_maximized = (state & GDK_WINDOW_STATE_MAXIMIZED) != 0;
    report();
  }
  return FALSE;
}

// Whether a monitor still shows any of the frame.
gboolean on_a_monitor(GtkWindow* window, const GdkRectangle& frame) {
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
  for (int i = 0; i < gdk_display_get_n_monitors(display); ++i) {
    GdkRectangle area;
    gdk_monitor_get_workarea(gdk_display_get_monitor(display, i), &area);
    if (gdk_rectangle_intersect(&area, &frame, nullptr)) {
      return TRUE;
    }
  }
  return FALSE;
}

gboolean number(FlValue* frame, const char* key, gint* out) {
  FlValue* value = fl_value_lookup_string(frame, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_FLOAT) {
    return FALSE;
  }
  *out = static_cast<gint>(fl_value_get_float(value));
  return TRUE;
}

void on_method_call(FlMethodChannel* channel, FlMethodCall* call,
                    gpointer user_data) {
  GtkWindow* window = GTK_WINDOW(user_data);
  FlValue* args = fl_method_call_get_args(call);
  g_autoptr(FlMethodResponse) response = nullptr;
  GdkRectangle frame;
  FlValue* maximized = args != nullptr &&
                               fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                           ? fl_value_lookup_string(args, "maximized")
                           : nullptr;
  if (strcmp(fl_method_call_get_name(call), "setPlace") == 0 &&
      maximized != nullptr &&
      fl_value_get_type(maximized) == FL_VALUE_TYPE_BOOL &&
      number(args, "left", &frame.x) && number(args, "top", &frame.y) &&
      number(args, "width", &frame.width) &&
      number(args, "height", &frame.height)) {
    if (on_a_monitor(window, frame)) {
      gtk_window_move(window, frame.x, frame.y);
      gtk_window_resize(window, frame.width, frame.height);
      g_left = frame.x;
      g_top = frame.y;
      g_width = frame.width;
      g_height = frame.height;
    }
    if (fl_value_get_bool(maximized)) {
      gtk_window_maximize(window);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

}  // namespace

void anicel_window_place_register(GtkWindow* window, FlView* view) {
  FlBinaryMessenger* messenger =
      fl_engine_get_binary_messenger(fl_view_get_engine(view));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_place_channel = fl_method_channel_new(messenger, "anicel/window_place",
                                          FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(g_place_channel, on_method_call,
                                            window, nullptr);
  g_signal_connect(GTK_WIDGET(window), "configure-event",
                   G_CALLBACK(on_configure), nullptr);
  g_signal_connect(GTK_WIDGET(window), "window-state-event",
                   G_CALLBACK(on_window_state), nullptr);
}
