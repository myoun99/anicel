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

  /// Whether the run is over ([dispose]).
  bool _over = false;

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
  ///
  /// 🚨ONE PICTURE IS HELD UNDER A KEY: a render that lands where another
  /// landed first while it was out is let go, and its asker is handed the
  /// one held. 🚨A PICTURE THAT LANDS AFTER THE RUN IS OVER IS LET GO, AND
  /// ITS ASK FAILS: nothing is held once [dispose] is called, and whoever
  /// would be handed it does not let go of it — the run it was for is over.
  /// ↩️An engine's picture lands in real time (7′): two asks for one key
  /// before either landed put the first out of reach, and one landing after
  /// a window closed over its preview stayed held for good. (A render out
  /// is not handed to a second asker: a test's seam asks again in real time
  /// for what it asked under a faked clock, which never lands there.)
  Future<ui.Image> of(Object key, Future<ui.Image> Function() render) async {
    final held = _heldUnder(key);
    if (held != null) {
      return held;
    }
    _made += 1;
    final picture = await render();
    if (_over) {
      picture.dispose();
      throw StateError('the run this picture was made for is over');
    }
    final landedFirst = _heldUnder(key);
    if (landedFirst != null) {
      picture.dispose();
      return landedFirst;
    }
    debugHeld += 1;
    return _thisFrame[key] = picture;
  }

  /// The picture held under [key], now this frame's, or null.
  ui.Image? _heldUnder(Object key) {
    final held = _thisFrame[key] ?? _frameBefore.remove(key);
    return held == null ? null : _thisFrame[key] = held;
  }

  /// Starts the next frame: what the frame before the last one asked for,
  /// and the last one did not, is let go; what the last one asked for is
  /// kept for one more.
  void nextFrame() {
    _frameBefore.forEach(_letGo);
    _frameBefore = _thisFrame;
    _thisFrame = {};
  }

  /// Lets go of every picture held — and of every one still out, once it
  /// lands ([of]).
  void dispose() {
    _over = true;
    for (final held in [_thisFrame, _frameBefore]) {
      held.forEach(_letGo);
      held.clear();
    }
  }

  void _letGo(Object key, ui.Image picture) {
    picture.dispose();
    debugHeld -= 1;
  }
}
