import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pixel_clipboard_verb.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/bitmap_surface_geometry.dart'
    show bitmapSurfaceContentBounds;
import 'package:anicel/src/services/canvas_color_sampler.dart'
    show surfacePixelRgba;
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../helpers/panel_finders.dart';

/// 🚨★★★**THE CUT TOOL'S STAMP LANDS WHERE 픽셀 붙여넣기 LANDS** (F-293).
///
/// 🗣️유저 2026-10-05: 「잘라내기도구의 스탬프, 여러 프레임 선택해서 여러프레임
/// 붙여넣을수있도록. **색편집의 픽셀붙여넣기랑 법 통일**」 · 「여러프레임 붙여넣기
/// 얘기는 선택범위로 선택한채로 커서로 붙여넣거나, 원래 위치에 붙여넣기나
/// 동일하게. 법 통일해서 가능하도록」.
/// 🗣️I-28-paste-in-place-Q1 (유저 2026-10-01): 「같은 문으로 — 범위 전부 ·
/// 페더 따름」.
///
/// ↩️The stamp went down the pen's funnel: whatever range was drawn on the
/// timeline it landed on the cel you stand on, and it cut through a
/// selection's hard outline. The paste's law, by every road the stamp has —
/// the press on the canvas, the drag's trail, 원래 위치에 붙여넣기.
void main() {
  // The one drawable row's timeline: three single cels, a cel HELD for two
  // frames (3–4), an EMPTY frame (5) and one more cel (6).
  const cels = ['c0', 'c1', 'c2', 'c3', 'c4'];
  const starts = {0: 'c0', 1: 'c1', 2: 'c2', 3: 'c3', 6: 'c4'};

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
                        for (final id in cels)
                          Frame(
                            id: FrameId(id),
                            duration: 1,
                            strokes: const [],
                          ),
                      ],
                      timeline: {
                        for (final MapEntry(key: at, value: id)
                            in starts.entries)
                          at: TimelineExposure.drawing(
                            FrameId(id),
                            length: id == 'c3' ? 2 : 1,
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

  EditorWorkspace workspaceOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace));

  Layer row(EditorSessionManager session) =>
      session.layers.firstWhere((l) => l.frames.length == cels.length);

  Future<void> pumpFrames(WidgetTester tester, [int frames = 6]) async {
    for (var i = 0; i < frames; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<EditorSessionManager> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: fixture())),
    );
    await tester.pumpAndSettle();
    final session = workspaceOf(tester).session;
    session.selectLayer(row(session).id);
    session.selectFrameIndex(0);
    await tester.pump();
    return session;
  }

  BrushFrameKey keyOf(EditorSessionManager session, String cel) =>
      session.brushFrameKeyForCut(
        session.requireActiveCut,
        row(session).id,
        FrameId(cel),
      );

  BitmapSurface celOf(EditorSessionManager session, String cel) =>
      session.pixelEditing.coordinator!.currentSurfaceOf(keyOf(session, cel));

  /// [cel]'s straight RGBA at (x, y), as 0xRRGGBBAA — zero where it is clear.
  int pixel(EditorSessionManager session, String cel, int x, int y) =>
      surfacePixelRgba(celOf(session, cel), x, y) ?? 0;

  int alphaOf(int rgba) => rgba & 0xFF;

  /// Paints [cel] with one colour inside [left, right) × [top, bottom),
  /// through the COORDINATOR — the surface the verbs read and write.
  void paint(
    EditorSessionManager session,
    String cel, {
    required ({int left, int top, int right, int bottom}) box,
    required List<int> rgba,
  }) {
    final key = keyOf(session, cel);
    final coordinator = session.pixelEditing.coordinator!;
    final base = coordinator.currentSurfaceOf(key);
    final size = base.tileSize;
    final pixels = Uint8List(size * size * 4);
    for (var y = box.top; y < box.bottom; y += 1) {
      for (var x = box.left; x < box.right; x += 1) {
        pixels.setRange((y * size + x) * 4, (y * size + x) * 4 + 4, rgba);
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

  const red = [255, 0, 0, 255];
  const blue = [0, 0, 255, 255];
  const redRgba = 0xFF0000FF;
  const blueRgba = 0x0000FFFF;

  /// A square of one colour, cut from (10, 10).
  CutPiece squareOf(List<int> rgba, {int side = 20}) => CutPiece(
    image: BrushStampImage(
      id: 'held-${rgba.join('-')}-$side',
      width: side,
      height: side,
      rgba: Uint8List.fromList([
        for (var i = 0; i < side * side; i += 1) ...rgba,
      ]),
    ),
    originLeft: 10,
    originTop: 10,
  );

  /// Puts [piece] in the window's cut slot and arms the stamp, at [blend]
  /// and [opacity] — the tool's own.
  Future<void> holdStamp(
    WidgetTester tester,
    CutPiece piece, {
    BrushBlendMode blend = BrushBlendMode.color,
    double opacity = 1,
  }) async {
    workspaceOf(tester).session.pixelVerbs.cutToolHand!(piece);
    final brush = workspaceOf(tester).brushTool!;
    brush.value = brush.value.copyWith(
      tool: CanvasTool.cutStamp,
      cutStampBlendMode: blend,
      cutStampOpacity: opacity,
    );
    await pumpFrames(tester);
  }

  void selectAcross(EditorSessionManager session, int start, int end) {
    session.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: row(session).id,
      startIndex: start,
      endIndexExclusive: end,
    );
  }

  void marquee(
    EditorSessionManager session,
    CanvasSelectionRegion? region, {
    SelectionMaskOptions mask = SelectionMaskOptions.none,
  }) {
    session.pixelVerbs.pixelVerbCanvas = () => (
      region: region,
      argb: 0xFF000000,
      mask: mask,
    );
  }

  /// A press of the mouse on the canvas, where the artist can see it.
  Future<void> press(WidgetTester tester, {Offset off = Offset.zero}) async {
    await tester.tapAt(
      visibleCanvasPoint(tester, offset: off),
      kind: PointerDeviceKind.mouse,
    );
    await pumpFrames(tester);
  }

  /// 원래 위치에 붙여넣기, by its button in the tool settings — the rail
  /// group they live in starts folded.
  Future<void> pasteInPlace(WidgetTester tester) async {
    final button = find.byKey(
      const ValueKey<String>('cut-paste-at-origin-button'),
    );
    if (button.evaluate().isEmpty) {
      final settings = EditorWorkspace.railGroupId(right: false, slot: 2);
      await tester.tap(find.byKey(ValueKey<String>('rail-group-$settings')));
      await pumpFrames(tester, 30);
    }
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await pumpFrames(tester);
  }

  /// [b] holds [a]'s picture, pixel for pixel.
  void expectSamePicture(BitmapSurface a, BitmapSurface b, String why) {
    final box = bitmapSurfaceContentBounds(a);
    expect(bitmapSurfaceContentBounds(b), box, reason: '$why — its box');
    if (box == null) {
      return;
    }
    for (var y = box.top; y < box.bottomExclusive; y += 1) {
      for (var x = box.left; x < box.rightExclusive; x += 1) {
        final want = surfacePixelRgba(a, x, y);
        final got = surfacePixelRgba(b, x, y);
        if (want != got) {
          fail('$why — at ($x, $y): $got, not $want');
        }
      }
    }
  }

  testWidgets('🚨a press lands the piece on every cel of the frame range — a '
      'blank cel too — as ONE undo', (tester) async {
    final session = await pump(tester);
    await holdStamp(tester, squareOf(red));
    selectAcross(session, 0, 3);
    await tester.pump();

    await press(tester);

    final landed = celOf(session, 'c0');
    final box = bitmapSurfaceContentBounds(landed);
    expect(box, isNotNull, reason: '⛔premise: the press stamps the cel');
    expect(
      (box!.rightExclusive - box.left, box.bottomExclusive - box.top),
      (20, 20),
      reason: 'one piece, whole',
    );
    expectSamePicture(landed, celOf(session, 'c1'), 'c1, a blank cel');
    expectSamePicture(landed, celOf(session, 'c2'), 'c2');
    expect(
      bitmapSurfaceContentBounds(celOf(session, 'c3')),
      isNull,
      reason: 'past the range nothing lands',
    );

    session.historyManager.undo();
    await tester.pump();
    for (final cel in ['c0', 'c1', 'c2']) {
      expect(
        bitmapSurfaceContentBounds(celOf(session, cel)),
        isNull,
        reason: 'one undo takes it off $cel',
      );
    }
    expect(session.historyManager.canUndo, isFalse, reason: 'ONE step');

    session.historyManager.redo();
    await tester.pump();
    expectSamePicture(landed, celOf(session, 'c2'), 'redo, c2');
  });

  testWidgets('with no range drawn the press lands on the cel you stand on, '
      'and nowhere else', (tester) async {
    final session = await pump(tester);
    await holdStamp(tester, squareOf(red));

    await press(tester);

    expect(bitmapSurfaceContentBounds(celOf(session, 'c0')), isNotNull);
    for (final cel in ['c1', 'c2', 'c3', 'c4']) {
      expect(bitmapSurfaceContentBounds(celOf(session, cel)), isNull);
    }
  });

  testWidgets('🚨a drag\'s trail lands on every cel of the range, stamp for '
      'stamp', (tester) async {
    final session = await pump(tester);
    await holdStamp(tester, squareOf(red));
    selectAcross(session, 0, 2);
    await tester.pump();

    final mouse = await tester.startGesture(
      visibleCanvasPoint(tester, offset: const Offset(-120, 0)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    for (var step = 0; step < 4; step += 1) {
      await mouse.moveBy(const Offset(60, 0));
      await tester.pump();
    }
    await mouse.up();
    await pumpFrames(tester);

    final trail = celOf(session, 'c0');
    final box = bitmapSurfaceContentBounds(trail)!;
    expect(
      box.rightExclusive - box.left,
      greaterThanOrEqualTo(60),
      reason: '⛔premise: the drag laid three pieces or more',
    );
    expectSamePicture(trail, celOf(session, 'c1'), 'the trail, on c1');
    expect(bitmapSurfaceContentBounds(celOf(session, 'c2')), isNull);
  });

  testWidgets('🚨원래 위치에 붙여넣기 lands what 픽셀 붙여넣기 lands — the same '
      'cels, the same pixels, over and under (I-28-paste-in-place-Q1)', (
    tester,
  ) async {
    final session = await pump(tester);
    paint(
      session,
      'c0',
      box: (left: 10, top: 10, right: 40, bottom: 40),
      rgba: red,
    );
    // c1 holds blue over the piece's left half, so the ORDER shows.
    paint(
      session,
      'c1',
      box: (left: 10, top: 10, right: 25, bottom: 40),
      rgba: blue,
    );
    session.pixelVerbs.runPixelClipboardVerb(PixelClipboardVerb.copy);
    // ONE picture in both holders.
    final board = session.appClipboard.pixels.piece!;
    // The range does not hold the cel you stand on, a cel is held twice in
    // it (3–4) and the marquee is soft: every clause of the paste's law.
    selectAcross(session, 1, 5);
    marquee(
      session,
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 14, top: 12, right: 32, bottom: 60),
      ),
      mask: const SelectionMaskOptions(featherPx: 4),
    );
    await tester.pump();

    for (final (verb, blend) in const [
      (PixelClipboardVerb.pasteAbove, BrushBlendMode.color),
      (PixelClipboardVerb.pasteBelow, BrushBlendMode.behind),
    ]) {
      final before = {for (final cel in cels) cel: celOf(session, cel)};
      session.pixelVerbs.runPixelClipboardVerb(verb);
      await tester.pump();
      final pasted = {for (final cel in cels) cel: celOf(session, cel)};
      expect(
        alphaOf(pixel(session, 'c2', 31, 30)),
        allOf(greaterThan(0), lessThan(255)),
        reason: '⛔premise: the paste lands in part at the soft edge',
      );
      expect(
        identical(pasted['c0'], before['c0']),
        isTrue,
        reason: '⛔premise: the cel you stand on is outside the range',
      );
      session.historyManager.undo();
      await tester.pump();

      await holdStamp(tester, board, blend: blend);
      await pasteInPlace(tester);

      for (final cel in cels) {
        expectSamePicture(
          pasted[cel]!,
          celOf(session, cel),
          '${verb.name} against the stamp at ${blend.name}, on $cel',
        );
      }
      session.historyManager.undo();
      await tester.pump();
      for (final cel in cels) {
        expectSamePicture(
          before[cel]!,
          celOf(session, cel),
          'one undo takes the button\'s press off $cel',
        );
      }
    }
  });

  testWidgets('one landing per PHYSICAL cel, and no cel is made on an empty '
      'frame — by the press and by the button (08-12 C5 · C6)', (tester) async {
    final session = await pump(tester);
    // Half-transparent, so a second landing on the held cel would show.
    await holdStamp(tester, squareOf(const [255, 0, 0, 128]));
    final exposuresBefore = Map.of(row(session).timeline);
    // 3–4 is ONE cel held twice; 5 is empty.
    selectAcross(session, 3, 6);
    session.selectFrameIndex(3);
    await pumpFrames(tester);

    await press(tester);
    final box = bitmapSurfaceContentBounds(celOf(session, 'c3'))!;
    expect(
      alphaOf(pixel(session, 'c3', box.left + 5, box.top + 5)),
      128,
      reason: 'twice would have laid 128 over 128 — 「같은게 두개인곳에 '
          '붙여넣으면 한번만 발리도록」',
    );
    session.historyManager.undo();
    await tester.pump();

    await pasteInPlace(tester);
    expect(alphaOf(pixel(session, 'c3', 15, 15)), 128);
    expect(
      row(session).timeline.keys.toSet(),
      exposuresBefore.keys.toSet(),
      reason: 'the empty frame stays empty — a piece makes no cel',
    );
  });

  testWidgets('🚨a press lands through the marquee at its FEATHER (「페더 '
      '따름」) — on every cel of the range', (tester) async {
    final session = await pump(tester);
    await holdStamp(tester, squareOf(red, side: 40));
    selectAcross(session, 0, 2);
    await tester.pump();
    // Where the press lands, read off a first press and taken back.
    await press(tester);
    final box = bitmapSurfaceContentBounds(celOf(session, 'c0'))!;
    session.historyManager.undo();
    await tester.pump();

    // The marquee's right edge runs down the middle of the piece; its other
    // three edges are far outside it.
    final edge = box.left + 20;
    final midY = box.top + 20;
    marquee(
      session,
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(
          left: (box.left - 60).toDouble(),
          top: (box.top - 60).toDouble(),
          right: edge.toDouble(),
          bottom: (box.bottomExclusive + 60).toDouble(),
        ),
      ),
      mask: const SelectionMaskOptions(featherPx: 4),
    );
    await press(tester);

    for (final cel in ['c0', 'c1']) {
      expect(
        alphaOf(pixel(session, cel, box.left + 2, midY)),
        255,
        reason: '$cel: deep inside the marquee the piece lands whole',
      );
      expect(
        alphaOf(pixel(session, cel, edge - 1, midY)),
        allOf(greaterThan(0), lessThan(255)),
        reason: '$cel: just inside the edge it lands in part — a hard cut '
            'lands it whole there',
      );
      expect(
        alphaOf(pixel(session, cel, edge, midY)),
        0,
        reason: '$cel: the feather ramps INWARD, so nothing lands past the '
            'outline',
      );
    }
  });

  testWidgets('the stamp\'s own blend and opacity reach every cel — erase '
      'clears with the piece, 50% presses half', (tester) async {
    final session = await pump(tester);
    for (final cel in ['c1', 'c2']) {
      paint(
        session,
        cel,
        box: (left: 0, top: 0, right: 60, bottom: 60),
        rgba: blue,
      );
    }
    selectAcross(session, 1, 3);
    await holdStamp(tester, squareOf(red), blend: BrushBlendMode.erase);

    await pasteInPlace(tester);
    for (final cel in ['c1', 'c2']) {
      expect(pixel(session, cel, 15, 15), 0, reason: '$cel: erased');
      expect(pixel(session, cel, 35, 35), blueRgba, reason: '$cel: the rest');
    }
    session.historyManager.undo();
    await tester.pump();
    expect(pixel(session, 'c2', 15, 15), blueRgba, reason: 'one undo');

    await holdStamp(tester, squareOf(red), opacity: 0.5);
    session.frameRangeSelection.value = null;
    session.selectFrameIndex(6);
    await pumpFrames(tester);
    await pasteInPlace(tester);
    expect(
      alphaOf(pixel(session, 'c4', 15, 15)),
      closeTo(128, 1),
      reason: 'the stamp\'s opacity, on the cel you stand on',
    );
    expect(pixel(session, 'c4', 15, 15) >> 8, redRgba >> 8);
  });

  testWidgets('확정 lays the stamp down again on the cel you stand on — the '
      'stamp is still the last drawing action', (tester) async {
    final session = await pump(tester);
    await holdStamp(tester, squareOf(red));
    selectAcross(session, 0, 2);
    await tester.pump();
    await press(tester);
    final stamped = celOf(session, 'c0');

    session.frameRangeSelection.value = null;
    session.selectFrameIndex(6);
    await pumpFrames(tester);
    final again = workspaceOf(tester).lastStroke!;
    expect(again.canReinput, isTrue);
    again.reinput();
    await pumpFrames(tester);

    expectSamePicture(stamped, celOf(session, 'c4'), '확정, on c4');
  });

  /// 🗣️유저 2026-09-17, of a range that crosses rows: 「몇 행에 걸쳐서 적용하던
  /// **동시적용은 가능하게**」 — rows and frames are one law, and each row
  /// stands on the canvas where its OWN placement puts it
  /// (a-marquee-on-a-posed-row ④).
  group('a range over two rows — one plain, one drawn twice the size', () {
    const plainCel = FrameId('rw-plain-cel');
    const posedCel = FrameId('rw-posed-cel');
    const plain = LayerId('rw-plain');
    const posed = LayerId('rw-posed');

    Layer rowOf(LayerId id, FrameId frame, {double? scale}) => Layer(
      id: id,
      name: id.value,
      frames: [
        Frame(id: frame, name: frame.value, duration: 1, strokes: const []),
      ],
      timeline: {0: TimelineExposure.drawing(frame, length: 1)},
      // Twice the size about the canvas centre: the artwork under a press
      // away from the centre is somewhere else.
      transformTrack: scale == null
          ? null
          : TransformTrack.empty().copyWith(
              scale: PropertyTrack<double>.empty().withKey(0, scale),
            ),
    );

    /// The two rows on screen, the stamp armed, the range drawn over both,
    /// standing on [standOn].
    Future<EditorSessionManager> pumpRows(
      WidgetTester tester, {
      required LayerId standOn,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1700, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            initialProject: Project(
              id: const ProjectId('rw-project'),
              name: 'Rows',
              createdAt: DateTime.utc(2026),
              tracks: [
                Track(
                  id: const TrackId('rw-track'),
                  name: 'Video Track',
                  cuts: [
                    Cut(
                      id: const CutId('rw-cut'),
                      name: 'rw-cut',
                      duration: defaultCutDuration,
                      canvasSize: defaultCutCanvasSize,
                      layers: [
                        rowOf(plain, plainCel),
                        rowOf(posed, posedCel, scale: 2),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final session = workspaceOf(tester).session;
      session.selectLayer(standOn);
      session.selectFrameIndex(0);
      await pumpFrames(tester);
      await holdStamp(tester, squareOf(red));
      session.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: standOn,
        startIndex: 0,
        endIndexExclusive: 1,
        layerIds: const [plain, posed],
      );
      await tester.pump();
      return session;
    }

    ({int left, int top, int rightExclusive, int bottomExclusive}) inkOn(
      EditorSessionManager session,
      LayerId layer,
    ) {
      final box = bitmapSurfaceContentBounds(
        session.pixelEditing.coordinator!.currentSurfaceOf(
          session.brushFrameKeyForCut(
            session.requireActiveCut,
            layer,
            layer == plain ? plainCel : posedCel,
          ),
        ),
      );
      expect(box, isNotNull, reason: '${layer.value} took the piece');
      return box!;
    }

    Offset centreOf(
      ({int left, int top, int rightExclusive, int bottomExclusive}) box,
    ) => Offset(
      (box.left + box.rightExclusive) / 2,
      (box.top + box.bottomExclusive) / 2,
    );

    Offset middleOf(EditorSessionManager session) {
      final canvas = session.requireActiveCut.canvasSize;
      return Offset(canvas.width / 2, canvas.height / 2);
    }

    const away = Offset(140, 70);

    testWidgets('🚨a press lands on each row\'s cel where THAT row shows it — '
        'the piece 1:1 on both, the marquee read on each', (tester) async {
      final session = await pumpRows(tester, standOn: plain);

      await press(tester, off: away);

      final onPlain = inkOn(session, plain);
      final onPosed = inkOn(session, posed);
      for (final box in [onPlain, onPosed]) {
        expect(
          (box.rightExclusive - box.left, box.bottomExclusive - box.top),
          (20, 20),
          reason: 'the piece is a row\'s pure pixels: 1:1 on each',
        );
      }
      final middle = middleOf(session);
      // An unplaced row shows its artwork where it is.
      final pressed = centreOf(onPlain);
      expect(
        (pressed - middle).distance,
        greaterThan(60),
        reason: '⛔premise: the press is away from the centre, where the two '
            'rows part',
      );
      expect(
        (centreOf(onPosed) - (middle + (pressed - middle) / 2)).distance,
        lessThan(1.5),
        reason: 'the posed row is drawn twice the size about the centre, so '
            'the press is half as far out in its artwork',
      );

      // …and each row reads the marquee where IT shows it: an outline whose
      // right edge runs through the press cuts the piece in half on both.
      session.historyManager.undo();
      await tester.pump();
      marquee(
        session,
        CanvasSelectionRegion.shape(
          CanvasSelectionShape.rect(
            left: pressed.dx - 400,
            top: pressed.dy - 400,
            right: pressed.dx,
            bottom: pressed.dy + 400,
          ),
        ),
      );
      await press(tester, off: away);
      final halfOnPlain = inkOn(session, plain);
      final halfOnPosed = inkOn(session, posed);
      expect(halfOnPlain.rightExclusive - halfOnPlain.left, 10);
      expect(
        halfOnPosed.rightExclusive - halfOnPosed.left,
        closeTo(10, 1),
        reason: 'read through the plain row\'s outline, the posed row\'s '
            'piece — half as far out — would lie wholly inside it',
      );
    });

    testWidgets('확정 lays down what landed on the cel you STAND on — not the '
        'first cel the range names', (tester) async {
      // The range names the plain row first; the stand is on the posed one.
      final session = await pumpRows(tester, standOn: posed);
      await press(tester, off: away);
      final landed = centreOf(inkOn(session, posed));
      expect(
        (landed - centreOf(inkOn(session, plain))).distance,
        greaterThan(30),
        reason: '⛔premise: the two rows took it in different places',
      );
      session.historyManager.undo();
      await tester.pump();
      session.frameRangeSelection.value = null;
      await pumpFrames(tester);

      workspaceOf(tester).lastStroke!.reinput();
      await pumpFrames(tester);

      expect(
        (centreOf(inkOn(session, posed)) - landed).distance,
        lessThan(0.6),
        reason: 'the same pixels, at the same place on this cel',
      );
    });
  });
}
