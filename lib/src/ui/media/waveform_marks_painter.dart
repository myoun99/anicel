import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/canvas_viewport.dart';
import '../canvas/viewport_canvas_transform.dart';
import '../repaint_props.dart';
import '../theme/app_theme.dart' show AppColors;
import '../widgets/transport_bar.dart';

/// The marks over a sound's waveform page: the line that says where in the
/// sound you are, and — where a window keeps a span of it — that span.
///
/// ⚠️Its own painter and its own layer above the page: the page is a
/// [StaticRaster] that re-bakes only when you page or pan, and a playhead
/// inside it would re-bake it on every tick of a run.
///
/// The media viewer's playhead; the import window's preview draws the same
/// line since it became the same panel, with the span IN/OUT keep (F-282 ④,
/// 2026-10-09 — 유저 2026-09-11: 「거기서 가져올 구간을 줄이면 블록도 그만큼
/// 줄어든다」).
class WaveformMarksPainter extends CustomPainter with RepaintOnProps {
  const WaveformMarksPainter({
    required this.atSeconds,
    required this.ofSeconds,
    required this.docSize,
    required this.viewport,
    required this.effectiveRatio,
    required this.color,
    this.kept,
  });

  final double atSeconds;
  final double ofSeconds;
  final ui.Size docSize;
  final CanvasViewport viewport;
  final double effectiveRatio;
  final Color color;

  /// The span kept, in seconds of the sound — washed as the transport's
  /// range is, edged where IN and OUT stand. Null where nothing is kept.
  final ({double from, double to})? kept;

  @override
  void paint(Canvas canvas, Size size) {
    if (ofSeconds <= 0) {
      return;
    }
    canvas.save();
    // The SAME transform the page uses — the marks have to land on the
    // waveform under every zoom and pan, so they cannot compute their own.
    applyViewportTransform(canvas, viewport, devicePixelRatio: effectiveRatio);
    // In DOCUMENT units, so a line thins as you zoom in rather than growing
    // into a bar over the sample it is pointing at.
    final line = docSize.width / 600;
    double xOf(double seconds) =>
        docSize.width * (seconds / ofSeconds).clamp(0.0, 1.0);
    final span = kept;
    if (span != null) {
      final from = xOf(span.from);
      final to = xOf(span.to);
      canvas.drawRect(
        Rect.fromLTRB(from, 0, to, docSize.height),
        Paint()..color = TransportBar.rangeWash,
      );
      final edge = Paint()
        ..strokeWidth = line
        ..color = AppColors.accent;
      for (final x in [from, to]) {
        canvas.drawLine(Offset(x, 0), Offset(x, docSize.height), edge);
      }
    }
    final x = xOf(atSeconds);
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, docSize.height),
      Paint()
        ..strokeWidth = line
        ..color = color,
    );
    canvas.restore();
  }

  @override
  Object get props =>
      (atSeconds, ofSeconds, docSize, viewport, effectiveRatio, color, kept);
}
