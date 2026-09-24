@Tags(['benchmark'])
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_coverage.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/native/qa_native_engine.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_ops.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_tile_store.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import '../../helpers/native_engine_path.dart';
import 'timeline_frame_geometry_probe.dart';

/// What a row's substrate costs to BAKE on the native rasterizer: a
/// 240-frame working row in 64-frame tiles at DPR 1.5.
///
/// The two per-cell bakes this replaced are rebuilt here from the painter's
/// own answers, so the comparison survives them: pre-I-44 (a field fill per
/// cell and one per interior seam) and I-44 (a field fill per cell, no
/// line). Against them, today's emitter with the block frame lines off and
/// on (유저 2026-09-24: a switch, and 「좀 더 성능적으로 개선해주면 좋아」).
///
/// 🔬Measured 2026-09-24 (median of 60, four tiles): 24px pre-I-44 2.8ms ·
/// I-44 2.0 · off 1.45 · on 1.45; 12px 1.26 · 1.16 · 0.56 · 0.61; 8px
/// 0.77 · 0.62 · 0.33 · 0.41 — the lines on cost less than I-44's bare
/// paper did.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dllPath = nativeEngineLibraryPathOrNull();

  setUp(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = dllPath;
    QaNativeEngine.debugForceDartFallback = false;
  });

  tearDown(() {
    QaNativeEngine.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
  });

  const frames = 240;
  const span = 64;
  const dpr = 1.5;
  const fps = 24;
  const lengths = [2, 3, 1, 6, 4, 2, 12, 3, 8, 1, 2, 4];

  Layer workingRow() {
    final timeline = <int, TimelineExposure>{};
    final cels = <Frame>[];
    var at = 0;
    for (var i = 0; at < frames; i += 1) {
      final length = lengths[i % lengths.length];
      final id = FrameId('c$i');
      cels.add(Frame(id: id, duration: 1, strokes: const []));
      timeline[at] = TimelineExposure.drawing(id, length: length);
      at += length;
    }
    return Layer(
      id: const LayerId('bench'),
      name: 'A',
      frames: cels,
      timeline: timeline,
    );
  }

  TimelineCellExposureState stateFor(Layer layer, int frameIndex) {
    if (layer.timeline[frameIndex]?.isDrawing ?? false) {
      return TimelineCellExposureState.drawingStart;
    }
    if (coveringDrawingBlockAt(layer.timeline, frameIndex) != null) {
      return TimelineCellExposureState.held;
    }
    return TimelineCellExposureState.uncovered;
  }

  test('bake cost: pre-I-44 / I-44 / today off / today on', () {
    final engine = QaNativeEngine.instance;
    if (engine == null) {
      markTestSkipped('native engine not built');
      return;
    }
    const scheme = ColorScheme.dark();
    for (final cell in [24.0, 12.0, 8.0]) {
      TimelineRowCellsPainter painterFor({required bool lines}) =>
          TimelineRowCellsPainter(
            layer: workingRow(),
            geometry: testFrameGeometry(
              frameCellExtent: cell,
              frameEndIndexExclusive: frames,
            ),
            crossAxisExtent: 28,
            exposureStateForLayer: stateFor,
            colorScheme: scheme,
            baseTextStyle: const TextStyle(fontSize: 11),
            blockFrameLines: lines,
            framesPerSecond: fps,
          );
      final off = painterFor(lines: false);
      final on = painterFor(lines: true);
      final model = <String, List<Int32List>>{
        'pre-I-44': [],
        'I-44': [],
        'off': [],
        'on': [],
      };
      for (var start = 0; start < frames; start += span) {
        final end = (start + span).clamp(0, frames);
        final originMain = off.cellRectFor(start).left;

        // The per-cell bakes, rebuilt: a field fill per papered cell with
        // its own corners, and pre-I-44 a field fill per interior seam.
        Int32List perCell({required bool seams}) {
          final writer = TimelineGridTileOpWriter();
          for (var frame = start; frame < end; frame += 1) {
            final style = off.resolvedCellStyleFor(frame);
            if (style.background.a <= 0) {
              continue;
            }
            final paper = off.paperRectFor(frame);
            final radius = style.radius;
            var mask = 0;
            var value = 0.0;
            if (radius != null) {
              for (final (corner, bit) in [
                (radius.topLeft, TimelineGridTileOp.cornerTopLeft),
                (radius.topRight, TimelineGridTileOp.cornerTopRight),
                (radius.bottomLeft, TimelineGridTileOp.cornerBottomLeft),
                (radius.bottomRight, TimelineGridTileOp.cornerBottomRight),
              ]) {
                if (corner.x > 0) {
                  mask |= bit;
                  value = corner.x;
                }
              }
            }
            writer.rrectFill(
              (paper.left - originMain) * dpr,
              paper.top * dpr,
              paper.width * dpr,
              paper.height * dpr,
              value * dpr,
              mask,
              timelineGridPackRgba(style.background),
            );
          }
          if (seams) {
            for (final line in on.substrateIn(start, end).lines) {
              writer.rrectFill(
                (line.rect.left - originMain) * dpr,
                line.rect.top * dpr,
                line.rect.width * dpr,
                line.rect.height * dpr,
                0,
                0,
                timelineGridPackRgba(line.color),
              );
            }
          }
          return writer.build();
        }

        model['pre-I-44']!.add(perCell(seams: true));
        model['I-44']!.add(perCell(seams: false));
        for (final (name, painter) in [('off', off), ('on', on)]) {
          model[name]!.add(
            timelineGridSubstrateOps(
              painter: painter,
              spanStartIndex: start,
              spanEndIndexExclusive: end,
              devicePixelRatio: dpr,
            ),
          );
        }
      }

      final width = (span * cell * dpr).ceil();
      final height = (28 * dpr).ceil();
      final pixels = Uint8List(width * height * 4);
      final results = <String>[];
      for (final entry in model.entries) {
        final words = entry.value.fold<int>(0, (sum, ops) => sum + ops.length);
        final samples = <int>[];
        for (var round = 0; round < 60; round += 1) {
          final watch = Stopwatch()..start();
          for (final ops in entry.value) {
            engine.gridRasterTileBytes(
              pixels: pixels,
              tileWidth: width,
              tileHeight: height,
              backgroundRgba: 0,
              ops: ops,
            );
          }
          samples.add(watch.elapsedMicroseconds);
        }
        samples.sort();
        results.add(
          '${entry.key}: ${words}w median ${samples[samples.length ~/ 2]}us',
        );
      }
      // ignore: avoid_print
      print('cell ${cell}px — ${results.join(' | ')}');
    }
  });
}
