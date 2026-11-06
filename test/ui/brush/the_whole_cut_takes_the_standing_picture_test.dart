import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/canvas_read_source.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/cut_piece_slot.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/paint_tool_state_notifier.dart';
import 'package:anicel/src/ui/brush/tool_library_panel.dart';
import 'package:anicel/src/ui/brush/tool_press.dart';
import 'package:anicel/src/ui/brush/transform_tool_options.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/cursor_notice.dart';

import '../../helpers/rail_group_button.dart';

/// 🗣️I-28 (유저 2026-09-30): 「잘라내기 툴의 도구 라이브러리에 전체 잘라내기
/// 신설. 내용은 화면의 전체 그림을 잘라냄」 — I-28-Q1 「지금 서 있는 셀의 그림
/// 전체」 (「잘라내기 도구를 화면전체로 한거랑 똑같은 결과」). ↩️I-28-Q2 「누르는
/// 순간 실행」 until I-163 (유저 2026-11-05): the tile arms, and 「실행」 in
/// the tool settings runs it with the options above it.
void main() {
  /// 전체 잘라내기 under 「레이어」: the cel's own read, with no work ahead
  /// of it — the step is the press.
  void cutWhole(EditorSessionManager session, {required bool takeWhatItCuts}) {
    final cut = session.pixelVerbs.cutWhole(
      source: CanvasReadSource.layer,
      takeWhatItCuts: takeWhatItCuts,
    );
    expect(cut.ahead, isNull, reason: 'the cel\'s own read needs none');
    cut.step();
  }

  Project fixture() {
    final base = createDefaultProject();
    final track = base.tracks.first;
    final cut = track.cuts.first;
    final row = cut.layers.firstWhere(layerAcceptsBrushInput);
    return base.copyWith(
      tracks: [
        track.copyWith(
          cuts: [
            cut.copyWith(
              layers: [
                for (final layer in cut.layers)
                  if (layer.id == row.id)
                    layer.copyWith(
                      frames: [
                        for (final id in ['c0', 'c1'])
                          Frame(
                            id: FrameId(id),
                            duration: 1,
                            strokes: const [],
                          ),
                      ],
                      timeline: {
                        0: const TimelineExposure.drawing(
                          FrameId('c0'),
                          length: 1,
                        ),
                        1: const TimelineExposure.drawing(
                          FrameId('c1'),
                          length: 1,
                        ),
                      },
                    )
                  else
                    layer,
              ],
            ),
          ],
        ),
      ],
    );
  }

  Future<EditorSessionManager> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: fixture())),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    session.selectLayer(
      session.layers.firstWhere((l) => l.frames.length == 2).id,
    );
    session.selectFrameIndex(0);
    await tester.pump();
    return session;
  }

  /// Two red squares on c0 — one at (10, 10), one at (100, 10).
  void inkTwoSquares(EditorSessionManager session) {
    final layer = session.layers.firstWhere((l) => l.frames.length == 2);
    final key = session.brushFrameKeyForCut(
      session.requireActiveCut,
      layer.id,
      const FrameId('c0'),
    );
    final coordinator = session.pixelEditing.coordinator!;
    final base = coordinator.currentSurfaceOf(key);
    final size = base.tileSize;
    final pixels = Uint8List(size * size * 4);
    for (final left in [10, 100]) {
      for (var y = 10; y < 20; y += 1) {
        for (var x = left; x < left + 10; x += 1) {
          pixels.setRange((y * size + x) * 4, (y * size + x) * 4 + 4, [
            255,
            0,
            0,
            255,
          ]);
        }
      }
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

  testWidgets('the tile ARMS — it cuts nothing at the press, and lights as '
      'the tool in hand (I-163)', (tester) async {
    final tool = PaintToolStateNotifier(
      BrushToolState.defaults.copyWith(tool: CanvasTool.cut),
    );
    addTearDown(tool.dispose);
    final transform = ValueNotifier(TransformToolOptions.defaults);
    addTearDown(transform.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<BrushToolState>(
            valueListenable: tool,
            builder: (context, state, _) => ToolLibraryPanel(
              tool: state.tool,
              onPress: (press) =>
                  pressTool(press, tool: tool, transform: transform),
              brushLibrary: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('sub-tool-cut-whole')));
    await tester.pump();

    expect(tool.value.tool, CanvasTool.cutWhole);
    expect(
      canvasToolRailGroup(tool.value.tool),
      CanvasTool.cut,
      reason: 'a sub-tool of the cut, like the stamp',
    );
  });

  testWidgets('「실행」 in the tool settings runs it, with the 대상 and the '
      '「원본 삭제」 the tool holds at the press', (tester) async {
    final session = await pump(tester);
    inkTwoSquares(session);
    final workspace = tester.widget<EditorWorkspace>(
      find.byType(EditorWorkspace),
    );
    final layer = session.layers.firstWhere((l) => l.frames.length == 2);
    final key = session.brushFrameKeyForCut(
      session.requireActiveCut,
      layer.id,
      const FrameId('c0'),
    );
    final run = find.byKey(const ValueKey<String>('cut-whole-run-button'));

    workspace.brushTool!.value = workspace.brushTool!.value.copyWith(
      tool: CanvasTool.cutWhole,
      cutSource: CanvasReadSource.layer,
      cutDeletesSource: true,
    );
    await tester.pumpAndSettle();
    // The tool settings ship closed.
    await pressToolSettingsButton(tester);
    await tester.pumpAndSettle();
    expect(run, findsOneWidget);
    // The settings scroll: what is pressed is brought into view first.
    await tester.ensureVisible(run);
    await tester.pumpAndSettle();
    await tester.tap(run);
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('work-progress-dialog')),
      findsNothing,
      reason: 'the cel\'s own read is one block, with no work ahead',
    );

    expect(
      session.renderCaches.brushFrameStore.celHasRenderableContent(key),
      isFalse,
      reason: '「원본 삭제」 on: the picture left the cel',
    );
    expect(
      workspace.brushTool!.value.tool,
      CanvasTool.cutStamp,
      reason: 'the window\'s own hand took it, and the stamp follows',
    );
  });

  // 🗣️I-90 (유저 2026-10-10): 「잘라내기시 해당 그림 없애는것」.
  testWidgets('with 「원본 삭제」 the picture goes into the hand AND off the '
      'cel — one undo puts it back, and the hand keeps it', (tester) async {
    final session = await pump(tester);
    inkTwoSquares(session);
    final slot = CutPieceSlot();
    addTearDown(slot.dispose);
    session.pixelVerbs.cutToolHand = slot.hold;
    final layer = session.layers.firstWhere((l) => l.frames.length == 2);
    final key = session.brushFrameKeyForCut(
      session.requireActiveCut,
      layer.id,
      const FrameId('c0'),
    );
    final store = session.renderCaches.brushFrameStore;

    // CONTROL: off, the cel keeps its picture.
    cutWhole(session, takeWhatItCuts: false);
    expect(slot.piece, isNotNull);
    expect(store.celHasRenderableContent(key), isTrue, reason: 'a copy');

    cutWhole(session, takeWhatItCuts: true);
    await tester.pump();
    final piece = slot.piece!;
    expect(
      piece.image.width,
      greaterThanOrEqualTo(100),
      reason: 'both squares in the hand',
    );
    expect(
      store.celHasRenderableContent(key),
      isFalse,
      reason: 'and nothing of them left on the cel',
    );

    session.historyManager.undo();
    await tester.pump();
    expect(store.celHasRenderableContent(key), isTrue, reason: 'one undo');
    expect(slot.piece, same(piece), reason: 'the hand is not history');
  });

  testWidgets('it takes the standing cel\'s WHOLE picture — the marquee is '
      'not read — and the stamp follows', (tester) async {
    final session = await pump(tester);
    inkTwoSquares(session);
    // A marquee over the first square alone: the cut tool cuts through its
    // own outline, never the selection's.
    session.pixelVerbs.pixelVerbCanvas = () => (
      region: CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 0, top: 0, right: 30, bottom: 30),
      ),
      argb: 0xFF000000,
      mask: SelectionMaskOptions.none,
    );
    final slot = CutPieceSlot();
    addTearDown(slot.dispose);
    final published = session.pixelVerbs.cutToolHand;
    expect(published, isNotNull, reason: 'the workspace hands its slot in');
    session.pixelVerbs.cutToolHand = slot.hold;

    cutWhole(session, takeWhatItCuts: false);

    final piece = slot.piece!;
    expect((piece.originLeft, piece.originTop), (10, 10));
    expect(
      piece.image.width,
      greaterThanOrEqualTo(100),
      reason: 'both squares, 10…110 — the whole picture',
    );

    // The real hand: the window's slot, which arms the stamp.
    session.pixelVerbs.cutToolHand = published;
    cutWhole(session, takeWhatItCuts: false);
    await tester.pump();
    final workspace = tester.widget<EditorWorkspace>(
      find.byType(EditorWorkspace),
    );
    expect(workspace.brushTool!.value.tool, CanvasTool.cutStamp);
  });

  // 🗣️F-254 (유저 2026-10-01): 「전체 잘라내기, 지금 작동안하는 그림없는
  // 곳에선 아무메시지 안뜨는데 뜨도록. 내용은 잘라낼 대상이 존재하지
  // 않습니다.」
  testWidgets('a cel with no drawing leaves the hand as it was — and says '
      'there is nothing to cut', (tester) async {
    addTearDown(cursorNotices.clear);
    final session = await pump(tester);
    inkTwoSquares(session);
    final slot = CutPieceSlot();
    addTearDown(slot.dispose);
    session.pixelVerbs.cutToolHand = slot.hold;
    cutWhole(session, takeWhatItCuts: false);
    final held = slot.piece;
    expect(held, isNotNull);
    expect(
      cursorNotices.message,
      isNull,
      reason: 'a cut that took a picture has nothing to explain',
    );

    session.selectFrameIndex(1);
    await tester.pump();
    cutWhole(session, takeWhatItCuts: false);

    expect(
      slot.piece,
      same(held),
      reason: 'the slot outlives frames, cuts and projects — one press on '
          'an empty cel must not throw it away',
    );
    expect(cursorNotices.message, AppText.strings.noticeNothingToCut);
    expect(
      AppStrings.of(AppLanguage.ko).noticeNothingToCut,
      '잘라낼 대상이 존재하지 않습니다',
      reason: '유저가 준 문장 그대로',
    );
  });
}
