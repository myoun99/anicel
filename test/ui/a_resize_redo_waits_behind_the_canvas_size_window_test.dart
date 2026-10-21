import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_resize_anchor.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_command_actions.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// 🗣️a-resize-redo-moves-every-cel-on-the-ui-thread-Q1 (유저 2026-10-22:
/// 「다시 하기도 대기 창 뒤에서 옮긴다」 — 「크기를 바꿀 때와 같은 「캔버스
/// 크기」 대기 창이 뜨고, 작업자가 옮깁니다」): a resize done again — by the
/// rail's ↷, as by every door that opens the one redo — and a 겸용 변경 that
/// takes the other cut's canvas stand behind the window a resize stands
/// behind, and their pictures move ahead of the step.
void main() {
  final window = find.byKey(const ValueKey<String>('resize-progress-dialog'));

  Future<EditorSessionManager> openApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    return tester
        .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
        .session;
  }

  /// A picture drawn on [cutId], in tiles of 8: a move about a centre two
  /// pixels away is no whole tile.
  BrushFrameKey draw(EditorSessionManager session, CutId cutId) {
    final key = BrushFrameKey(
      projectId: const ProjectId('p'),
      trackId: const TrackId('t'),
      cutId: cutId,
      layerId: const LayerId('l'),
      frameId: const FrameId('drawn'),
    );
    final cut = session.activeTrack.cuts.firstWhere((cut) => cut.id == cutId);
    session.renderCaches.brushFrameStore.storeBakedSurface(
      key,
      BitmapSurface(canvasSize: cut.canvasSize, tileSize: 8).putTiles([
        (
          coord: TileCoord(x: 1, y: 1),
          tile: BitmapTile(size: 8, pixels: Uint8List(256)..fillRange(0, 256, 9)),
        ),
      ]),
    );
    return key;
  }

  /// The window up over the step, under the canvas size's name, the step
  /// landed behind it — and the window gone once its done line has lingered.
  Future<void> expectBehindTheWindow(
    WidgetTester tester,
    bool Function() landed,
  ) async {
    await tester.pump();
    expect(window, findsOneWidget);
    expect(
      find.descendant(
        of: window,
        matching: find.text(AppText.strings.canvasSizeTitle),
      ),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(landed(), isTrue);
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();
    expect(window, findsNothing);
  }

  testWidgets('🎯the rail\'s ↷ runs a resize again behind the window, its '
      'pictures moved ahead; the ↶ does not wait', (tester) async {
    final session = await openApp(tester);
    final store = session.renderCaches.brushFrameStore;
    draw(session, session.requireActiveCut.id);
    final before = session.requireActiveCut.canvasSize;
    final resized = CanvasSize(
      width: before.width - 2,
      height: before.height - 2,
    );
    session.cutVerbs.resizeActiveCutCanvas(
      resized,
      anchor: CanvasResizeAnchor.center,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('undo-button')));
    await tester.pump();
    expect(window, findsNothing, reason: 'an undo puts the pictures back');
    expect(session.requireActiveCut.canvasSize, before);
    await tester.pumpAndSettle();

    final movedHere = store.celsMovedHere;
    await tester.tap(find.byKey(const ValueKey<String>('redo-button')));
    await expectBehindTheWindow(
      tester,
      () => session.requireActiveCut.canvasSize == resized,
    );
    expect(store.celsMovedHere, movedHere, reason: 'moved ahead, not here');
  });

  testWidgets('a 겸용 변경 that takes the other cut\'s canvas stands behind '
      'the same window', (tester) async {
    final session = await openApp(tester);
    final store = session.renderCaches.brushFrameStore;
    session.cutVerbs.duplicateActiveCut();
    await tester.pumpAndSettle();
    final origin = session.requireActiveCut;
    final target = session.activeTrack.cuts.firstWhere(
      (cut) => cut.id != origin.id,
    );
    session.cutCommandCoordinator.resizeCutCanvas(
      cutId: target.id,
      canvasSize: CanvasSize(
        width: origin.canvasSize.width - 2,
        height: origin.canvasSize.height - 2,
      ),
    );
    draw(session, target.id);
    await tester.pumpAndSettle();

    final movedHere = store.celsMovedHere;
    final context = tester.element(find.byType(EditorCanvasArea));
    final shown = showConvertActiveCutToLinked(context, session);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('convert-linked-cut-confirm-button')),
    );
    await expectBehindTheWindow(
      tester,
      () =>
          session.activeTrack.cuts
              .firstWhere((cut) => cut.id == target.id)
              .canvasSize ==
          origin.canvasSize,
    );
    await shown;
    expect(store.celsMovedHere, movedHere, reason: 'moved ahead, not here');
  });

  testWidgets('a 겸용 변경 whose canvases agree moves nothing, and does not '
      'wait', (tester) async {
    final session = await openApp(tester);
    session.cutVerbs.duplicateActiveCut();
    await tester.pumpAndSettle();
    final origin = session.requireActiveCut;
    final shown = showConvertActiveCutToLinked(
      tester.element(find.byType(EditorCanvasArea)),
      session,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('convert-linked-cut-confirm-button')),
    );
    await tester.pump();
    expect(window, findsNothing);
    await tester.pumpAndSettle();
    await shown;
    expect(
      session.layerVerbs.isLayerLinked(session.activeLayer!.id),
      isTrue,
      reason: 'converted all the same',
    );
    expect(session.requireActiveCut.id, origin.id);
  });
}
