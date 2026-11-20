import 'package:flutter/widgets.dart';

import '../native/lost_screen.dart';

/// 🚨A SCREEN WHOSE GRAPHICS DEVICE WENT IS DRAWN ON NO MORE ([LostScreen]).
///
/// 🔬On the Surface (Intel, dxcap -forcetdr, 2026-11-18 15:08) the window
/// stood white and alive for 26 seconds after the reset, and the first frame
/// drawn then ended the process: Impeller's GLES encoder refused the frame
/// and a FML_CHECK aborted (`render_pass_gles.cc:844` — engine code, nothing
/// in Dart can catch it). And a frame drawn there shows nothing anyway: the
/// window does not present again.
///
/// So once the runner says the device went, a frame is begun as ever — its
/// callbacks are called, and what waits for a frame's end hears it — and is
/// not drawn, as a frame asked for only to look is not ([LookOnlyFrames]).
/// The windows the app opens meanwhile are asked by Windows instead.
///
/// ⛔One fact, not a flag of its own: it reads [LostScreen.hasGone].
mixin LostScreenFrames on WidgetsBinding {
  @override
  void drawFrame() {
    if (!LostScreen.hasGone) {
      super.drawFrame();
    }
  }
}
