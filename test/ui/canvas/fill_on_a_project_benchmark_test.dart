@Tags(['benchmark'])
library;

// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/native/engine_floods.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/canvas_read_source.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/a_fill_on_a_session.dart';
import '../../helpers/opened_session.dart';

/// The bucket's tap on a real project, timed: the whole press as a canvas
/// makes it ([fillPressedOn]) — the frame's picture, the flood, its finish
/// — and the range cut into stamp pieces, a first tap and its repeats, for
/// each read source, inside the canvas and let out past it. Prints FILLON
/// lines; run with `--dart-define=BRUSH_LAB_PROFILE=true` for the picture
/// and the flood apart (`fill.picture` · `fill.flood`).
///
/// 🗣️유저 2026-10-27: 「성능같은거 측정할때 … S5_BA파일의 컷352로 측정해줘 …
/// 측정할땐 비지블 다 on해서 최대한 무겁게해서」 — every row of the cut is
/// shown here, so:
/// ⛔FILL_COPY names a COPY of a project, never a user's own file.
/// FILL_CUT is its cut's name (352), FILL_ROW the row stood on (D+2),
/// FILL_AT the canvas points pressed, `x,y;x,y` (the middle).
/// Skipped where FILL_COPY is unset.
void main() {
  opensTheEnginesScreens();

  test(
    'fill tap staged timings on a project',
    () async {
      final env = Platform.environment;
      final copy = env['FILL_COPY'];
      if (copy == null) {
        markTestSkipped('FILL_COPY names no copy of a project');
        return;
      }
      final kernels = Stopwatch()..start();
      await EngineFloods.warm();
      print('FILLON kernels compiled in ${kernels.elapsedMilliseconds}ms');

      final opened = Stopwatch()..start();
      final session = await openedSession(copy.replaceAll(r'\', '/'));
      addTearDown(session.dispose);
      final cutName = env['FILL_CUT'] ?? '352';
      final cut = session.repository
          .requireProject()
          .tracks
          .expand((track) => track.cuts)
          .firstWhere((cut) => cut.name == cutName);
      session.selectCut(cut.id);
      session.layerSwitches.setAllLayersVisibility(true);
      final rowName = env['FILL_ROW'] ?? 'D+2';
      session.selectLayer(
        session.layers.firstWhere((layer) => layer.name == rowName).id,
      );
      session.selectFrameIndex(session.requireActiveCut.duration ~/ 2);
      final size = session.requireActiveCut.canvasSize;
      print(
        'FILLON opened in ${opened.elapsedMilliseconds}ms: cut $cutName '
        '${size.width}x${size.height}, ${session.layers.length} rows, on '
        '$rowName at frame ${session.currentFrameIndex}',
      );

      final points = [
        for (final at in (env['FILL_AT'] ?? '').split(';'))
          if (at.contains(','))
            CanvasPoint(
              x: double.parse(at.split(',').first),
              y: double.parse(at.split(',').last),
            ),
      ];
      if (points.isEmpty) {
        points.add(CanvasPoint(x: size.width / 2, y: size.height / 2));
      }

      for (final source in CanvasReadSource.values) {
        for (final past in [false, true]) {
          final options = FloodFillOptions(
            source: source,
            extendBeyondCanvas: past,
          );
          for (final at in points) {
            for (final tap in ['first', 'again', 'again', 'again']) {
              final press = Stopwatch()..start();
              final range = fillPressedOn(session, at, options: options);
              press.stop();
              final pieces = Stopwatch()..start();
              final dabs = range?.dabsIn(0xFF3366CC) ?? const [];
              pieces.stop();
              final region = range?.region;
              print(
                'FILLON ${source.name}${past ? ' past' : ''} '
                '(${at.x.round()},${at.y.round()}) $tap '
                'press=${press.elapsedMilliseconds}ms '
                'pieces=${pieces.elapsedMilliseconds}ms '
                'count=${dabs.length} '
                '${range == null
                    ? 'nothing'
                    : region == null
                    ? 'open'
                    : '${region.width}x${region.height}'}',
              );
            }
          }
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
