import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_tool.dart' show CelTextHold;
import 'package:anicel/src/ui/session/text_clipboard.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';

import '../../../helpers/app_icon_button_probe.dart';
import '../../../helpers/cel_text_tool_harness.dart';
import '../../../helpers/key_chords.dart';

/// I-101 ② (유저 2026-10-15): 「텍스트 복사/붙여넣기. 텍스트를 선택한
/// 상태(변형박스로 변한 상태)에서 복사 가능. 다른 대응가능한 곳에
/// 붙여넣기로 붙여넣기」 — through the app's own keys and the shared pill.
void main() {
  /// 'hi' typed at the middle of the canvas and held by its BOX: Escape
  /// stops the typing and keeps the text in hand (R9-rest).
  Future<void> hiHeldByItsBox(WidgetTester tester, {Project? project}) async {
    await pumpTextToolApp(
      tester,
      project: project ?? textToolProject(drawings: 2),
    );
    await takeTextTool(tester);
    final c = canvasPixelInView(tester);
    await clickAt(tester, c.dx, c.dy);
    await typeText(tester, 'hi');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFrames(tester);
    expect(textToolOf(tester).hold, CelTextHold.box, reason: '⛔fixture');
  }

  TimelineToolbarPanelContext pill(WidgetTester tester) =>
      TimelineToolbarPanelContext(sessionOf(tester));

  /// The first drawing at 0, the second HELD at 1 and 2 — one cel, two
  /// frames — and 3 with no cel at all.
  Project secondHeldTwice() {
    final project = textToolProject(drawings: 2);
    final track = project.tracks.single;
    final cut = track.cuts.single;
    final layer = cut.layers.single;
    return project.copyWith(
      tracks: [
        track.copyWith(
          cuts: [
            cut.copyWith(
              layers: [
                layer.copyWith(
                  timeline: {
                    0: const TimelineExposure.drawing(
                      textToolFrameId,
                      length: 1,
                    ),
                    1: const TimelineExposure.drawing(
                      textToolSecondFrameId,
                      length: 2,
                    ),
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  const twin = LayerId('text-tool-twin');

  /// [textToolProject]'s row and a TWIN beside it, the same drawings — and
  /// with [onePicture] ONE picture: the two a link group, as a 겸용 pair's
  /// rows are.
  Project twoRows({bool onePicture = false}) {
    final project = textToolProject(drawings: 2);
    final track = project.tracks.single;
    final cut = track.cuts.single;
    final row = cut.layers.single;
    return project.copyWith(
      tracks: [
        track.copyWith(
          cuts: [
            cut.copyWith(
              layers: [row, row.copyWith(id: twin, name: 'Twin')],
            ),
          ],
        ),
      ],
      linkRegistry: LayerLinkRegistry(
        groups: [
          if (onePicture)
            LayerLinkGroup(
              id: 'twin',
              members: [
                for (final id in [textToolLayerId, twin])
                  LayerLinkMember(
                    trackId: track.id,
                    cutId: cut.id,
                    layerId: id,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  testWidgets('🎯Ctrl+C takes the text held by its box, and Ctrl+V on '
      'another frame sets it on that cel as it was shown, where it stood — '
      'one undo', (tester) async {
    await hiHeldByItsBox(tester);
    await pressCtrl(tester, LogicalKeyboardKey.keyC);
    sessionOf(tester).selectFrameIndex(1);
    await pumpFrames(tester);
    final copied = celOf(tester).texts.single;
    final history = sessionOf(tester).historyManager;
    final steps = history.undoCount;

    await pressCtrl(tester, LogicalKeyboardKey.keyV);
    await pumpFrames(tester);

    final pasted = celOf(tester, textToolSecondKey).texts.single;
    expect(pasted.content, copied.content);
    expect(pasted.plate, copied.plate);
    expect(celOf(tester).texts, [copied], reason: 'the copy stays');
    expect(history.undoCount, steps + 1);

    history.undo();
    await pumpFrames(tester);
    expect(celOf(tester, textToolSecondKey).texts, isEmpty);
    expect(celOf(tester).texts, [copied]);
  });

  testWidgets('the text in hand is copied AHEAD of the frame you stand on, '
      'and lets go of the frames in hand — one copy in hand, whichever '
      'board took it', (tester) async {
    await pumpTextToolApp(tester, project: textToolProject(drawings: 2));
    final session = sessionOf(tester);
    pill(tester).copyFrame();
    expect(
      session.clipboard.canPasteIndependentFrameAtCurrentFrame,
      isTrue,
      reason: '⛔전제: the frame is in hand',
    );
    await takeTextTool(tester);
    final c = canvasPixelInView(tester);
    await clickAt(tester, c.dx, c.dy);
    await typeText(tester, 'hi');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFrames(tester);

    await pressCtrl(tester, LogicalKeyboardKey.keyC);

    expect(session.textClipboard.holdsText, isTrue);
    expect(session.clipboard.canPasteIndependentFrameAtCurrentFrame, isFalse);

    session.selectFrameIndex(1);
    await pumpFrames(tester);
    pill(tester).copyFrame();
    expect(session.textClipboard.holdsText, isFalse);
    expect(session.clipboard.canPasteIndependentFrameAtCurrentFrame, isTrue);
  });

  testWidgets('🚨while its letters are typed into, a copy is not the '
      'text\'s', (tester) async {
    await pumpTextToolApp(tester);
    await takeTextTool(tester);
    final c = canvasPixelInView(tester);
    await clickAt(tester, c.dx, c.dy);
    await typeText(tester, 'hi');
    expect(textToolOf(tester).hold, CelTextHold.letters, reason: '⛔전제');

    pill(tester).copyPress?.call();

    expect(sessionOf(tester).textClipboard.holdsText, isFalse);
  });

  testWidgets('a text in hand pastes where a cel stands, and lights no link '
      'paste (I-101-Q2)', (tester) async {
    await hiHeldByItsBox(tester, project: secondHeldTwice());
    await pressCtrl(tester, LogicalKeyboardKey.keyC);
    final session = sessionOf(tester);

    session.selectFrameIndex(1);
    await pumpFrames(tester);
    expect(pill(tester).canPasteIndependentFrame, isTrue);
    expect(pill(tester).canPasteLinkedFrame, isFalse);

    session.selectFrameIndex(3);
    await pumpFrames(tester);
    expect(
      pill(tester).canPasteIndependentFrame,
      isFalse,
      reason: 'a frame with no cel takes none — no cel is made (C6)',
    );
  });

  testWidgets('a frame range pastes on every cel in it: once on the cel it '
      'holds twice, none on the frame with no cel (C5 · C6), one undo', (
    tester,
  ) async {
    await hiHeldByItsBox(tester, project: secondHeldTwice());
    await pressCtrl(tester, LogicalKeyboardKey.keyC);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFrames(tester);
    final session = sessionOf(tester);
    Map<int, TimelineExposure> timeline() => session.requireActiveCut.layers
        .firstWhere((layer) => layer.id == textToolLayerId)
        .timeline;
    final before = timeline();
    final steps = session.historyManager.undoCount;
    session.frameRangeSelection.value = const TimelineFrameRangeSelection(
      layerId: textToolLayerId,
      startIndex: 0,
      endIndexExclusive: 4,
    );
    await tester.pump();

    await pressCtrl(tester, LogicalKeyboardKey.keyV);
    await pumpFrames(tester);

    expect(celOf(tester).texts, hasLength(2));
    expect(celOf(tester, textToolSecondKey).texts, hasLength(1));
    expect(timeline(), before);
    expect(session.historyManager.undoCount, steps + 1);
  });

  testWidgets('the pill\'s paste lights the moment a text is copied', (
    tester,
  ) async {
    await hiHeldByItsBox(tester);
    const paste = ValueKey<String>('shared-paste-independent-button');
    expect(
      tester.appIconButton(find.byKey(paste)).onPressed,
      isNull,
      reason: '⛔전제: nothing in hand',
    );

    await pressCtrl(tester, LogicalKeyboardKey.keyC);
    await pumpFrames(tester);

    expect(tester.appIconButton(find.byKey(paste)).onPressed, isNotNull);
  });

  testWidgets('🚨with a band on another row — where the pill copies nothing '
      'else — the text in hand is still copied', (tester) async {
    await hiHeldByItsBox(tester, project: twoRows());
    final session = sessionOf(tester);
    final other = session.requireActiveCut.layers.firstWhere(
      (layer) => layer.id != session.activeLayer!.id,
    );
    session.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: other.id,
      startIndex: 0,
      endIndexExclusive: 1,
    );
    await pumpFrames(tester);
    expect(textToolOf(tester).session, isNotNull, reason: '⛔전제: held');
    expect(
      session.clipboard.canCopyFrameAtCurrentFrame,
      isFalse,
      reason: '⛔전제: the band misses the row stood on',
    );

    await pressCtrl(tester, LogicalKeyboardKey.keyC);

    expect(session.textClipboard.holdsText, isTrue);
  });

  testWidgets('🚨two rows that are one picture take ONE text — a paste '
      'lands once on each cel the STORE holds, not on each row (C5)', (
    tester,
  ) async {
    await hiHeldByItsBox(tester, project: twoRows(onePicture: true));
    await pressCtrl(tester, LogicalKeyboardKey.keyC);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFrames(tester);
    final store = coordinatorOf(tester).frameStore;
    expect(
      store.canonicalKeyOf(
        BrushFrameKey(
          projectId: textToolSecondKey.projectId,
          trackId: textToolSecondKey.trackId,
          cutId: textToolSecondKey.cutId,
          layerId: twin,
          frameId: textToolSecondFrameId,
        ),
      ),
      textToolSecondKey,
      reason: '⛔fixture: the twin\'s cel is the row\'s',
    );
    sessionOf(tester).frameRangeSelection.value =
        const TimelineFrameRangeSelection(
          layerId: textToolLayerId,
          layerIds: [textToolLayerId, twin],
          startIndex: 1,
          endIndexExclusive: 2,
        );
    await tester.pump();

    await pressCtrl(tester, LogicalKeyboardKey.keyV);
    await pumpFrames(tester);

    expect(celOf(tester, textToolSecondKey).texts, hasLength(1));
  });

  testWidgets('a project behind the one on screen has no text in hand to '
      'copy — the canvas is the one in front', (tester) async {
    await pumpTextToolApp(tester);
    final behind = sessionOf(tester);
    for (final key in ['top-strip-project-button', 'menu-file-new']) {
      await tester.tap(find.byKey(ValueKey<String>(key)));
      await pumpFrames(tester, 40);
    }
    expect(sessionOf(tester), isNot(same(behind)), reason: '⛔전제');
    await takeTextTool(tester);
    final c = canvasPixelInView(tester);
    await clickAt(tester, c.dx, c.dy);
    await typeText(tester, 'hi');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpFrames(tester);
    expect(sessionOf(tester).textClipboard.canCopy, isTrue, reason: '⛔전제');

    expect(behind.textClipboard.canCopy, isFalse);
  });

  group('the board itself', () {
    /// A copy put in hand through the canvas's own channel, as the
    /// workspace hangs it — and every landing its paste asks to make
    /// with its faces, heard.
    List<Set<String>> holdCopy(WidgetTester tester, TextCopy copy) {
      final session = sessionOf(tester);
      final canvas = session.textClipboard.canvasText!;
      final faces = <Set<String>>[];
      session.textClipboard
        ..canvasText = (
          heldByItsBox: () => copy,
          landingWith: (landing, families) {
            faces.add(families);
            return canvas.landingWith(landing, families);
          },
        )
        ..copy();
      return faces;
    }

    CelTextContent hiIn(String? family) => CelTextContent(
      spans: [
        CelTextSpan(
          text: 'hi',
          style: TextLetterStyle(fontFamily: family),
        ),
      ],
      anchor: CanvasPoint(x: 10, y: 10),
    );

    /// A tile of [size] inked all over.
    BitmapTile ink(int size) => BitmapTile(
      size: size,
      pixels: Uint8List(BitmapTile.bytesFor(size))..fillRange(0, 4, 0xFF),
    );

    testWidgets('a pasted text brings the faces its letters are written in, '
        'in its own step', (tester) async {
      await pumpTextToolApp(tester);
      final faces = holdCopy(tester, (
        content: CelTextContent(
          spans: [
            const CelTextSpan(
              text: 'h',
              style: TextLetterStyle(fontFamily: 'Hand'),
            ),
            const CelTextSpan(
              text: 'i',
              style: TextLetterStyle(fontFamily: 'Pen'),
            ),
          ],
          anchor: CanvasPoint(x: 10, y: 10),
        ),
        plate: const {},
      ));

      sessionOf(tester).textClipboard.pasteIndependent();

      expect(faces, [
        {'Hand', 'Pen'},
      ]);
      expect(celOf(tester).texts.single.content.text, 'hi');
    });

    testWidgets('its pixels stop at THIS cel\'s wall: a copy from a '
        'pasteboard that reaches further keeps none past it', (tester) async {
      await pumpTextToolApp(tester);
      final wall = coordinatorOf(tester).sessionStore.pasteboard.region;
      final size = celOf(tester).tileSize;
      final inside = TileCoord(x: 0, y: 0);
      final past = TileCoord(x: wall.rightExclusive ~/ size + 4, y: 0);
      holdCopy(tester, (
        content: hiIn(null),
        plate: {inside: ink(size), past: ink(size)},
      ));

      sessionOf(tester).textClipboard.pasteIndependent();

      expect(celOf(tester).texts.single.plate.keys, [inside]);
    });

    testWidgets('🚨a tile the wall crosses keeps what lies inside it and '
        'loses what lies past it — the cut is to the pixel', (tester) async {
      await pumpTextToolApp(tester);
      final wall = coordinatorOf(tester).sessionStore.pasteboard.region;
      final size = celOf(tester).tileSize;
      final edge = wall.rightExclusive % size;
      expect(edge, isNot(0), reason: '⛔fixture: the wall crosses a tile');
      expect(wall.top, lessThanOrEqualTo(0), reason: '⛔fixture');
      final crossed = TileCoord(x: wall.rightExclusive ~/ size, y: 0);
      // The tile's top row inked on its last column inside the wall and on
      // its first one past it.
      final pixels = Uint8List(BitmapTile.bytesFor(size));
      for (final column in [edge - 1, edge]) {
        pixels.fillRange(column * 4, column * 4 + 4, 0xFF);
      }
      holdCopy(tester, (
        content: hiIn(null),
        plate: {crossed: BitmapTile(size: size, pixels: pixels)},
      ));

      sessionOf(tester).textClipboard.pasteIndependent();

      final kept = Uint8List(BitmapTile.bytesFor(size));
      celOf(tester).texts.single.plate[crossed]!.copyPixelsInto(kept);
      expect(kept[(edge - 1) * 4 + 3], 0xFF, reason: 'inside the wall');
      expect(kept[edge * 4 + 3], 0, reason: 'past it');
    });
  });
}
