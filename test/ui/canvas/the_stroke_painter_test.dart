import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_settings.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/stroke.dart';
import 'package:anicel/src/models/stroke_id.dart';
import 'package:anicel/src/models/stroke_point.dart';
import 'package:anicel/src/ui/canvas/stroke_painter.dart';

/// The vector stroke painter — nothing named it (2026-09-05).
///
/// Pinned by PIXELS, because everything here is about what lands on the
/// canvas: a hidden layer contributing nothing, a layer's opacity
/// multiplying into its strokes, and the live points drawing at a fixed
/// preview alpha whatever the brush says.
void main() {
  const size = 40;

  Stroke strokeAt(List<Offset> points, {double width = 6, int? color}) =>
      Stroke(
        id: const StrokeId('s'),
        points: [
          for (final point in points) StrokePoint(x: point.dx, y: point.dy),
        ],
        brushSettings: BrushSettings(size: width, color: color ?? 0xFF000000),
      );

  Layer layer(String id, {bool visible = true, double opacity = 1}) => Layer(
    id: LayerId(id),
    name: id,
    frames: const [],
    timeline: const {},
    kind: LayerKind.image,
    isVisible: visible,
    opacity: opacity,
  );

  Frame frameWith(List<Stroke> strokes) =>
      Frame(id: const FrameId('f'), duration: 1, strokes: strokes);

  Future<Uint32List> paint(StrokePainter painter) async {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(size * 1.0, size * 1.0));
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(size, size);
      try {
        final data = await image.toByteData();
        return data!.buffer.asUint32List();
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  /// How dark the middle of the canvas is — the stroke runs through it.
  int darknessAtCentre(Uint32List pixels) {
    final pixel = pixels[(size ~/ 2) * size + (size ~/ 2)];
    final r = pixel & 0xFF;
    return 255 - r;
  }

  final line = [const Offset(4, 20), const Offset(36, 20)];

  test('a bare canvas is paper, not nothing — the painter owns its own '
      'background', () async {
    final pixels = await paint(const StrokePainter());

    expect(darknessAtCentre(pixels), 0);
    expect(pixels[0] >>> 24, 0xFF, reason: 'opaque paper, not transparency');
  });

  test('a stroke lands', () async {
    final pixels = await paint(StrokePainter(strokes: [strokeAt(line)]));

    expect(darknessAtCentre(pixels), greaterThan(200));
  });

  test('⛔a HIDDEN layer contributes nothing', () async {
    final pixels = await paint(
      StrokePainter(
        paintableLayers: [
          PaintableLayer(
            layer: layer('a', visible: false),
            frame: frameWith([strokeAt(line)]),
          ),
        ],
      ),
    );

    expect(darknessAtCentre(pixels), 0);
  });

  test('🚨a layer\'s OPACITY multiplies into its strokes — the row\'s '
      'slider is not a separate compositing pass here', () async {
    final full = await paint(
      StrokePainter(
        paintableLayers: [
          PaintableLayer(layer: layer('a'), frame: frameWith([strokeAt(line)])),
        ],
      ),
    );
    final faint = await paint(
      StrokePainter(
        paintableLayers: [
          PaintableLayer(
            layer: layer('a', opacity: 0.25),
            frame: frameWith([strokeAt(line)]),
          ),
        ],
      ),
    );

    expect(darknessAtCentre(faint), lessThan(darknessAtCentre(full)));
    expect(darknessAtCentre(faint), greaterThan(0));
  });

  test('🚨LAYERS win over the loose stroke list — a painter given both '
      'draws the layers, not both', () async {
    final pixels = await paint(
      StrokePainter(
        strokes: [strokeAt(line)],
        paintableLayers: [
          PaintableLayer(
            layer: layer('a', visible: false),
            frame: frameWith(const []),
          ),
        ],
      ),
    );

    expect(
      darknessAtCentre(pixels),
      0,
      reason: 'the loose stroke would have drawn if both were painted',
    );
  });

  test('🚨the LIVE points draw at a fixed preview alpha, whatever the '
      'brush says — an in-flight stroke is a preview, not the mark', () async {
    final live = await paint(
      StrokePainter(
        activePoints: [
          for (final point in line) StrokePoint(x: point.dx, y: point.dy),
        ],
      ),
    );
    final landed = await paint(StrokePainter(strokes: [strokeAt(line)]));

    expect(darknessAtCentre(live), greaterThan(0));
    expect(darknessAtCentre(live), lessThan(darknessAtCentre(landed)));
  });

  test('a single point still draws — a tap is a dot', () async {
    final pixels = await paint(
      StrokePainter(
        strokes: [
          strokeAt([const Offset(20, 20)]),
        ],
      ),
    );

    expect(darknessAtCentre(pixels), greaterThan(200));
  });

  test('⛔an EMPTY stroke draws nothing rather than a stray dot', () async {
    final pixels = await paint(StrokePainter(strokes: [strokeAt(const [])]));

    expect(darknessAtCentre(pixels), 0);
  });

  test('it repaints when any of the three inputs change, and not '
      'otherwise', () {
    const painter = StrokePainter();

    expect(painter.shouldRepaint(const StrokePainter()), isFalse);
    expect(
      painter.shouldRepaint(StrokePainter(strokes: [strokeAt(line)])),
      isTrue,
    );
  });
}
