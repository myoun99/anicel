import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;

/// The pictures a run of frames is made of, each under what it was made of,
/// each held for ONE frame after the last frame that asked for it.
///
/// A frame asks for the pictures it is made of ([of]). One it shares with
/// the frame before it is that frame's picture, handed again; one nobody
/// asked for in a whole frame is let go when the frame after starts
/// ([nextFrame]). Two frames are all this is for — a picture held across a
/// run of frames is made once for the run, and nothing older stays.
///
/// GPU pictures, so let go by hand: [dispose] when the run is over.
class HeldPictures {
  var _thisFrame = <Object, ui.Image>{};
  var _frameBefore = <Object, ui.Image>{};

  /// How many pictures [of] has had to make — a frame that is made of what
  /// the frame before it was made of makes none.
  int get made => _made;
  int _made = 0;

  /// How many pictures every holder is holding right now (test hook) — a
  /// run that is over holds none.
  @visibleForTesting
  static int debugHeld = 0;

  /// The picture held under [key] — asked for by this frame already, or by
  /// the frame before it — or [render]'s, held from now on.
  ///
  /// The holder's own: nobody it is handed to disposes it. A [render] that
  /// fails holds nothing.
  Future<ui.Image> of(Object key, Future<ui.Image> Function() render) async {
    final held = _thisFrame[key] ?? _frameBefore.remove(key);
    if (held != null) {
      return _thisFrame[key] = held;
    }
    _made += 1;
    final picture = await render();
    debugHeld += 1;
    return _thisFrame[key] = picture;
  }

  /// Starts the next frame: what the frame before the last one asked for,
  /// and the last one did not, is let go; what the last one asked for is
  /// kept for one more.
  void nextFrame() {
    _frameBefore.values.forEach(_letGo);
    _frameBefore = _thisFrame;
    _thisFrame = {};
  }

  /// Lets go of every picture held.
  void dispose() {
    for (final held in [_thisFrame, _frameBefore]) {
      held.values.forEach(_letGo);
      held.clear();
    }
  }

  static void _letGo(ui.Image picture) {
    picture.dispose();
    debugHeld -= 1;
  }
}
