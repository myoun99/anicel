#ifndef RUNNER_PICTURE_CURSORS_H_
#define RUNNER_PICTURE_CURSORS_H_

#include <flutter_linux/flutter_linux.h>

// I-54 ⓔ · F-441: the cursors of one size — the pen, the fill's bucket, the
// eyedropper — as the system's own (user 2026-09-30: 「os커서를 바꿈으로서
// 앱이랑 관계없이 빠르게」). This engine takes no picture for a cursor, so the
// runner does: registers the 'anicel/cursor' method channel, whose two calls
// are the ones Windows's engine takes (lib/src/ui/brush/drawing_cursor.dart).
// Call once from my_application_activate after the FlView is added to the
// window.
void anicel_picture_cursors_register(FlView* view);

#endif  // RUNNER_PICTURE_CURSORS_H_
