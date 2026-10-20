#include "launch_splash.h"

// I-106-Q6 (user, 2026-10-20): the splash stands half as tall as its
// monitor's short side — 「짧은 변의 50%로하면 가로일땐 높이의 50%」 — so a
// turned monitor gets the same picture. Spelled again in
// windows/runner/launch_splash.cpp and MainFlutterWindow.swift.
static constexpr int kShortSideShare = 2;

// The ground under the picture where nothing can show through.
static constexpr double kOpaqueGround[] = {0.09, 0.09, 0.10};

// |name| in the bundle's data folder, beside the executable.
static gchar* data_path(const gchar* name) {
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  if (exe == nullptr) {
    return nullptr;
  }
  g_autofree gchar* dir = g_path_get_dirname(exe);
  return g_build_filename(dir, "data", name, nullptr);
}

static gboolean draw_cb(GtkWidget* widget, cairo_t* cr, gpointer data) {
  GdkPixbuf* picture = GDK_PIXBUF(data);
  if (gdk_screen_is_composited(gtk_widget_get_screen(widget))) {
    cairo_set_source_rgba(cr, 0, 0, 0, 0);
  } else {
    cairo_set_source_rgb(cr, kOpaqueGround[0], kOpaqueGround[1],
                         kOpaqueGround[2]);
  }
  cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
  cairo_paint(cr);
  cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
  // The picture is larger than any splash; fit it to the window.
  const double scale = static_cast<double>(gtk_widget_get_allocated_height(
                           widget)) /
                       gdk_pixbuf_get_height(picture);
  cairo_scale(cr, scale, scale);
  gdk_cairo_set_source_pixbuf(cr, picture, 0, 0);
  cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_GOOD);
  cairo_paint(cr);
  return TRUE;
}

// The work area of the monitor the app opens on (the primary one).
static GdkRectangle work_area() {
  GdkRectangle area = {0, 0, 0, 0};
  GdkDisplay* display = gdk_display_get_default();
  GdkMonitor* monitor = gdk_display_get_primary_monitor(display);
  if (monitor == nullptr) {
    monitor = gdk_display_get_monitor(display, 0);
  }
  if (monitor != nullptr) {
    gdk_monitor_get_workarea(monitor, &area);
  }
  return area;
}

GtkWidget* anicel_launch_splash_show() {
  g_autofree gchar* path = data_path("launch_splash.png");
  if (path == nullptr) {
    return nullptr;
  }
  GdkPixbuf* picture = gdk_pixbuf_new_from_file(path, nullptr);
  if (picture == nullptr) {
    return nullptr;
  }
  const GdkRectangle area = work_area();
  const int height = MIN(area.width, area.height) / kShortSideShare;
  if (height <= 0) {
    g_object_unref(picture);
    return nullptr;
  }
  const int width = height * gdk_pixbuf_get_width(picture) /
                    gdk_pixbuf_get_height(picture);

  GtkWidget* splash = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  GtkWindow* window = GTK_WINDOW(splash);
  gtk_window_set_type_hint(window, GDK_WINDOW_TYPE_HINT_SPLASHSCREEN);
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_skip_taskbar_hint(window, TRUE);
  gtk_window_set_default_size(window, width, height);
  gtk_window_move(window, area.x + (area.width - width) / 2,
                  area.y + (area.height - height) / 2);
  GdkScreen* screen = gtk_widget_get_screen(splash);
  GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
  if (visual != nullptr && gdk_screen_is_composited(screen)) {
    gtk_widget_set_visual(splash, visual);
  }
  gtk_widget_set_app_paintable(splash, TRUE);
  // The window holds the picture until it is destroyed.
  g_signal_connect_data(splash, "draw", G_CALLBACK(draw_cb), picture,
                        [](gpointer data, GClosure*) { g_object_unref(data); },
                        static_cast<GConnectFlags>(0));
  gtk_widget_show(splash);
  // Drawn now: the engine starts before the main loop next runs.
  while (gtk_events_pending()) {
    gtk_main_iteration();
  }
  return splash;
}

void anicel_launch_splash_close(GtkWidget* splash) {
  if (splash != nullptr) {
    gtk_widget_destroy(splash);
  }
}

void anicel_app_icon_set() {
  g_autofree gchar* path = data_path("app_icon.png");
  if (path != nullptr) {
    gtk_window_set_default_icon_from_file(path, nullptr);
  }
}
