// Anicel pen sidecar (pen program, PEN-4 — Linux).
//
// Flutter's Linux embedder delivers neither stylus device kinds nor
// pressure (flutter/flutter#63209): GDK sees the pen (GDK_SOURCE_PEN,
// pressure axis via libinput/X11-wacom), the embedder flattens it to a
// mouse. This sidecar restores the driver data: a GTK event hook on the
// top-level window reads the source device + pressure axis per motion/
// button event and streams them over the 'qa_pen/linux' event channel —
// the same pressure-sidecar contract as the Windows Wintab bridge.
//
// UNVERIFIED-ON-DEVICE: written on the Windows workstation; needs one
// Linux build + a tablet pass (the input inspector's driver line is the
// check). Runner-owned (wired from my_application.cc after the window
// is realized) — no plugin registrant churn. The proper long-term fix
// is upstream (pen -> kStylus + pressure in the GTK embedder); this
// sidecar works today without an engine fork.

#include "pen_sidecar.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

static FlEventChannel* g_pen_channel = nullptr;
static gboolean g_pen_listening = FALSE;

// Forwards one tablet-capable GdkEvent's pen data onto the channel.
static gboolean qa_pen_window_event(GtkWidget* widget, GdkEvent* event,
                                    gpointer user_data) {
  if (!g_pen_listening || g_pen_channel == nullptr) {
    return FALSE;  // Never consume — observe only.
  }
  if (event->type != GDK_MOTION_NOTIFY && event->type != GDK_BUTTON_PRESS &&
      event->type != GDK_BUTTON_RELEASE) {
    return FALSE;
  }
  GdkDevice* device = gdk_event_get_source_device(event);
  if (device == nullptr) {
    return FALSE;
  }
  GdkInputSource source = gdk_device_get_source(device);
  if (source != GDK_SOURCE_PEN && source != GDK_SOURCE_ERASER) {
    return FALSE;
  }
  gdouble pressure = 0.0;
  if (!gdk_event_get_axis(event, GDK_AXIS_PRESSURE, &pressure)) {
    pressure = 0.0;
  }
  gdouble tilt_x = 0.0;
  gdouble tilt_y = 0.0;
  gdk_event_get_axis(event, GDK_AXIS_XTILT, &tilt_x);
  gdk_event_get_axis(event, GDK_AXIS_YTILT, &tilt_y);

  g_autoptr(FlValue) message = fl_value_new_map();
  fl_value_set_string_take(message, "pressure", fl_value_new_float(pressure));
  fl_value_set_string_take(message, "tiltX", fl_value_new_float(tilt_x));
  fl_value_set_string_take(message, "tiltY", fl_value_new_float(tilt_y));
  fl_value_set_string_take(message, "timeMs",
                           fl_value_new_float(gdk_event_get_time(event)));
  fl_value_set_string_take(
      message, "eraser",
      fl_value_new_bool(source == GDK_SOURCE_ERASER ? TRUE : FALSE));
  fl_event_channel_send(g_pen_channel, message, nullptr, nullptr);
  return FALSE;
}

static FlMethodErrorResponse* qa_pen_listen(FlEventChannel* channel,
                                            FlValue* args,
                                            gpointer user_data) {
  g_pen_listening = TRUE;
  return nullptr;
}

static FlMethodErrorResponse* qa_pen_cancel(FlEventChannel* channel,
                                            FlValue* args,
                                            gpointer user_data) {
  g_pen_listening = FALSE;
  return nullptr;
}

void qa_pen_sidecar_register(GtkWindow* window, FlView* view) {
  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_pen_channel = fl_event_channel_new(messenger, "qa_pen/linux",
                                       FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(g_pen_channel, qa_pen_listen,
                                       qa_pen_cancel, nullptr, nullptr);

  // Pen axes only stream to widgets that ask for them.
  gtk_widget_add_events(GTK_WIDGET(window),
                        GDK_POINTER_MOTION_MASK | GDK_BUTTON_PRESS_MASK |
                            GDK_BUTTON_RELEASE_MASK);
  g_signal_connect(GTK_WIDGET(window), "event",
                   G_CALLBACK(qa_pen_window_event), nullptr);
}
