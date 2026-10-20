#ifndef RUNNER_LAUNCH_SPLASH_H_
#define RUNNER_LAUNCH_SPLASH_H_

#include <gtk/gtk.h>

// The picture that stands in the middle of the screen from the moment the
// app is launched until its first frame (I-106-Q3/Q4/Q5, user 2026-10-20:
// the teal A and the white name, nothing behind them — the desktop shows
// through — on every desktop). Without a compositor nothing can show
// through, so the picture stands on a dark ground instead.
//
// Returns the splash window, or nullptr when the picture cannot be read —
// the app starts the same without it.
//
// UNVERIFIED-ON-DEVICE: authored on the Windows workstation.
GtkWidget* anicel_launch_splash_show();

// Takes the splash away. Safe with nullptr.
void anicel_launch_splash_close(GtkWidget* splash);

// Gives every window of the app the app icon (drawn by tool/app_art).
void anicel_app_icon_set();

#endif  // RUNNER_LAUNCH_SPLASH_H_
