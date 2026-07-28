@Tags(['benchmark'])
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../helpers/panel_finders.dart';

/// What a folder's GROUP BUFFER costs while you draw INSIDE it (not a
/// correctness test — folder_group_buffer_test owns the contract and
/// folder_buffer_route_parity_test owns the pixels).
///
/// The merged canvas paints the whole composite tree in one picture, so a
/// buffering folder around the active layer means a real `saveLayer` every
/// paint. The default project has no folders at all, which is why the
/// full-pipeline benchmark never exercised one — this measures the same
/// move-pump path with a multiply folder wrapped around the layer being
/// drawn on, against the pass-through baseline.
///
/// The buffer's bounds are the VISIBLE canvas rect, not the pasteboard
/// (5×5 canvases = 25× the area) — that clamp is the difference between a
/// buffer costing about what it draws and costing 25× that.
void main() {
  testWidgets('move-pump cost: pass-through folder vs BUFFERING folder '
      'around the layer being drawn on', (tester) async {
    late ProjectRepository repository;
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(onRepositoryCreated: (repo) => repository = repo),
      ),
    );
    await tester.pumpAndSettle();

    final addButton = find.byKey(const ValueKey<String>('new-frame-button'));
    await tester.ensureVisible(addButton);
    await tester.pumpAndSettle();
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    final canvas = mainCanvasView();
    expect(canvas, findsOneWidget, reason: 'authored cel must be drawable');

    // Group the active layer through the menu (the app's own entrance).
    await tester.ensureVisible(find.byKey(const ValueKey<String>('menu-layer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('menu-layer')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('menu-layer-group-into-folder')),
    );
    await tester.pumpAndSettle();

    final cut = repository.requireProject().tracks.first.cuts.first;
    final folder = cut.layers.folderLayers.single;
    expect(
      folder.blendMode,
      LayerBlendMode.passThrough,
      reason: 'a fresh folder buffers nothing — the baseline below',
    );

    Future<double> pumpStrokes() async {
      final center = tester.getCenter(canvas);
      final watch = Stopwatch();
      const strokes = 10;
      const movesPerStroke = 8;
      for (var stroke = 0; stroke < strokes; stroke += 1) {
        final gesture = await tester.startGesture(
          center + Offset(stroke.toDouble() - 5, 0),
          kind: PointerDeviceKind.stylus,
        );
        for (var move = 0; move < movesPerStroke; move += 1) {
          await gesture.moveBy(const Offset(3, 2));
          watch.start();
          await tester.pump(const Duration(milliseconds: 16));
          watch.stop();
        }
        await gesture.up();
        await tester.pumpAndSettle();
      }
      return watch.elapsedMicroseconds / (strokes * movesPerStroke) / 1000;
    }

    // Warm the pipeline so neither reading pays first-paint costs.
    await pumpStrokes();

    // PASS THROUGH: no buffer at all — what every organizing folder costs.
    final passThrough = await pumpStrokes();

    // MULTIPLY: a real group buffer wraps the active layer every paint.
    repository.updateLayer(
      layerId: folder.id,
      update: (layer) => layer.copyWith(blendMode: LayerBlendMode.multiply),
    );
    await tester.pumpAndSettle();
    final buffered = await pumpStrokes();

    // ignore: avoid_print
    print(
      '[folder-buffer] move-pump  passThrough '
      '${passThrough.toStringAsFixed(2)}ms  |  buffered '
      '${buffered.toStringAsFixed(2)}ms',
    );

    // No ratio assertion: a debug-build single run has too much variance
    // to pin one honestly. What IS asserted is that drawing inside a
    // buffering folder still works end to end.
    expect(
      repository
          .requireProject()
          .tracks
          .first
          .cuts
          .first
          .layers
          .folderLayers
          .single
          .blendMode,
      LayerBlendMode.multiply,
    );
  });
}
