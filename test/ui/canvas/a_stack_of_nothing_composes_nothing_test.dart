// A STACK WITH NOTHING TO DRAW COVERS NOTHING — NOT A PAGE OF NOTHING.
//
// The canvas's ghosts' view is mounted standing with no ghost too (onion
// off), and it stands on no row and no paper. Its composite was seeded with
// the page, so every paint of it rastered an empty buffer the size of the
// canvas in view and laid it over the frame: 2736×1742 at 100% on the
// Surface Pro 11, the whole 3840² page at fit — a scrub step there took
// 130–300ms to reach the screen against the 70ms of a hover, and 70ms with
// no buffer at all (D7-2, 2026-10-25). The pixels are the same either way,
// so this pins what it costs: the world it covers.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/ui/playback/stacked_frame_picture.dart';

void main() {
  const canvasSize = CanvasSize(width: 200, height: 100);

  Rect worldOf({required bool paper}) => stackedFrameOf(
    const [],
    page: (
      canvasSize: canvasSize,
      pasteboardReach: PasteboardReach.whole,
      paintPaper: paper,
      paperBackground: ProjectBackground.defaultBackground,
    ),
    surfaceOf: (_) => null,
  ).extent;

  test('no row and no paper: it covers nothing', () {
    expect(worldOf(paper: false), Rect.zero);
  });

  test('no row but the paper: it covers the page', () {
    expect(worldOf(paper: true), canvasSize.canvasRect);
  });
}
