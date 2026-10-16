#ifndef RUNNER_WINDOW_FULL_SCREEN_H_
#define RUNNER_WINDOW_FULL_SCREEN_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// The window's full screen (I-103-Q2, user 2026-10-16: 「데스크톱만 켜고
// 끄기」). Registers the 'anicel/window' method channel — Dart's
// setFullScreen throws GTK's switch — and reports every time the window goes
// in or out, a window manager's own key included, so the app's mark follows
// the window. Call once from my_application_activate after the FlView is
// added to the window.
void anicel_window_full_screen_register(GtkWindow* window, FlView* view);

#endif  // RUNNER_WINDOW_FULL_SCREEN_H_
