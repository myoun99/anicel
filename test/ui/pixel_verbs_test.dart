import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_folder.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/pixel_clipboard_verb.dart';
import 'package:anicel/src/models/pixel_verb_settings.dart';
import 'package:anicel/src/models/pixel_verb_subject.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/cel_pixel_overwrite.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/pixel_verbs.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/editor_workspace.dart';

/// The two PIXEL verbs — 색 변환 and 픽셀 비우기 — and the ladder that decides
/// what a press touches.
///
/// 유저 2026-08-26: 「조작은 무조건 서있는 레이어에 조작하게 하는거야. 그러니
/// **선택범위 있으면 그거 전부, 아니면 서있는곳** 조작하는거야」.
void main() {
  /// A project whose drawing row already HAS a cel.
  ///
  /// ⚠️A default project has none — every layer arrives with
  /// `frames: const []` — so a fixture that skipped this would be measuring
  /// the ladder's empty answer and calling it the ladder.
  Project projectWithACel() {
    final base = createDefaultProject();
    final track = base.tracks.first;
    final cut = track.cuts.first;
    // 🚨EVERY layer gets one, the camera row included. If only the drawable
    // ones had cels then the gate test would pass with the gate DELETED —
    // what refused the camera row would be its emptiness, not the predicate.
    // Verified by mutation: without this, removing `layerAcceptsBrushInput`
    // left the suite green.
    final drawn = [
      for (final layer in cut.layers)
        if (layer.frames.isEmpty)
          // 🚨THREE distinct cels, one frame each — not one four-frame hold.
          // A hold would let the range rung and the standing rung answer with
          // the same single cel, and the range test could not tell them
          // apart. Verified by mutation: with a hold, deleting the range rung
          // outright left the suite green.
          layer.copyWith(
            frames: [
              for (var i = 0; i < 3; i++)
                Frame(
                  id: FrameId('${layer.id.value}-cel-$i'),
                  duration: 1,
                  strokes: const [],
                ),
            ],
            timeline: {
              for (var i = 0; i < 3; i++)
                i: TimelineExposure.drawing(
                  FrameId('${layer.id.value}-cel-$i'),
                  length: 1,
                ),
            },
          )
        else
          layer,
    ];
    return base.copyWith(
      tracks: [
        track.copyWith(
          cuts: [cut.copyWith(layers: drawn)],
        ),
      ],
    );
  }

  /// Bakes real INK into every drawable cel of the open cut.
  ///
  /// 🚨A frame existing is not a drawing existing — 유저 2026-08-27: 「색변환은
  /// 레이어에 그림이 존재 해야 활성화시키는게 맞고」. A fixture that only
  /// declared frames would now be measuring the empty answer and calling it
  /// the ladder, which is exactly the mistake the cel note above warns about
  /// one level up.
  ///
  /// ⚠️At the cels' own tile size: an editing session FOLLOWS the store
  /// (`BrushFrameEditingCoordinator._storeMovedPast`), so what is baked here
  /// IS the surface the verbs act on and [alphaAt] reads. Baked at 16 it was
  /// a surface no cel of the app ever has, and the coordinator used to go on
  /// drawing on the empty session it had seeded before this ran.
  void inkEveryCel(EditorSessionManager session) {
    final cut = session.requireActiveCut;
    const size = defaultCelTileSize;
    final pixels = Uint8List(size * size * 4);
    for (var i = 3; i < pixels.length; i += 4) {
      pixels[i] = 0xFF;
    }
    for (final layer in session.layers) {
      for (final frame in layer.frames) {
        session.renderCaches.brushFrameStore.storeBakedSurface(
          session.brushFrameKeyForCut(cut, layer.id, frame.id),
          BitmapSurface(
            canvasSize: cut.canvasSize,
            tiles: {
              TileCoord(x: 0, y: 0): BitmapTile(size: size, pixels: pixels),
            },
          ),
        );
      }
    }
  }

  Future<EditorSessionManager> pump(
    WidgetTester tester, {
    Project? project,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(initialProject: project ?? projectWithACel()),
      ),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    if (project == null) {
      inkEveryCel(session);
      await tester.pump();
    }
    return session;
  }

  /// A default project has NO cels — every layer arrives with
  /// `frames: const []`. So a row has to be given one before a pixel verb
  /// has anything to answer with, which is itself the first thing worth
  /// pinning (see the empty-row test).
  Future<Layer> drawableRow(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
    final row = session.layers.firstWhere(
      (l) => layerAcceptsBrushInput(l) && l.frames.isNotEmpty,
    );
    session.selectLayer(row.id);
    session.selectFrameIndex(0);
    await tester.pump();
    return row;
  }

  testWidgets('an EMPTY row has nothing to recolour — the buttons dim',
      (tester) async {
    // A DEFAULT project, deliberately: every layer arrives with no frames, so
    // this is the state a new file is in. A verb that answered 「standing」
    // here would be naming a cel that does not exist.
    final session = await pump(tester, project: createDefaultProject());
    final empty = session.layers.firstWhere(layerAcceptsBrushInput);
    expect(empty.frames, isEmpty);
    session.selectLayer(empty.id);
    await tester.pump();
    expect(session.pixelVerbs.pixelVerbSubject, PixelVerbSubject.nothing);
  });

  testWidgets('standing is one cel — the ladder does not reach for neighbours',
      (tester) async {
    final session = await pump(tester);
    await drawableRow(tester, session);
    expect(session.pixelVerbs.pixelVerbSubject, PixelVerbSubject.standing);
    expect(pixelVerbsOf(session).pixelVerbCellKeys(), hasLength(1));
  });

  testWidgets(
      'a ROW SELECTION does not fan the verb out — 유저: 「내가 비슷한얘기 '
      '옛날에 했다가 폐기했어」', (tester) async {
    final session = await pump(tester);
    await drawableRow(tester, session);
    final standing = pixelVerbsOf(session).pixelVerbCellKeys();
    expect(standing, hasLength(1));

    // Select every row there is. Under the discarded design this would have
    // named one cel per row; the verb still answers with the one you are
    // standing on.
    session.rowSelection.value = [
      for (final layer in session.layers) LayerRowAddress(layer.id),
    ];
    await tester.pump();
    expect(session.rowSelection.value.length, greaterThan(1));

    expect(
      session.pixelVerbs.pixelVerbSubject,
      PixelVerbSubject.standing,
      reason: 'selecting rows says which rows are selected, not '
          '「recolour all of their drawings」',
    );
    expect(
      pixelVerbsOf(session).pixelVerbCellKeys().map((k) => k.frameId).toList(),
      standing.map((k) => k.frameId).toList(),
    );
  });

  testWidgets('a FRAME RANGE is the one rung that touches more than one cel',
      (tester) async {
    final session = await pump(tester);
    final layer = await drawableRow(tester, session);

    session.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: layer.id,
      startIndex: 0,
      endIndexExclusive: 4,
    );
    await tester.pump();

    expect(session.pixelVerbs.pixelVerbSubject, PixelVerbSubject.range);
    // 🚨COUNTED, not just non-empty. `isNotEmpty` passed with the range rung
    // deleted, because the standing rung answers with one — the assertion has
    // to say 「more than standing would give you」 or it is not about the range
    // at all.
    expect(
      pixelVerbsOf(session).pixelVerbCellKeys().length,
      greaterThan(1),
      reason: 'a range is drawn ACROSS the cels, which is why it is the one '
          'rung allowed to name more than one',
    );
  });

  testWidgets('a HIDDEN row is not touched — 유저: 「비지블이 on인 레이어만 '
      '활성화되야함」', (tester) async {
    final session = await pump(tester);
    final row = await drawableRow(tester, session);
    expect(session.pixelVerbs.pixelVerbSubject, PixelVerbSubject.standing);

    session.layerSwitches.toggleLayerVisibility(row.id);
    await tester.pump();
    expect(
      session.pixelVerbs.pixelVerbSubject,
      PixelVerbSubject.nothing,
      reason: '「기본적으로 그림 조작하는건 그런느낌인거지」 — a pixel verb '
          'acts on what you can see',
    );
  });

  testWidgets('a CLEARED cel is not a drawing — 유저: 「삭제눌렀으면 그림이 '
      '사라진거니 … 버튼도 비활성화되야하는데」', (tester) async {
    final session = await pump(tester);
    await drawableRow(tester, session);
    expect(session.pixelVerbs.pixelVerbSubject, PixelVerbSubject.standing);
    final key = pixelVerbsOf(session).pixelVerbCellKeys().single;

    // 🚨What 픽셀 비우기 leaves behind: the tiles are still there, every
    // alpha at zero. It cannot drop them — undo walks the tiles that EXIST
    // (see the `undo-weight` card) — so 「프레임이 있다」 went on meaning
    // 「그림이 있다」 and the buttons stayed lit over an empty block.
    final before = session.renderCaches.brushFrameStore.bakedSurfaceOrNull(key)!;
    session.renderCaches.brushFrameStore.storeBakedSurface(
      key,
      before.putTiles([
        for (final tile in before.tiles.values)
          (
            coord: TileCoord(x: 0, y: 0),
            tile: BitmapTile(
              size: tile.size,
              pixels: Uint8List(tile.size * tile.size * 4),
            ),
          ),
      ]),
    );
    await tester.pump();

    expect(
      session.renderCaches.brushFrameStore.celHasRenderableContent(key),
      isFalse,
      reason: 'the same question the block\'s tint asks',
    );
    expect(session.pixelVerbs.pixelVerbSubject, PixelVerbSubject.nothing);
  });

  testWidgets('the gate is the existing predicate — a camera row has no pixels',
      (tester) async {
    final session = await pump(tester);
    final camera = session.layers
        .where((l) => l.kind == LayerKind.camera)
        .toList();
    if (camera.isEmpty) {
      return; // No camera row in the default project; nothing to assert.
    }
    session.selectLayer(camera.first.id);
    await tester.pump();
    expect(
      session.pixelVerbs.pixelVerbSubject,
      PixelVerbSubject.nothing,
      reason: 'layerAcceptsBrushInput already refuses this — ⛔no new predicate',
    );
  });

  testWidgets('the buttons dim rather than the press throwing when no canvas '
      'coordinator has been published', (tester) async {
    final session = await pump(tester);
    session.pixelEditing.coordinator = null;
    expect(pixelVerbsOf(session).canRunPixelVerb, isFalse);
    // ⛔And the press is a no-op rather than an exception: a gate and a verb
    // that disagree is the bug T25 exists to prevent.
    expect(
      () => pixelVerbsOf(session).runPixelVerb(CelPixelVerb.replaceColour),
      returnsNormally,
    );
  });

  /// ⚠️Ink written through the COORDINATOR, not the store beside it. The
  /// fixture one level up seeds `renderCaches.brushFrameStore` directly and
  /// that is enough for the ladder tests, which only ask WHICH cels a press
  /// names — but the press itself reads `coordinator.currentSurfaceOf`,
  /// which answers with an empty 256-tile surface for the same key. A pin
  /// on the PIXELS has to put the drawing where the verb will look.
  ///
  /// White and opaque, but for the [pixels] named — tile-local (x, y) to
  /// their RGBA.
  void inkThroughCoordinator(
    EditorSessionManager session, {
    Map<(int, int), List<int>> pixels = const {},
  }) {
    final key = pixelVerbsOf(session).pixelVerbCellKeys().single;
    final coordinator = session.pixelEditing.coordinator!;
    final base = coordinator.currentSurfaceOf(key);
    final bytes = base.tileSize * base.tileSize * 4;
    final ink = Uint8List(bytes)..fillRange(0, bytes, 0xFF);
    for (final MapEntry(key: (x, y), value: rgba) in pixels.entries) {
      final at = (y * base.tileSize + x) * 4;
      ink.setRange(at, at + 4, rgba);
    }
    coordinator.restoreSurfaceSnapshot(
      key,
      base.putTiles([
        (
          coord: TileCoord(x: 0, y: 0),
          tile: BitmapTile(size: base.tileSize, pixels: ink),
        ),
      ]),
    );
  }

  List<int> pixelAt(EditorSessionManager session, int x, int y) {
    final key = pixelVerbsOf(session).pixelVerbCellKeys().single;
    final tile = session.pixelEditing.coordinator!
        .currentSurfaceOf(key)
        .tileAt(TileCoord(x: 0, y: 0))!;
    final at = tile.byteOffsetForPixel(x: x, y: y);
    return tile.pixels.sublist(at, at + 4);
  }

  int alphaAt(EditorSessionManager session, int x, int y) =>
      pixelAt(session, x, y)[3];

  /// 🚨★★★**THE SELECTION'S SOFTNESS IS PART OF THE SELECTION.** A Ctrl+T
  /// lift on a marquee honoured 확장·페더·AA; these four verbs ran on a hard
  /// mask whatever the user had set, so one outline meant two things. The
  /// parameter was wired all the way to `celPixelWalkFor` — only the press
  /// site never passed it. 유저 확정 2026-09-09 (`pixel-verbs-mask-options`
  /// = 가): 「선택툴로 선택한채로 사용할때 … 선택의 aa 따르게」.
  ///
  /// ⚠️Two halves, and each has its own mutant: the WORKSPACE has to publish
  /// the fact, and the PRESS has to pass it on.
  group('the selection\'s softness reaches the pixel verbs', () {
    testWidgets('the workspace publishes it, beside the colour and the '
        'marquee', (tester) async {
      final session = await pump(tester);

      expect(
        session.pixelVerbs.pixelVerbCanvas,
        isNotNull,
        reason: 'the canvas-side facts the verbs read at the press',
      );
      expect(
        session.pixelVerbs.pixelVerbCanvas!().mask.isHard,
        isTrue,
        reason: 'every option is off by default, so nothing changes for a '
            'user who never touched them',
      );
    });

    testWidgets('🚨and a FEATHERED marquee softens what 픽셀 비우기 takes',
        (tester) async {
      final session = await pump(tester);
      await drawableRow(tester, session);
      inkThroughCoordinator(session);
      // The marquee the press reads: a box whose edge runs through the ink,
      // so a feather has somewhere to ramp.
      final box = CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(left: 0, top: 0, right: 40, bottom: 40),
      );
      session.pixelVerbs.pixelVerbCanvas = () => (
        region: box,
        argb: 0xFF000000,
        mask: SelectionMaskOptions.none,
      );
      expect(alphaAt(session, 20, 20), 255, reason: 'fixture: ink is here');

      pixelVerbsOf(session).runPixelVerb(CelPixelVerb.clearPixels);
      await tester.pump();
      final hard = alphaAt(session, 38, 38);

      session.historyManager.undo();
      await tester.pump();
      expect(alphaAt(session, 38, 38), 255, reason: 'fixture: undo put it back');

      session.pixelVerbs.pixelVerbCanvas = () => (
        region: box,
        argb: 0xFF000000,
        mask: const SelectionMaskOptions(featherPx: 8),
      );
      pixelVerbsOf(session).runPixelVerb(CelPixelVerb.clearPixels);
      await tester.pump();
      final feathered = alphaAt(session, 38, 38);

      expect(hard, 0, reason: 'a hard mask empties the pixel outright');
      expect(
        feathered,
        greaterThan(hard),
        reason: '⛔the whole round: the press used to ignore this and both '
            'runs came out identical',
      );
    });
  });

  /// 🗣️I-13 — what the colour edit list's knobs hold is read at the PRESS,
  /// as the colour and the marquee are: a knob turns while the list is open.
  group('the knobs reach the press (I-13)', () {
    tearDown(
      () => PixelVerbSettings.settings.value = const PixelVerbSettings(),
    );

    testWidgets('🚨2치화 cuts at the byte the knob holds when it is '
        'pressed', (tester) async {
      final session = await pump(tester);
      await drawableRow(tester, session);
      inkThroughCoordinator(
        session,
        pixels: {
          (0, 0): [10, 20, 30, 127],
          (1, 0): [10, 20, 30, 128],
        },
      );

      pixelVerbsOf(session).runPixelVerb(CelPixelVerb.binarize);
      await tester.pump();
      expect(pixelAt(session, 0, 0), [10, 20, 30, 0], reason: 'under half');
      expect(pixelAt(session, 1, 0), [10, 20, 30, 255]);

      session.historyManager.undo();
      await tester.pump();
      expect(pixelAt(session, 0, 0), [10, 20, 30, 127], reason: 'fixture');

      PixelVerbSettings.settings.value = const PixelVerbSettings(
        binarizeThreshold: 127,
      );
      pixelVerbsOf(session).runPixelVerb(CelPixelVerb.binarize);
      await tester.pump();
      expect(
        pixelAt(session, 0, 0),
        [10, 20, 30, 255],
        reason: '⛔the press read the knob as it stands, not the 128 it was',
      );
    });

    testWidgets('색 삭제 reaches as far as its own knob says', (tester) async {
      final session = await pump(tester);
      await drawableRow(tester, session);
      inkThroughCoordinator(session, pixels: {(0, 0): [2, 2, 2, 255]});
      session.pixelVerbs.pixelVerbCanvas = () => (
        region: null,
        argb: 0xFF000000,
        mask: SelectionMaskOptions.none,
      );

      pixelVerbsOf(session).runPixelVerb(CelPixelVerb.deleteColour);
      await tester.pump();
      expect(alphaAt(session, 0, 0), 255, reason: 'at 0 two off is not it');

      PixelVerbSettings.settings.value = const PixelVerbSettings(
        deleteColourTolerance: 2,
      );
      pixelVerbsOf(session).runPixelVerb(CelPixelVerb.deleteColour);
      await tester.pump();
      expect(alphaAt(session, 0, 0), 0, reason: 'at 2 it is');
    });
  });

  /// The marquee is drawn on the canvas and the pixels live in each row's
  /// artwork, so the press carries it through the placement the stack PAINTS
  /// the row with (`layerPlacementAt`). It used to read the raw track value,
  /// which missed the fx switch and every folder above the row.
  /// I-37 — 유저 2026-10-02: 「폴더 전체를 하나로 들도록」, and I-37-Q1
  /// (10-09): 「변형만」. A transform stood on a folder takes up every
  /// drawing row inside it; every other pixel verb still refuses a folder.
  group('a TRANSFORM reaches into a folder, and only it', () {
    const folder = LayerId('lifted-folder');

    /// The drawing row and a twin of it, both moved into [folder], every
    /// cel inked, standing on the folder at frame 0.
    Future<({Layer a, Layer b})> rowsInAFolder(
      WidgetTester tester,
      EditorSessionManager session, {
      bool bShows = true,
    }) async {
      final a = await drawableRow(tester, session);
      final b = _twinOf(a, 'twin');
      final cut = session.requireActiveCut;
      final at = cut.layers.indexWhere((layer) => layer.id == a.id);
      session.repository.replaceLayer(layer: a.copyWith(folderId: folder));
      session.repository.insertLayer(
        cutId: cut.id,
        layer: b.copyWith(folderId: folder, isVisible: bShows),
        index: at + 1,
      );
      session.repository.insertLayer(
        cutId: cut.id,
        layer: createFolderLayer(id: folder, name: 'F'),
        index: at + 2,
      );
      session.refreshAfterCutCommand();
      inkEveryCel(session);
      session.selectLayer(folder);
      session.selectFrameIndex(0);
      await tester.pump();
      return (a: a, b: b);
    }

    List<String> cels(List<BrushFrameKey>? keys) => [
      for (final key in keys ?? const <BrushFrameKey>[]) key.frameId.value,
    ];

    /// What a transform lifts where you stand, by cel — none of them live:
    /// a folder is no cel the canvas edits.
    List<String> underfoot(List<({BrushFrameKey key, bool live})>? lifted) {
      expect(lifted?.where((cel) => cel.live), anyOf(isNull, isEmpty));
      return cels(lifted?.map((cel) => cel.key).toList());
    }

    testWidgets('standing on a folder, a transform takes up the cel of every '
        'drawing row inside it — and no other pixel verb reaches in', (
      tester,
    ) async {
      final session = await pump(tester);
      final (:a, :b) = await rowsInAFolder(tester, session);
      final verbs = pixelVerbsOf(session);

      expect(underfoot(verbs.transformCelsUnderfoot()), [
        '${a.id.value}-cel-0',
        'twin-cel-0',
      ]);
      expect(cels(verbs.transformCellKeys()), [
        '${a.id.value}-cel-0',
        'twin-cel-0',
      ]);
      expect(
        verbs.pixelVerbCellKeys(),
        isEmpty,
        reason: 'I-37-Q1 「변형만」: 색 변환 · 픽셀 비우기 stay out of a folder',
      );
    });

    testWidgets('a HIDDEN row inside the folder is not taken up', (
      tester,
    ) async {
      final session = await pump(tester);
      final (:a, b: _) = await rowsInAFolder(tester, session, bShows: false);

      expect(underfoot(pixelVerbsOf(session).transformCelsUnderfoot()), [
        '${a.id.value}-cel-0',
      ]);
    });

    testWidgets('a RANGE over the folder carries every row inside it across '
        'the range', (tester) async {
      final session = await pump(tester);
      await rowsInAFolder(tester, session);
      session.frameRangeSelection.value = const TimelineFrameRangeSelection(
        layerId: folder,
        startIndex: 0,
        endIndexExclusive: 3,
      );
      await tester.pump();

      expect(pixelVerbsOf(session).transformCellKeys(), hasLength(6));
      expect(pixelVerbsOf(session).pixelVerbCellKeys(), isEmpty);
    });

    testWidgets('standing on a drawing row nothing is underfoot, and the '
        'transform\'s ladder is the pixel verbs\'', (tester) async {
      final session = await pump(tester);
      final (:a, b: _) = await rowsInAFolder(tester, session);
      session.selectLayer(a.id);
      await tester.pump();
      final verbs = pixelVerbsOf(session);

      expect(verbs.transformCelsUnderfoot(), isNull);
      expect(cels(verbs.transformCellKeys()), cels(verbs.pixelVerbCellKeys()));
      expect(verbs.transformCellKeys(), hasLength(1));
    });

    // 🚨F-458 (유저 2026-10-23): 「…보이고있는거니까」 — and the solo shows
    // the folders above the row you stand on, whatever their own eyes.
    testWidgets('standing in a folder the user switched off, the solo '
        'showing it makes the row one an edit reaches', (tester) async {
      final session = await pump(tester);
      final (:a, b: _) = await rowsInAFolder(tester, session);
      session.selectLayer(a.id);
      session.layerSwitches.toggleLayerVisibility(folder);
      await tester.pump();
      expect(
        session.pixelVerbs.pixelVerbSubject,
        PixelVerbSubject.nothing,
        reason: 'the premise: a row in a hidden folder is hidden',
      );

      session.visibilitySolo.toggleLayerVisibilitySolo();
      await tester.pump();
      expect(
        session.requireActiveCut.layers.byId(folder)!.isVisible,
        isTrue,
        reason: 'the premise: the solo shows the folder above you',
      );
      expect(session.pixelVerbs.pixelVerbSubject, PixelVerbSubject.standing);
    });
  });

  /// F-329 (유저 2026-10-10): 「변형중에도 라이브로 선택된 다른행의 프레임도
  /// 변형중인거 보이도록」 — a frame range drawn down rows lifts each row's cel
  /// on screen, beside the cel you stand on, as a folder's rows are lifted.
  group('a TRANSFORM over a RANGE lifts each row\'s cel on screen', () {
    /// The drawing row and a twin of it beside it, every cel inked, standing
    /// on the row at frame 0.
    Future<({Layer a, Layer b})> rowAndTwin(
      WidgetTester tester,
      EditorSessionManager session,
    ) async {
      final a = await drawableRow(tester, session);
      final b = _twinOf(a, 'twin');
      final cut = session.requireActiveCut;
      session.repository.insertLayer(
        cutId: cut.id,
        layer: b,
        index: cut.layers.indexWhere((layer) => layer.id == a.id) + 1,
      );
      session.refreshAfterCutCommand();
      inkEveryCel(session);
      session.selectLayer(a.id);
      session.selectFrameIndex(0);
      await tester.pump();
      return (a: a, b: b);
    }

    /// What a transform lifts where you stand, by cel, and which is live.
    List<(String, bool)>? lifted(EditorSessionManager session) =>
        pixelVerbsOf(session).transformCelsUnderfoot()
            ?.map((cel) => (cel.key.frameId.value, cel.live))
            .toList();

    testWidgets('across both rows: your cel live, and the other row\'s cel '
        'at the playhead beside it — not the frames off screen', (
      tester,
    ) async {
      final session = await pump(tester);
      final (:a, :b) = await rowAndTwin(tester, session);
      session.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: a.id,
        layerIds: [a.id, b.id],
        startIndex: 0,
        endIndexExclusive: 3,
      );
      await tester.pump();

      expect(lifted(session), [
        ('${a.id.value}-cel-0', true),
        ('twin-cel-0', false),
      ]);
    });

    testWidgets('a range on the next row adds that row — it does not take '
        'your own cel out of the lift', (tester) async {
      final session = await pump(tester);
      final (:a, :b) = await rowAndTwin(tester, session);
      session.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: b.id,
        layerIds: [b.id],
        startIndex: 0,
        endIndexExclusive: 3,
      );
      await tester.pump();

      expect(lifted(session), [
        ('${a.id.value}-cel-0', true),
        ('twin-cel-0', false),
      ]);
    });

    /// The cels a transform's confirm lands on, by name.
    List<String> landsOn(EditorSessionManager session) => [
      for (final key in pixelVerbsOf(session).transformCellKeys())
        key.frameId.value,
    ];

    // 🚨F-399 (유저 2026-10-18): 「활성레이어 솔로 상태라도 여러 행의 블록
    // 선택하고 변형작동시 가능하게하도록. 지금 현재 서있는 레이어만
    // 적용되는듯」. The solo switches the other rows' eyes off for the
    // screen, and the ladder asked those eyes.
    testWidgets('with the solo up, a range across both rows still lands on '
        'both — the solo is display, not an edit', (tester) async {
      final session = await pump(tester);
      final (:a, :b) = await rowAndTwin(tester, session);
      session.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: a.id,
        layerIds: [a.id, b.id],
        startIndex: 0,
        endIndexExclusive: 3,
      );
      final before = landsOn(session);
      expect(before, contains('twin-cel-0'), reason: 'the premise');

      session.visibilitySolo.toggleLayerVisibilitySolo();
      await tester.pump();
      expect(
        session.requireActiveCut.layers.byId(b.id)!.isVisible,
        isFalse,
        reason: 'the premise: the solo switched the twin off',
      );

      expect(landsOn(session), before);
      expect(
        lifted(session),
        isNull,
        reason: 'nothing else is lifted live: the twin is not on screen, '
            'and it lands at the confirm',
      );
    });

    testWidgets('and a row the USER switched off stays out of it, solo or '
        'not', (tester) async {
      final session = await pump(tester);
      final (:a, :b) = await rowAndTwin(tester, session);
      session.layerSwitches.toggleLayerVisibility(b.id);
      session.frameRangeSelection.value = TimelineFrameRangeSelection(
        layerId: a.id,
        layerIds: [a.id, b.id],
        startIndex: 0,
        endIndexExclusive: 3,
      );
      final before = landsOn(session);
      expect(before, isNot(contains('twin-cel-0')), reason: 'the premise');

      session.visibilitySolo.toggleLayerVisibilitySolo();
      await tester.pump();
      expect(landsOn(session), before);
    });

    // 🚨F-458 (유저 2026-10-23): 「비지블 off인 레이어에서 활성레이어솔로인
    // 상태라도 색변환이나 그런 보여야만 할수있는 조작관련 가능하게. 왜냐면
    // 보이고있는거니까」.
    testWidgets('and standing on a row the user switched off, the solo '
        'showing it makes it one an edit reaches — it is on screen', (
      tester,
    ) async {
      final session = await pump(tester);
      final (:a, b: _) = await rowAndTwin(tester, session);
      session.layerSwitches.toggleLayerVisibility(a.id);
      await tester.pump();
      expect(session.pixelVerbs.pixelVerbSubject, PixelVerbSubject.nothing);

      session.visibilitySolo.toggleLayerVisibilitySolo();
      await tester.pump();
      expect(
        session.requireActiveCut.layers.byId(a.id)!.isVisible,
        isTrue,
        reason: 'the premise: the solo shows the row you stand on',
      );
      expect(session.pixelVerbs.pixelVerbSubject, PixelVerbSubject.standing);
      expect(
        session.pixelVerbs.canRunPixelClipboardVerb(PixelClipboardVerb.copy),
        isTrue,
        reason: 'and the cel you stand on, which 픽셀 복사 reads',
      );

      session.visibilitySolo.toggleLayerVisibilitySolo();
      await tester.pump();
      expect(
        session.pixelVerbs.pixelVerbSubject,
        PixelVerbSubject.nothing,
        reason: 'the eye is still the one the user left off: out of the '
            'solo, nothing shows it',
      );
    });
  });

  group('the marquee reaches a row where the row shows', () {
    CanvasSelectionRegion box(double left, double right) =>
        CanvasSelectionRegion.shape(
          CanvasSelectionShape.rect(left: left, top: 0, right: right, bottom: 40),
        );

    /// The canvas centre, moved right by [dx] — a position key's pose.
    TransformTrack movedRight(EditorSessionManager session, double dx) {
      final size = session.requireActiveCut.canvasSize;
      return TransformTrack(
        keyframes: {
          0: TransformPose(
            center: CanvasPoint(x: size.width / 2 + dx, y: size.height / 2),
          ),
        },
      );
    }

    Future<void> clearUnder(
      WidgetTester tester,
      EditorSessionManager session,
      CanvasSelectionRegion marquee,
    ) async {
      session.pixelVerbs.pixelVerbCanvas = () => (
        region: marquee,
        argb: 0xFF000000,
        mask: SelectionMaskOptions.none,
      );
      pixelVerbsOf(session).runPixelVerb(CelPixelVerb.clearPixels);
      await tester.pump();
    }

    testWidgets('a row whose transform is switched OFF shows where it stands '
        '— its keys do not move the marquee', (tester) async {
      final session = await pump(tester);
      final row = await drawableRow(tester, session);
      session.laneVerbs.updateLayerTransformTrack(
        row.id,
        movedRight(session, 100),
      );
      session.effectsAndFx.toggleLayerTransformFx(row.id);
      await tester.pump();
      expect(
        session.requireActiveCut.layers.byId(row.id)!.transformEnabled,
        isFalse,
        reason: 'fixture: keyed, and bypassed',
      );
      inkThroughCoordinator(session);

      await clearUnder(tester, session, box(0, 40));

      expect(alphaAt(session, 20, 20), 0);
    });

    testWidgets('a row inside a MOVED folder is cleared where the folder shows '
        'it', (tester) async {
      final session = await pump(tester);
      final row = await drawableRow(tester, session);
      const folder = LayerId('moved-folder');
      final cut = session.requireActiveCut;
      session.repository.replaceLayer(layer: row.copyWith(folderId: folder));
      session.repository.insertLayer(
        cutId: cut.id,
        layer: createFolderLayer(
          id: folder,
          name: 'F',
        ).copyWith(transformTrack: movedRight(session, 100)),
        index: cut.layers.indexWhere((layer) => layer.id == row.id) + 1,
      );
      session.refreshAfterCutCommand();
      session.selectLayer(row.id);
      await tester.pump();
      inkThroughCoordinator(session);

      // The ink at artwork x 0..40 shows at canvas x 100..140.
      await clearUnder(tester, session, box(100, 140));

      expect(alphaAt(session, 20, 20), 0);
      expect(
        alphaAt(session, 120, 20),
        255,
        reason: 'what sits at the marquee\'s ARTWORK coordinates is not what '
            'it was drawn over',
      );
    });
  });
}

/// [row]'s twin — the same kind, its own id and its own three cels.
Layer _twinOf(Layer row, String id) => row.copyWith(
  id: LayerId(id),
  frames: [
    for (var i = 0; i < 3; i++)
      Frame(id: FrameId('$id-cel-$i'), duration: 1, strokes: const []),
  ],
  timeline: {
    for (var i = 0; i < 3; i++)
      i: TimelineExposure.drawing(FrameId('$id-cel-$i'), length: 1),
  },
);

/// The collaborator that owns the laws above, under its OWN name.
///
/// 🚨`tool/mutation_run.dart` picks the tests that will witness a mutation by
/// asking which tests IMPORT the file. Round 8 carved ~50 collaborators out of
/// `EditorSessionManager` and every pin still arrived through the session, so
/// 63 of the 71 files under `lib/src/ui/session/` reported UNNAMED and the
/// campaign skipped exactly the code that round wrote. ⛔Widening the runner to
/// transitive reachability was tried and reverted (one small file drew 390
/// namers); a collaborator that holds a law gets a test that names it instead.
PixelVerbs pixelVerbsOf(EditorSessionManager session) =>
    session.pixelVerbs;
