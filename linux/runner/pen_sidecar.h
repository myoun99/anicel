#ifndef RUNNER_PEN_SIDECAR_H_
#define RUNNER_PEN_SIDECAR_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// Anicel pen sidecar (pen program, PEN-4 — Linux). Registers the
// 'qa_pen/linux' event channel and hooks the window's GDK events to
// stream pen pressure/tilt (which the Flutter Linux embedder drops,
// flutter/flutter#63209). Call once from my_application_activate after
// the FlView is added to the window.
void qa_pen_sidecar_register(GtkWindow* window, FlView* view);

#endif  // RUNNER_PEN_SIDECAR_H_
