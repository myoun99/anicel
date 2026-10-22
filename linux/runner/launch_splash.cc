#include "launch_splash.h"

#include <fontconfig/fontconfig.h>
#include <pango/pangocairo.h>

#include <cstring>
#include <string>
#include <vector>

// I-106-Q6 (user, 2026-10-20): the splash stands half as tall as its
// monitor's short side — 「짧은 변의 50%로하면 가로일땐 높이의 50%」 — so a
// turned monitor gets the same picture. Spelled again in
// windows/runner/launch_splash.cpp and MainFlutterWindow.swift.
static constexpr int kShortSideShare = 2;

// The stage's line, close under the name, small and faint (user,
// 2026-10-21: 「Anicel 아래에 어느정도 붙고, 글자크기도 좀 작게 … 있는듯
// 없는듯한 느낌으로」): its middle and its type size as shares of the
// picture's height (tool/app_art/render_app_art_test.dart,
// kSplashStageCenter and kSplashStageSize over kSplashHeight), and its ink.
// Spelled again in windows/runner/launch_splash.cpp and
// MainFlutterWindow.swift.
static constexpr double kStageCenter = 210.0 / 232.0;
static constexpr double kStageSize = 8.0 / 232.0;
static constexpr double kStageInk = 0.6;
static constexpr double kStageShadow = 0.3;

// 「1초마다 .을 붙이고 초기화하고」 (user, 2026-10-21): one, two, three
// dots, a second each, and round again.
static constexpr guint kDotTurnMs = 1000;
static constexpr int kMostDots = 3;

// The ground under the picture where nothing can show through.
static constexpr double kOpaqueGround[] = {0.09, 0.09, 0.10};

// What lib/src/native/launch_splash.dart leaves for the next launch:
// LaunchSplash.labelsFileName under appSupportFilePath's base.
static constexpr char kLabelsPath[] = "anicel/launch-labels.txt";

struct Splash {
  GdkPixbuf* picture = nullptr;
  std::string last_face_files;
  std::vector<std::string> last_names;
  std::string face_files;
  std::string families;
  std::string name;
  int dots = 1;
  guint timer = 0;
};

static void splash_free(gpointer data) {
  Splash* splash = static_cast<Splash*>(data);
  if (splash->timer != 0) {
    g_source_remove(splash->timer);
  }
  g_object_unref(splash->picture);
  delete splash;
}

static Splash* splash_of(GtkWidget* widget) {
  return widget == nullptr
             ? nullptr
             : static_cast<Splash*>(g_object_get_data(G_OBJECT(widget),
                                                      "anicel-splash"));
}

// |relative| in the bundle beside the executable.
static std::string bundle_path(const std::string& relative) {
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  if (exe == nullptr) {
    return std::string();
  }
  g_autofree gchar* dir = g_path_get_dirname(exe);
  return std::string(dir) + "/" + relative;
}

static std::vector<std::string> split_on(const std::string& text, char on) {
  std::vector<std::string> parts;
  size_t start = 0;
  while (start <= text.size()) {
    size_t end = text.find(on, start);
    if (end == std::string::npos) {
      end = text.size();
    }
    if (end > start) {
      parts.push_back(text.substr(start, end - start));
    }
    start = end + 1;
  }
  return parts;
}

// The face's files in order, as one Pango family list — the first speaks,
// the rest fill in what it lacks, then the OS — or "Sans" (the OS's face)
// when there are none.
static std::string families_of(const std::string& face_files) {
  std::string families;
  for (const std::string& file : split_on(face_files, '\t')) {
    const std::string path = bundle_path("data/flutter_assets/" + file);
    const FcChar8* fc_path = reinterpret_cast<const FcChar8*>(path.c_str());
    FcConfigAppFontAddFile(nullptr, fc_path);
    int count = 0;
    FcPattern* pattern = FcFreeTypeQuery(fc_path, 0, nullptr, &count);
    FcChar8* family = nullptr;
    if (pattern != nullptr &&
        FcPatternGetString(pattern, FC_FAMILY, 0, &family) == FcResultMatch) {
      if (!families.empty()) {
        families += ",";
      }
      families += reinterpret_cast<const char*>(family);
    }
    if (pattern != nullptr) {
      FcPatternDestroy(pattern);
    }
  }
  return families.empty() ? "Sans" : families;
}

static void paint_stage(GtkWidget* widget, cairo_t* cr, Splash* splash) {
  const double height = gtk_widget_get_allocated_height(widget);
  const double width = gtk_widget_get_allocated_width(widget);
  g_autoptr(PangoFontDescription) font =
      pango_font_description_from_string(splash->families.c_str());
  pango_font_description_set_absolute_size(
      font, height * kStageSize * PANGO_SCALE);
  g_autoptr(PangoLayout) name = pango_cairo_create_layout(cr);
  g_autoptr(PangoLayout) dots = pango_cairo_create_layout(cr);
  pango_layout_set_font_description(name, font);
  pango_layout_set_font_description(dots, font);
  pango_layout_set_text(name, splash->name.c_str(), -1);
  const std::string dot_text(static_cast<size_t>(splash->dots), '.');
  pango_layout_set_text(dots, dot_text.c_str(), -1);
  int name_width = 0;
  int name_height = 0;
  pango_layout_get_pixel_size(name, &name_width, &name_height);
  // The name stands still; the dots grow to its right.
  const double left = (width - name_width) / 2;
  const double top = height * kStageCenter - name_height / 2.0;
  const double lift = height / 232.0;
  for (int pass = 0; pass < 2; ++pass) {
    if (pass == 0) {
      cairo_set_source_rgba(cr, 0, 0, 0, kStageShadow);
    } else {
      cairo_set_source_rgba(cr, 1, 1, 1, kStageInk);
    }
    const double y = top + (pass == 0 ? lift : 0);
    cairo_move_to(cr, left, y);
    pango_cairo_show_layout(cr, name);
    cairo_move_to(cr, left + name_width, y);
    pango_cairo_show_layout(cr, dots);
  }
}

static gboolean draw_cb(GtkWidget* widget, cairo_t* cr, gpointer) {
  Splash* splash = splash_of(widget);
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
  cairo_save(cr);
  const double scale = gtk_widget_get_allocated_height(widget) /
                       static_cast<double>(gdk_pixbuf_get_height(
                           splash->picture));
  cairo_scale(cr, scale, scale);
  gdk_cairo_set_source_pixbuf(cr, splash->picture, 0, 0);
  cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_GOOD);
  cairo_paint(cr);
  cairo_restore(cr);
  if (!splash->name.empty()) {
    paint_stage(widget, cr, splash);
  }
  return TRUE;
}

// Drawn now: the engine may keep this thread busy before the main loop
// runs again.
static void draw_now(GtkWidget* widget) {
  gtk_widget_queue_draw(widget);
  while (gtk_events_pending()) {
    gtk_main_iteration();
  }
}

static gboolean turn_dots(gpointer data) {
  GtkWidget* widget = GTK_WIDGET(data);
  Splash* splash = splash_of(widget);
  splash->dots = splash->dots % kMostDots + 1;
  gtk_widget_queue_draw(widget);
  return G_SOURCE_CONTINUE;
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

static void read_labels(Splash* splash) {
  const gchar* base = g_getenv("APPDATA");
  if (base == nullptr) {
    base = g_getenv("HOME");
  }
  if (base == nullptr) {
    return;
  }
  g_autofree gchar* path = g_build_filename(base, kLabelsPath, nullptr);
  g_autofree gchar* text = nullptr;
  if (!g_file_get_contents(path, &text, nullptr, nullptr)) {
    return;
  }
  const std::string labels(text);
  const size_t first_end = labels.find('\n');
  if (first_end == std::string::npos) {
    return;
  }
  splash->last_face_files = labels.substr(0, first_end);
  splash->last_names = split_on(labels.substr(first_end + 1), '\n');
}

GtkWidget* anicel_launch_splash_show() {
  const std::string path = bundle_path("data/launch_splash.png");
  if (path.empty()) {
    return nullptr;
  }
  GdkPixbuf* picture = gdk_pixbuf_new_from_file(path.c_str(), nullptr);
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

  GtkWidget* widget = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  Splash* splash = new Splash();
  splash->picture = picture;
  read_labels(splash);
  g_object_set_data_full(G_OBJECT(widget), "anicel-splash", splash,
                         splash_free);
  GtkWindow* window = GTK_WINDOW(widget);
  gtk_window_set_type_hint(window, GDK_WINDOW_TYPE_HINT_SPLASHSCREEN);
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_skip_taskbar_hint(window, TRUE);
  gtk_window_set_default_size(window, width, height);
  gtk_window_move(window, area.x + (area.width - width) / 2,
                  area.y + (area.height - height) / 2);
  GdkScreen* screen = gtk_widget_get_screen(widget);
  GdkVisual* visual = gdk_screen_get_rgba_visual(screen);
  if (visual != nullptr && gdk_screen_is_composited(screen)) {
    gtk_widget_set_visual(widget, visual);
  }
  gtk_widget_set_app_paintable(widget, TRUE);
  g_signal_connect(widget, "draw", G_CALLBACK(draw_cb), nullptr);
  gtk_widget_show(widget);
  splash->timer = g_timeout_add(kDotTurnMs, turn_dots, widget);
  draw_now(widget);
  return widget;
}

void anicel_launch_splash_say(GtkWidget* widget, const gchar* face_files,
                              const gchar* name) {
  Splash* splash = splash_of(widget);
  if (splash == nullptr) {
    return;
  }
  if (splash->families.empty() || splash->face_files != face_files) {
    splash->face_files = face_files;
    splash->families = families_of(splash->face_files);
  }
  splash->name = name;
  // A new stage starts its dots again from one.
  splash->dots = 1;
  if (splash->timer != 0) {
    g_source_remove(splash->timer);
  }
  splash->timer = g_timeout_add(kDotTurnMs, turn_dots, widget);
  draw_now(widget);
}

void anicel_launch_splash_say_runner_stage(GtkWidget* widget, guint index) {
  // The first launch has no names yet: the line stays empty, its place
  // kept, until Dart speaks.
  Splash* splash = splash_of(widget);
  if (splash != nullptr && index < splash->last_names.size()) {
    anicel_launch_splash_say(widget, splash->last_face_files.c_str(),
                             splash->last_names[index].c_str());
  }
}

void anicel_launch_splash_close(GtkWidget* splash) {
  if (splash != nullptr) {
    gtk_widget_destroy(splash);
  }
}

static FlMethodChannel* g_launch_channel = nullptr;

static void on_launch_call(FlMethodChannel* channel, FlMethodCall* call,
                           gpointer user_data) {
  FlValue* args = fl_method_call_get_args(call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(fl_method_call_get_name(call), "stage") == 0 &&
      fl_value_get_type(args) == FL_VALUE_TYPE_LIST &&
      fl_value_get_length(args) == 2 &&
      fl_value_get_type(fl_value_get_list_value(args, 0)) ==
          FL_VALUE_TYPE_STRING &&
      fl_value_get_type(fl_value_get_list_value(args, 1)) ==
          FL_VALUE_TYPE_STRING) {
    GtkWidget** splash = static_cast<GtkWidget**>(user_data);
    anicel_launch_splash_say(
        *splash, fl_value_get_string(fl_value_get_list_value(args, 0)),
        fl_value_get_string(fl_value_get_list_value(args, 1)));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

void anicel_launch_splash_listen(GtkWidget** splash, FlView* view) {
  FlBinaryMessenger* messenger =
      fl_engine_get_binary_messenger(fl_view_get_engine(view));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_launch_channel = fl_method_channel_new(messenger, "anicel/launch",
                                           FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(g_launch_channel, on_launch_call,
                                            splash, nullptr);
}

void anicel_app_icon_set() {
  const std::string path = bundle_path("data/app_icon.png");
  if (!path.empty()) {
    gtk_window_set_default_icon_from_file(path.c_str(), nullptr);
  }
}
