// A STACK WITH NOTHING TO DRAW DRAWS NOTHING — NOT A BUFFER OF NOTHING.
//
// The canvas's ghosts' view is mounted standing with no ghost too (onion
// off), and it stands on no row and no paper. Its composite was seeded with
// the page, so every paint of it rastered an empty buffer the size of the
// canvas in view and laid it over the frame: 2736×1742 at 100% on the
// Surface Pro 11, the whole 3840² page at fit — a scrub step there took
// 130–300ms to reach the screen against the 70ms of a hover, and 70ms with
// no buffer at all (D7-2, 2026-10-25). The pixels are the same either way,
// so this pins what it costs: no draw reaches the canvas.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/ui/playback/layer_frame_image_cache.dart';

import '../../helpers/the_frame_as_it_stands.dart';

void main() {
  const canvasSize = CanvasSize(width: 200, height: 100);
  const screen = Size(300, 200);

  Future<List<Symbol>> drawsOf(
    WidgetTester tester, {
    required bool paper,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: screen.width,
            height: screen.height,
            child: TheFrameAsItStands(
              nodes: const [],
              imageCache: LayerFrameImageCache(frameStore: BrushFrameStore()),
              canvasSize: canvasSize,
              viewport: CanvasViewport(zoom: 1, panX: 0, panY: 0),
              paintPaper: paper,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final painter = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(TheFrameAsItStands),
            matching: find.byType(CustomPaint),
          ),
        )
        .where((paint) => paint.painter != null)
        .first
        .painter!;
    final canvas = _ClippedRecording(Offset.zero & screen);
    painter.paint(canvas, screen);
    return [
      for (final call in canvas.invocations)
        if (call.invocation.memberName.toString().startsWith('Symbol("draw'))
          call.invocation.memberName,
    ];
  }

  testWidgets('no row and no paper: nothing is drawn', (tester) async {
    expect(await drawsOf(tester, paper: false), isEmpty);
  });

  testWidgets('no row but the paper: the paper is drawn', (tester) async {
    expect(await drawsOf(tester, paper: true), isNotEmpty);
  });
}

/// A recording that answers where it is clipped and how it is turned, as a
/// screen's canvas does — the paint asks both before it composes.
class _ClippedRecording extends TestRecordingCanvas {
  _ClippedRecording(this._clip);

  final Rect _clip;

  @override
  Rect getLocalClipBounds() => _clip;

  @override
  Rect getDestinationClipBounds() => _clip;

  @override
  Float64List getTransform() => Matrix4.identity().storage;
}
