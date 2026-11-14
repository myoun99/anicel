import '../../helpers/a_canvas_standing_on_a_frame.dart';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/canvas_read_source.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/canvas_selection_shape.dart';
import 'package:anicel/src/services/cut_piece_slot.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/rail_group_button.dart';
import '../../helpers/wait_window.dart' show pumpPastTheWaitWindow;
import '../../helpers/surface_rgba_in_place.dart';

/// 🗣️I-163 (유저 2026-11-05): the cut tool's 대상 「표시」 is what is truly
/// seen, the other layers with it · Q1 「다른 이름으로 저장 한 장으로 통일
/// (스포이드도)」 — memo 「잘라내기의 원본삭제는 fx같은 삭제불가능한건
/// 삭제안한다거나 그런식」 · Q2 「보이는 레이어 전부의 그 영역」.
void main() {
  opensTheEnginesScreens();
  const a = LayerId('row-a');
  const b = LayerId('row-b');
  const hidden = LayerId('row-hidden');

  /// Three drawing rows of one cel each — A and B shown, the third's eye
  /// shut — on the default paper (opaque white), the camera's eye shut so
  /// nothing dims the picture round its frame.
  Project fixture() {
    final base = createDefaultProject();
    final track = base.tracks.first;
    final cut = track.cuts.first;
    final row = cut.layers.firstWhere(layerAcceptsBrushInput);
    Layer drawn(LayerId id, {bool visible = true}) => row.copyWith(
      id: id,
      name: id.value,
      isVisible: visible,
      frames: [
        Frame(id: FrameId('${id.value}-0'), duration: 1, strokes: const []),
      ],
      timeline: {
        0: TimelineExposure.drawing(FrameId('${id.value}-0'), length: 1),
      },
    );
    return base.copyWith(
      tracks: [
        track.copyWith(
          cuts: [
            cut.copyWith(
              layers: [
                for (final layer in cut.layers)
                  if (layer.id == row.id) ...[
                    drawn(a),
                    drawn(b),
                    drawn(hidden, visible: false),
                  ] else if (layer.kind == LayerKind.camera)
                    layer.copyWith(isVisible: false)
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
    session.selectLayer(a);
    session.selectFrameIndex(0);
    await tester.pump();
    return session;
  }

  BrushFrameKey celOf(EditorSessionManager session, LayerId row) =>
      session.brushFrameKeyForCut(
        session.requireActiveCut,
        row,
        FrameId('${row.value}-0'),
      );

  /// A red square 10 across with its corner at ([left], [top]) in [row]'s
  /// cel, cel pixels — on the pasteboard where they are negative.
  void square(EditorSessionManager session, LayerId row, int left, int top) {
    final key = celOf(session, row);
    final coordinator = session.pixelEditing.coordinator!;
    final base = coordinator.currentSurfaceOf(key);
    final size = base.tileSize;
    final coord = TileCoord(
      x: (left / size).floor(),
      y: (top / size).floor(),
    );
    final pixels = Uint8List(size * size * 4);
    for (var y = 0; y < 10; y += 1) {
      for (var x = 0; x < 10; x += 1) {
        final at =
            ((top - coord.y * size + y) * size + left - coord.x * size + x) * 4;
        pixels.setRange(at, at + 4, [255, 0, 0, 255]);
      }
    }
    coordinator.restoreSurfaceSnapshot(
      key,
      base.putTiles([
        (
          coord: coord,
          tile: BitmapTile(size: size, pixels: pixels),
        ),
      ]),
    );
  }

  bool drawn(EditorSessionManager session, LayerId row) => session
      .renderCaches
      .brushFrameStore
      .celHasRenderableContent(celOf(session, row));

  /// Whether [row]'s cel has ink at ([x], [y]).
  bool inkAt(EditorSessionManager session, LayerId row, int x, int y) {
    final surface = session.pixelEditing.coordinator!.currentSurfaceOf(
      celOf(session, row),
    );
    return ((surfaceRgbaInPlace(surface, x, y) ?? 0) & 0xFF) != 0;
  }

  int alphaAt(CutPiece piece, int x, int y) =>
      piece.image.rgba[(y * piece.image.width + x) * 4 + 3];

  /// A 「표시」 cut through [outline] — 전체 잘라내기's when null — its
  /// picture worked out ahead, then its step taken; the piece lands in the
  /// slot this returns.
  Future<CutPieceSlot> cutShown(
    WidgetTester tester,
    EditorSessionManager session,
    CanvasSelectionRegion? outline, {
    required bool takeWhatItCuts,
    void Function(CutPieceSlot slot)? betweenAheadAndStep,
  }) async {
    final slot = CutPieceSlot();
    addTearDown(slot.dispose);
    session.pixelVerbs.cutToolHand = slot.hold;
    final cut = outline == null
        ? session.pixelVerbs.cutWhole(
            source: CanvasReadSource.display,
            takeWhatItCuts: takeWhatItCuts,
          )
        : session.pixelVerbs.cutShown(outline, takeWhatItCuts: takeWhatItCuts);
    final ahead = cut.ahead;
    expect(ahead, isNotNull, reason: 'the picture is work ahead of the step');
    await tester.runAsync(() => ahead!((_) {}));
    betweenAheadAndStep?.call(slot);
    cut.step();
    await tester.pump();
    return slot;
  }

  /// The window's tool switched to [tool] reading what is SHOWN, with
  /// 「원본 삭제」 on.
  Future<EditorWorkspace> armShown(WidgetTester tester, CanvasTool tool) async {
    final workspace = tester.widget<EditorWorkspace>(
      find.byType(EditorWorkspace),
    );
    workspace.brushTool!.value = workspace.brushTool!.value.copyWith(
      tool: tool,
      cutSource: CanvasReadSource.display,
      cutDeletesSource: true,
    );
    await tester.pumpAndSettle();
    return workspace;
  }

  /// What the press put up, waited out: the wait window the shown picture
  /// is worked out behind (F-53 · F-551).
  Future<void> waitOutTheShownPicture(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('work-progress-dialog')),
      findsOneWidget,
      reason: 'the shown picture is work ahead of the step',
    );
    await pumpPastTheWaitWindow(tester);
    session.playbackRig.prerenderScheduler.cancel();
  }

  testWidgets('「실행」 under 「표시」 takes what is shown off every shown row, '
      'behind the wait window, into the window\'s own hand', (tester) async {
    final session = await pump(tester);
    square(session, a, 10, 10);
    square(session, b, 100, 10);
    square(session, hidden, 50, 50);
    final workspace = await armShown(tester, CanvasTool.cutWhole);
    final run = find.byKey(const ValueKey<String>('cut-whole-run-button'));
    // The tool settings ship closed, and they scroll.
    await pressToolSettingsButton(tester);
    await tester.pumpAndSettle();
    await tester.ensureVisible(run);
    await tester.pumpAndSettle();

    await tester.tap(run);
    await waitOutTheShownPicture(tester, session);

    expect(drawn(session, a), isFalse);
    expect(drawn(session, b), isFalse);
    expect(drawn(session, hidden), isTrue, reason: 'not shown, not cut');
    expect(
      workspace.brushTool!.value.tool,
      CanvasTool.cutStamp,
      reason: 'the window\'s own hand took it, and the stamp follows',
    );
  });

  testWidgets('an outline drawn on the canvas under 「표시」 takes what it '
      'holds off every shown row, behind the wait window', (tester) async {
    final session = await pump(tester);
    square(session, a, 10, 10);
    square(session, b, 100, 10);
    square(session, hidden, 50, 50);
    final workspace = await armShown(tester, CanvasTool.cut);
    // Over the whole view, from a pixel in — the canvas is fitted to it, a
    // screen pixel some three of the canvas's, and the squares are ten in.
    final layer = find.byKey(const ValueKey<String>('canvas-selection-layer'));
    final from = tester.getTopLeft(layer) + const Offset(1, 1);
    final to = tester.getBottomRight(layer) - const Offset(4, 4);

    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryButton,
    );
    await tester.pump();
    await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await waitOutTheShownPicture(tester, session);

    expect(drawn(session, a), isFalse);
    expect(drawn(session, b), isFalse);
    expect(drawn(session, hidden), isTrue, reason: 'not shown, not cut');
    expect(workspace.brushTool!.value.tool, CanvasTool.cutStamp);
  });

  testWidgets('the whole of what is shown: every shown row in one piece, '
      'where it stands on the canvas — no paper, no hidden row', (
    tester,
  ) async {
    final session = await pump(tester);
    square(session, a, 10, 10);
    square(session, b, 100, 10);
    square(session, hidden, 50, 50);

    final slot = await cutShown(tester, session, null, takeWhatItCuts: false);

    final piece = slot.piece!;
    expect(
      (piece.originLeft, piece.originTop),
      (10, 10),
      reason: 'the picture\'s pixels are the canvas\'s',
    );
    expect(
      piece.image.width,
      lessThan(110),
      reason: 'A and B, 10…110 — the paper would have made it the canvas',
    );
    expect(
      piece.image.height,
      lessThan(40),
      reason: 'the hidden row\'s square, down at 50, is not shown',
    );
    expect(alphaAt(piece, 0, 0), 255, reason: 'A');
    expect(alphaAt(piece, 95, 5), 255, reason: 'B, from the other row');
    expect(alphaAt(piece, 50, 5), 0, reason: 'between them, nothing');
    expect(drawn(session, a) && drawn(session, b), isTrue, reason: 'a copy');
  });

  testWidgets('「원본 삭제」 takes it off every shown row as one undo — at the '
      'step, not while the picture is worked out — and leaves the row whose '
      'eye is shut', (tester) async {
    final session = await pump(tester);
    square(session, a, 10, 10);
    square(session, b, 100, 10);
    square(session, hidden, 50, 50);

    final slot = await cutShown(
      tester,
      session,
      null,
      takeWhatItCuts: true,
      betweenAheadAndStep: (slot) {
        expect(slot.piece, isNull, reason: 'the hand waits for the step');
        expect(drawn(session, a) && drawn(session, b), isTrue);
      },
    );

    expect(slot.piece, isNotNull);
    expect(drawn(session, a), isFalse);
    expect(drawn(session, b), isFalse);
    expect(drawn(session, hidden), isTrue, reason: 'not shown, not cut');

    session.historyManager.undo();
    await tester.pump();
    expect(
      drawn(session, a) && drawn(session, b),
      isTrue,
      reason: 'one undo for every row',
    );
  });

  testWidgets('through an outline it takes what the outline holds of every '
      'shown row — and only that leaves', (tester) async {
    final session = await pump(tester);
    square(session, a, 10, 10);
    square(session, b, 100, 10);

    final slot = await cutShown(
      tester,
      session,
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 0, top: 0, right: 50, bottom: 50),
      ),
      takeWhatItCuts: true,
    );

    final piece = slot.piece!;
    expect((piece.originLeft, piece.originTop), (0, 0));
    expect(alphaAt(piece, 15, 15), 255, reason: 'A, inside the outline');
    expect(piece.image.width, lessThan(100), reason: 'B is outside it');
    expect(drawn(session, a), isFalse);
    expect(drawn(session, b), isTrue, reason: 'outside the outline');
  });

  testWidgets('an outline past the canvas is cut to it, as the picture is: '
      'ink on the pasteboard was not taken, so it does not leave', (
    tester,
  ) async {
    final session = await pump(tester);
    square(session, a, 10, 10);
    square(session, a, -15, -15);

    final slot = await cutShown(
      tester,
      session,
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: -50, top: -50, right: 30, bottom: 30),
      ),
      takeWhatItCuts: true,
    );

    final piece = slot.piece!;
    expect(
      (piece.originLeft, piece.originTop),
      (0, 0),
      reason: 'the picture starts at the canvas\'s corner',
    );
    expect(alphaAt(piece, 15, 15), 255);
    expect(inkAt(session, a, 15, 15), isFalse, reason: 'taken, so gone');
    expect(
      inkAt(session, a, -10, -10),
      isTrue,
      reason: 'the pasteboard square stays — it was never in the piece',
    );
  });
}
