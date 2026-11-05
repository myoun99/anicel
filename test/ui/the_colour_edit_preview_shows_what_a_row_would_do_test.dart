import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pixel_verb_settings.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/services/canvas_color_sampler.dart';
import 'package:anicel/src/services/cel_pixel_overwrite.dart'
    show CelPixelVerb;
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart'
    show LiveRows;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart'
    show EditorActionIds;
import 'package:anicel/src/ui/widgets/boolean_dot.dart';

import '../helpers/wait_window.dart' show windowBehind;

/// 🗣️I-164 (유저 2026-11-05): 「색변환의 수치 지정해서 하는 버튼들. 삭제나
/// 남기기나 2치화. 그런거는 프리뷰버튼 두도록. 그러고 수치 막대는 최대한
/// 컴팩트하게하고 그 막대 오른쪽에 두도록. 누르면 프리뷰로 보임. 프리뷰는
/// 한번에 하나만 활성화 가능하고, 그 색 편집 앵커창 나가면 사라짐. 즉
/// 체크해제됨.」
void main() {
  const a = LayerId('row-a');
  const b = LayerId('row-b');
  const knobs = [
    (
      bar: 'shared-binarize-cut',
      ring: '${EditorActionIds.editBinarize}-preview',
    ),
    (
      bar: 'shared-delete-colour-tolerance',
      ring: '${EditorActionIds.editDeleteColour}-preview',
    ),
    (
      bar: 'shared-keep-colour-tolerance',
      ring: '${EditorActionIds.editKeepColour}-preview',
    ),
  ];
  const binarizeRing = ValueKey<String>(
    '${EditorActionIds.editBinarize}-preview',
  );
  const keepRing = ValueKey<String>(
    '${EditorActionIds.editKeepColour}-preview',
  );
  const allShown = TimelineFrameRangeSelection(
    layerId: a,
    layerIds: [a, b],
    startIndex: 0,
    endIndexExclusive: 1,
  );

  /// Two drawing rows, a cel at each of the first two frames.
  Project fixture() {
    final base = createDefaultProject();
    final track = base.tracks.first;
    final cut = track.cuts.first;
    final row = cut.layers.firstWhere(layerAcceptsBrushInput);
    Layer drawn(LayerId id) => row.copyWith(
      id: id,
      name: id.value,
      frames: [
        for (var at = 0; at < 2; at += 1)
          Frame(id: FrameId('${id.value}-$at'), duration: 1, strokes: const []),
      ],
      timeline: {
        for (var at = 0; at < 2; at += 1)
          at: TimelineExposure.drawing(FrameId('${id.value}-$at'), length: 1),
      },
    );
    return base.copyWith(
      tracks: [
        track.copyWith(
          cuts: [
            cut.copyWith(
              layers: [
                for (final layer in cut.layers)
                  if (layer.id == row.id) ...[drawn(a), drawn(b)] else layer,
              ],
            ),
          ],
        ),
      ],
    );
  }

  BrushFrameKey celOf(
    EditorSessionManager session,
    LayerId row, {
    int at = 0,
  }) => session.brushFrameKeyForCut(
    session.requireActiveCut,
    row,
    FrameId('${row.value}-$at'),
  );

  /// [row]'s cel at frame [at] inked at [alpha] over its first tile — under
  /// 2치화's cut at rest, so its preview empties it.
  void ink(
    EditorSessionManager session,
    LayerId row, {
    int alpha = 100,
    int at = 0,
  }) {
    final key = celOf(session, row, at: at);
    final coordinator = session.pixelEditing.coordinator!;
    final base = coordinator.currentSurfaceOf(key);
    final size = base.tileSize;
    final pixels = Uint8List(size * size * 4);
    for (var at = 3; at < pixels.length; at += 4) {
      pixels[at] = alpha;
    }
    coordinator.restoreSurfaceSnapshot(
      key,
      base.putTiles([
        (
          coord: TileCoord(x: 0, y: 0),
          tile: BitmapTile(size: size, pixels: pixels),
        ),
      ]),
    );
  }

  int alphaOf(BitmapSurface surface) =>
      (surfacePixelRgba(surface, 1, 1) ?? 0) & 0xFF;

  int storedAlpha(EditorSessionManager session, LayerId row) => alphaOf(
    session.pixelEditing.coordinator!.currentSurfaceOf(celOf(session, row)),
  );

  /// What the canvas draws live.
  LiveRows live(WidgetTester tester) => tester
      .widget<FramePictureView>(find.byType(FramePictureView).first)
      .live!;

  bool ringOn(WidgetTester tester, Key ring) => tester
      .widget<BooleanDotButton>(
        find.ancestor(
          of: find.byKey(ring),
          matching: find.byType(BooleanDotButton),
        ),
      )
      .value;

  /// Stands on row A's first cel with both rows' first cels inked and
  /// [range] (both of them, by default), and opens the 색 편집 list.
  Future<EditorSessionManager> openTheList(
    WidgetTester tester, {
    TimelineFrameRangeSelection range = allShown,
  }) async {
    addTearDown(
      () => PixelVerbSettings.settings.value = const PixelVerbSettings(),
    );
    await tester.binding.setSurfaceSize(const Size(1700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: fixture())),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    session.selectLayer(a);
    session.selectFrameIndex(0);
    ink(session, a);
    ink(session, b);
    session.frameRangeSelection.value = range;
    await tester.pumpAndSettle();
    final head = find.byKey(
      const ValueKey<String>('shared-colour-edit-button'),
    );
    await tester.ensureVisible(head);
    await tester.pumpAndSettle();
    await tester.tap(head);
    await tester.pumpAndSettle();
    return session;
  }

  testWidgets('the rows a number runs — 2치화 · 색 삭제 · 색 유지 — carry a '
      'preview right of a short bar, and no other row does', (tester) async {
    await openTheList(tester);

    for (final knob in knobs) {
      final bar = find.byKey(ValueKey<String>(knob.bar));
      final ring = find.byKey(ValueKey<String>(knob.ring));
      expect(ring, findsOneWidget, reason: knob.ring);
      expect(
        tester.getRect(ring).left,
        greaterThanOrEqualTo(tester.getRect(bar).right),
        reason: '${knob.bar}: 「그 막대 오른쪽에」',
      );
      expect(
        tester.getSize(bar).width,
        lessThanOrEqualTo(56),
        reason: '${knob.bar}: 「수치 막대는 최대한 컴팩트하게」',
      );
    }
    expect(
      find.byType(BooleanDotButton),
      findsNWidgets(knobs.length),
      reason: 'a row with no number has nothing to preview',
    );
  });

  testWidgets('a preview shows every shown cel as the row would leave it, '
      'follows its knob and writes nothing — and one is on at a time', (
    tester,
  ) async {
    final session = await openTheList(tester);
    final preview = session.pixelVerbPreview;

    await tester.tap(find.byKey(binarizeRing));
    await tester.pumpAndSettle();

    expect(preview.verb, CelPixelVerb.binarize);
    expect(ringOn(tester, binarizeRing), isTrue, reason: 'its ring is lit');
    final cels = preview.cels();
    expect(cels.keys, {celOf(session, a), celOf(session, b)});
    expect(
      alphaOf(live(tester).activeSurfacePainter!.surface),
      0,
      reason: 'the row stood on, by its painter: under the cut, emptied',
    );
    expect(
      live(tester).liftedRows.keys,
      [celOf(session, b)],
      reason: 'A is its painter\'s, and drawn there only',
    );
    final other = live(tester).liftedRows[celOf(session, b)];
    expect(other?.float, isNull, reason: 'B in its own slot, nothing over it');
    expect(alphaOf(other!.surface), 0, reason: 'B too');
    expect((storedAlpha(session, a), storedAlpha(session, b)), (100, 100));
    expect(session.canUndo, isFalse, reason: 'nothing ran');
    expect(
      find.byKey(const ValueKey<String>('shared-binarize-button')),
      findsOneWidget,
      reason: 'the list stays open',
    );

    PixelVerbSettings.settings.value = PixelVerbSettings.settings.value
        .copyWith(binarizeThreshold: 100);
    await tester.pumpAndSettle();
    expect(
      alphaOf(live(tester).activeSurfacePainter!.surface),
      255,
      reason: 'at its cut now, 2치화 fills it — the preview follows the knob',
    );

    await tester.tap(find.byKey(keepRing));
    await tester.pumpAndSettle();
    expect(
      preview.verb,
      CelPixelVerb.keepColour,
      reason: '「프리뷰는 한번에 하나만」',
    );
    expect(
      ringOn(tester, binarizeRing),
      isFalse,
      reason: '2치화\'s ring went off',
    );

    await tester.tap(find.byKey(keepRing));
    await tester.pumpAndSettle();
    expect(preview.verb, isNull, reason: 'a lit ring pressed turns it off');
  });

  testWidgets('a cel written while its preview is on is previewed as it now '
      'stands — the pictures follow the cels, whoever writes them', (
    tester,
  ) async {
    final session = await openTheList(tester);
    await tester.tap(find.byKey(binarizeRing));
    await tester.pumpAndSettle();
    expect(
      alphaOf(live(tester).activeSurfacePainter!.surface),
      0,
      reason: '⛔premise: under the cut, emptied',
    );

    ink(session, a, alpha: 200);
    await tester.pumpAndSettle();

    expect(
      alphaOf(live(tester).activeSurfacePainter!.surface),
      255,
      reason: 'over the cut now, 2치화 fills it',
    );
    expect(session.canUndo, isFalse, reason: 'written past the history');
  });

  testWidgets('a cel of the range the canvas does not show is left out of '
      'the preview — the row still reaches it', (tester) async {
    final session = await openTheList(
      tester,
      range: const TimelineFrameRangeSelection(
        layerId: a,
        layerIds: [a],
        startIndex: 0,
        endIndexExclusive: 2,
      ),
    );
    ink(session, a, at: 1);
    expect(
      session.pixelVerbs.pixelVerbCellKeys(),
      containsAll([celOf(session, a), celOf(session, a, at: 1)]),
      reason: '⛔premise: the row reaches both of A\'s cels',
    );

    await tester.tap(find.byKey(binarizeRing));
    await tester.pumpAndSettle();

    expect(session.pixelVerbPreview.cels().keys, [celOf(session, a)]);
  });

  testWidgets('where the row would not run, there is nothing to show', (
    tester,
  ) async {
    final session = await openTheList(tester);
    expect(
      session.pixelVerbs.previewOf(CelPixelVerb.binarize),
      isNotEmpty,
      reason: '⛔premise',
    );

    session.brushInputActive.value = true;

    expect(session.pixelVerbs.canRunPixelVerb, isFalse, reason: '⛔premise');
    expect(session.pixelVerbs.previewOf(CelPixelVerb.binarize), isEmpty);
    session.brushInputActive.value = false;
  });

  testWidgets('leaving the list ends its preview: the canvas draws the cels '
      'again, and their pictures are let go', (tester) async {
    final session = await openTheList(tester);
    final preview = session.pixelVerbPreview;
    await tester.tap(find.byKey(binarizeRing));
    await tester.pumpAndSettle();
    expect(
      session.renderCaches.brushFrameStore.reclaimableViewCount,
      1,
      reason: '⛔premise: its pictures are held',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(binarizeRing), findsNothing, reason: 'the list closed');
    expect(preview.verb, isNull, reason: '「즉 체크해제됨」');
    expect(alphaOf(live(tester).activeSurfacePainter!.surface), 100);
    expect(live(tester).liftedRows, isEmpty);
    expect(session.renderCaches.brushFrameStore.reclaimableViewCount, 0);
  });

  testWidgets('choosing the row lands what it showed, and the preview ends '
      'where it lands — behind the wait window over two blocks', (
    tester,
  ) async {
    final session = await openTheList(tester);
    final preview = session.pixelVerbPreview;
    await tester.tap(find.byKey(binarizeRing));
    await tester.pumpAndSettle();
    CelPixelVerb? atTheLanding;
    void landed() => atTheLanding ??= preview.verb;
    session.historyManager.addListener(landed);
    addTearDown(() => session.historyManager.removeListener(landed));

    final window = await windowBehind(
      tester,
      () => tester.tap(
        find.byKey(const ValueKey<String>('shared-binarize-button')),
      ),
    );

    expect(window, isNotNull, reason: '⛔premise: two blocks, F-566');
    expect(
      atTheLanding,
      CelPixelVerb.binarize,
      reason: 'still shown as the pixels landed — no frame of the cels as '
          'they were between the list closing and the step',
    );
    expect(preview.verb, isNull);
    expect((storedAlpha(session, a), storedAlpha(session, b)), (0, 0));
    expect(alphaOf(live(tester).activeSurfacePainter!.surface), 0);
    session.playbackRig.prerenderScheduler.cancel();
  });
}
