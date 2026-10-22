#ifndef RUNNER_WINDOW_PLACE_H_
#define RUNNER_WINDOW_PLACE_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Where the window stands (I-116, user 2026-10-21: 「닫고 열때 마지막크기/
// 위치로 열고싶음」). Registers the 'anicel/window_place' method channel —
// Dart's setPlace puts the window where the last run left it, before the
// first frame shows it — and says where the window stands once it has
// settled after a move or a resize, and whenever it is maximized or back.
// Call once from my_application_activate after the FlView is added to the
// window.
void anicel_window_place_register(GtkWindow* window, FlView* view);

#endif  // RUNNER_WINDOW_PLACE_H_
