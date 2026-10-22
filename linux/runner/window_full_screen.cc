#include "window_full_screen.h"

#include <cstring>

// UNVERIFIED-ON-DEVICE: authored on the Windows workstation; the Linux
// build is the release workflow's, not every push's.

namespace {

FlMethodChannel* g_window_channel = nullptr;
gboolean g_full_screen = FALSE;

void report(gboolean on) {
  g_autoptr(FlValue) value = fl_value_new_bool(on);
  fl_method_channel_invoke_method(g_window_channel, "fullScreenChanged", value,
                                  nullptr, nullptr, nullptr);
}

void on_method_call(FlMethodChannel* channel, FlMethodCall* call,
                    gpointer user_data) {
  GtkWindow* window = GTK_WINDOW(user_data);
  FlValue* args = fl_method_call_get_args(call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(fl_method_call_get_name(call), "setFullScreen") == 0 &&
      fl_value_get_type(args) == FL_VALUE_TYPE_BOOL) {
    const gboolean on = fl_value_get_bool(args);
    if (on == g_full_screen) {
      // Already so: said at once, as a change is said when it lands.
      report(g_full_screen);
    } else if (on) {
      gtk_window_fullscreen(window);
    } else {
      gtk_window_unfullscreen(window);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

gboolean on_window_state(GtkWidget* widget, GdkEventWindowState* event,
                         gpointer user_data) {
  if (event->changed_mask & GDK_WINDOW_STATE_FULLSCREEN) {
    g_full_screen =
        (event->new_window_state & GDK_WINDOW_STATE_FULLSCREEN) != 0;
    report(g_full_screen);
  }
  return FALSE;
}

}  // namespace

void anicel_window_full_screen_register(GtkWindow* window, FlView* view) {
  FlBinaryMessenger* messenger =
      fl_engine_get_binary_messenger(fl_view_get_engine(view));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_window_channel = fl_method_channel_new(messenger, "anicel/window",
                                           FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(g_window_channel, on_method_call,
                                            window, nullptr);
  g_signal_connect(GTK_WIDGET(window), "window-state-event",
                   G_CALLBACK(on_window_state), nullptr);
}
