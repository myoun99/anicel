#ifndef RUNNER_LAUNCH_SPLASH_H_
#define RUNNER_LAUNCH_SPLASH_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// The picture that stands in the middle of the screen from the moment the
// app is launched until its first frame (I-106-Q3/Q4/Q5, user 2026-10-20:
// the teal A and the white name, nothing behind them — the desktop shows
// through — on every desktop), saying under the name what the launch is
// doing (I-106, 2026-10-21) with dots that turn once a second. Without a
// compositor nothing can show through, so the picture stands on a dark
// ground instead.
//
// Returns the splash window, or nullptr when the picture cannot be read —
// the app starts the same without it.
//
// UNVERIFIED-ON-DEVICE: authored on the Windows workstation. While the
// engine starts, this thread's main loop is busy, so the dots wait.
GtkWidget* anicel_launch_splash_show();

// Says the runner's own stage |index| (0 the engine, 1 the plugins) by the
// name the last launch left. Safe with nullptr.
void anicel_launch_splash_say_runner_stage(GtkWidget* splash, guint index);

// Says a stage Dart names, in the face of |face_files| (tab-separated,
// relative to flutter_assets; empty is the OS's face). Safe with nullptr.
void anicel_launch_splash_say(GtkWidget* splash, const gchar* face_files,
                              const gchar* name);

// Takes the splash away. Safe with nullptr.
void anicel_launch_splash_close(GtkWidget* splash);

// Lets Dart say its launch stages on *|splash| (nullptr once it is closed)
// over |view|'s messenger.
void anicel_launch_splash_listen(GtkWidget** splash, FlView* view);

// Gives every window of the app the app icon (drawn by tool/app_art).
void anicel_app_icon_set();

#endif  // RUNNER_LAUNCH_SPLASH_H_
