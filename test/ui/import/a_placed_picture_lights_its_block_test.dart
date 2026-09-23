import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/import/import_dialog.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_style.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';
import 'package:anicel/src/ui/timeline/timeline_silhouette_painter.dart';

import '../../helpers/solid_png_fixture.dart';
import '../../helpers/temp_dir.dart';

/// F-155 (유저 2026-09-17), three reports of one placement:
/// 「미디어 풀 파일 png를 기존 애니메이션 레이어의 프레임영역에 떨궈서
/// 블록/그림 만들었을때, 그림 존재하는데 블록이 회색임. 그상태에서 코마
/// 늘리니 정상적으로 흰색됬음」 · 「추가로 같은 상황에서 프레임블록 실루엣에
/// 움직이진 않는 개미행렬 실루엣 선이 존재함」 · 「같은 상황에서, 언두
/// 한번하면 … 그 그림이 한번 삭제되는데 블록은 남아있음 … 유령블록이 ui로
/// 남아있는듯」.
///
/// Each is driven the whole way the user went — a pool row dragged onto a
/// row's frame, the place window, Import — and each reads what the
/// timeline actually paints, because that is what they saw.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-f155');
  });

  tearDown(() => deleteTempQuietly(tempDir));

  const cell = 3;

  TimelineRowCellsPainter painterOf(WidgetTester tester, LayerId rowId) =>
      tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<TimelineRowCellsPainter>()
          .firstWhere((painter) => painter.layer.id == rowId);

  /// The app with a picture in its pool, that picture dragged from the pool
  /// onto [cell] of the first animation row and placed through the window.
  /// Returns once the picture is baked into the cel.
  Future<(EditorSessionManager, Layer)> placeByDrag(WidgetTester tester) async {
    final png = (await tester.runAsync(
      () => writeSolidPng(tempDir, 'a.png', rgba: 0xAAAAAAAA),
    ))!;
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          initialProject: createDefaultProject().copyWith(
            mediaAssets: [
              MediaAsset(path: png, name: 'a', kind: MediaAssetKind.image),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The pool ships closed, one rail button away.
    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'rail-group-${EditorWorkspace.railGroupId(right: true, slot: 3)}',
        ),
      ),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final row = session.requireActiveCut.layers.firstWhere(
      (layer) => layer.kind == LayerKind.animation,
    );

    // The cell where the row's own drop target reads it: the target's box
    // starts at the first frame the row lays out.
    final target = find.byKey(
      ValueKey<String>('timeline-layer-asset-drop-${row.id}'),
    );
    final frames = painterOf(tester, row.id).geometry.value;
    final at =
        tester.getTopLeft(target) +
        Offset(
          frames.edgeAt(cell) -
              frames.edgeAt(frames.frameStartIndex) +
              frames.frameCellExtent / 2,
          tester.getSize(target).height / 2,
        );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(ValueKey<String>('media-asset-row-$png'))),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(at);
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter is TimelineSilhouettePainter,
      ),
      findsOneWidget,
      reason: 'premise: the file over the row draws what it would make',
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(ImportDialog), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('import-run-button')));
    for (var tries = 0; tries < 100; tries += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      final landed = session.layerById(row.id)!;
      if (landed.timeline[cell] != null &&
          session.layerStack.celHasContentForLayer(landed, cell)) {
        break;
      }
    }
    await tester.pumpAndSettle();
    expect(
      session.layerStack.celHasContentForLayer(session.layerById(row.id)!, cell),
      isTrue,
      reason: 'premise: the picture is there — 「그림 존재하는데」',
    );
    return (session, row);
  }

  testWidgets('the placed block paints as drawn — not as the empty cel the '
      'drag was showing', (tester) async {
    final (session, row) = await placeByDrag(tester);

    expect(
      painterOf(tester, row.id).resolvedCellStyleFor(cell).background,
      timelineDrawingStartColor,
      reason: '「블록이 회색임」 — the block paints the cel the row holds',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('the placed block wears no outline of the block that was '
      'still to come', (tester) async {
    final (session, _) = await placeByDrag(tester);

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter is TimelineSilhouettePainter,
      ),
      findsNothing,
      reason: '「움직이진 않는 개미행렬 실루엣 선」 — the dashes marked what a '
          'drop WOULD make; it has been made',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('one undo takes the block off the screen with the picture — no '
      'ghost of it stays', (tester) async {
    final (session, row) = await placeByDrag(tester);

    session.undo();
    await tester.pumpAndSettle();

    expect(
      session.layerById(row.id)!.timeline[cell],
      isNull,
      reason: 'premise: the placement was one step, and it is undone',
    );
    expect(
      painterOf(tester, row.id).layer.timeline[cell],
      isNull,
      reason: '「유령블록이 ui로 남아있는듯」 — the row on screen is the row '
          'the project holds',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });
}
