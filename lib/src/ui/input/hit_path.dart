import 'package:flutter/gestures.dart' show HitTestTarget;
import 'package:flutter/rendering.dart';

/// WHAT IS UNDER A POINT ON SCREEN — every box a press there lands on, the
/// deepest first, as the press itself is found: of the whole view
/// ([hitPathInView]), or of one box alone ([hitPathWithin]).
///
/// The one spelling of the ask. A press asks it to learn what it landed on
/// beyond what took it (`panSlideUnder`, `RowControlSurface.covers`), and a
/// drop from the OS — no press, and it reaches no widget by itself — to
/// learn which place it fell on (`osFileDropPlaceAt`).
Iterable<HitTestTarget> hitPathInView(Offset globalPosition, int viewId) {
  final result = HitTestResult();
  RendererBinding.instance.hitTestInView(result, globalPosition, viewId);
  return _targetsOf(result);
}

/// [hitPathInView], asked of [box] alone — what is above it on screen is
/// not on the path.
Iterable<HitTestTarget> hitPathWithin(RenderBox box, Offset globalPosition) {
  final result = BoxHitTestResult();
  box.hitTest(result, position: box.globalToLocal(globalPosition));
  return _targetsOf(result);
}

Iterable<HitTestTarget> _targetsOf(HitTestResult result) => [
  for (final entry in result.path) entry.target,
];
