import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte_key.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_link_registry.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart' show CelRead;
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/editing/layer_merge_plan.dart'
    show LayerMergeChange;
import 'package:anicel/src/services/import/raster_cel_import.dart'
    show bakeCelSurface;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/merge_layer_rows.dart';

import '../../helpers/cel_text_fixture.dart' show pixelOf;
import '../../helpers/wait_window.dart';

/// 🗣️I-78 (유저 2026-10-06 · 10-28): MERGE makes the selected rows ONE row
/// whose cels are what they showed together — every row baked shown (Q7),
/// the result standing where the topmost stood (Q2) — as one undo step, and
/// asks first where the merge changes how they look (Q1 「포토샵 · 클튜처럼
/// (+경고)」).
void main() {
  const tile = defaultCelTileSize;
  const canvasSize = CanvasSize(width: 4 * tile, height: 3 * tile);
  const cutId = CutId('cut');
  const red = [200, 0, 0, 255];
  const green = [0, 200, 0, 255];
  const blue = [0, 0, 200, 255];

  /// Opaque tiles of [rgba] at [coords].
  BitmapSurface inkAt(List<TileCoord> coords, List<int> rgba) {
    final pixels = Uint8List(tile * tile * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels.setRange(i, i + 4, rgba);
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: tile,
      tiles: {
        for (final coord in coords)
          coord: BitmapTile(size: tile, pixels: Uint8List.fromList(pixels)),
      },
    );
  }

  Layer row(String id, {bool isVisible = true, LayerBlendMode? blendMode}) =>
      Layer(
        id: LayerId(id),
        name: id,
        isVisible: isVisible,
        blendMode: blendMode ?? LayerBlendMode.normal,
        frames: [
          Frame(id: FrameId('$id-1'), duration: 2, name: '1', strokes: []),
        ],
        timeline: {0: TimelineExposure.drawing(FrameId('$id-1'), length: 2)},
      );

  /// A synced attach row `r` riding `a` — its ink blue in the canvas's first
  /// tile of the second row, at half strength.
  final rider = Layer(
    id: const LayerId('r'),
    name: 'r',
    attachedToLayerId: const LayerId('a'),
    opacity: 0.5,
    frames: [
      Frame(id: const FrameId('r-1'), duration: 2, name: '1', strokes: []),
    ],
    baseFrameLinks: {const FrameId('a-1'): const FrameId('r-1')},
    timeline: const {},
  );

  /// [layer] parted into two blocks a frame long: its cel `1`, then `2`.
  Layer parted(Layer layer) => layer.copyWith(
    frames: [
      for (final cel in ['1', '2'])
        Frame(
          id: FrameId('${layer.id.value}-$cel'),
          duration: 1,
          name: cel,
          strokes: [],
        ),
    ],
    timeline: {
      for (final (index, cel) in ['1', '2'].indexed)
        index: TimelineExposure.drawing(
          FrameId('${layer.id.value}-$cel'),
          length: 1,
        ),
    },
  );

  /// A cut of `b` under `a`, `b`'s ink red in the canvas's second column of
  /// tiles and `a`'s green in its third, both rows selected — `a` moved by
  /// [aMoves], ridden by [rider] when [aRidden], and [parted] when
  /// [aParted], its second cel blue over its first's tile and the canvas's
  /// first of the second row.
  /// A session over one cut of [layers] and the camera, its pasteboard
  /// [pasteboardInUse].
  EditorSessionManager sessionOf(
    List<Layer> layers, {
    bool pasteboardInUse = true,
  }) => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('project'),
      name: 'Project',
      cameraSize: canvasSize,
      pasteboardInUse: pasteboardInUse,
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'Track',
          cuts: [
            Cut(
              id: cutId,
              name: 'Cut',
              duration: 2,
              canvasSize: canvasSize,
              layers: [...layers, createCameraLayer(cutId: cutId)],
            ),
          ],
        ),
      ],
      createdAt: DateTime.utc(2026),
    ),
  );

  EditorSessionManager session({
    bool bShown = true,
    LayerBlendMode? aBlend,
    TransformTrack? aMoves,
    bool aRidden = false,
    bool aParted = false,
    bool pasteboardInUse = true,
  }) {
    final a = row('a', blendMode: aBlend).copyWith(transformTrack: aMoves);
    final s = sessionOf([
      row('b', isVisible: bShown),
      if (aParted) parted(a) else a,
      if (aRidden) rider,
    ], pasteboardInUse: pasteboardInUse);
    final cut = s.requireActiveCut;
    final store = s.renderCaches.brushFrameStore;
    for (final (id, cel, coords, rgba) in [
      // A tile of b's past the canvas's left edge — a pan's background.
      ('b', '1', [TileCoord(x: 1, y: 0), TileCoord(x: -1, y: 0)], red),
      ('a', '1', [TileCoord(x: 2, y: 0)], green),
      if (aRidden) ('r', '1', [TileCoord(x: 0, y: 1)], blue),
      if (aParted)
        ('a', '2', [TileCoord(x: 2, y: 0), TileCoord(x: 0, y: 1)], blue),
    ]) {
      bakeCelSurface(
        store,
        s.brushFrameKeyForCut(cut, LayerId(id), FrameId('$id-$cel')),
        inkAt(coords, rgba),
      );
    }
    s.rowSelection.value = const [
      LayerRowAddress(LayerId('a')),
      LayerRowAddress(LayerId('b')),
    ];
    return s;
  }

  Future<BuildContext> hostedContext(WidgetTester tester) async {
    late BuildContext hosted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              hosted = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return hosted;
  }

  /// The one cel the row [id] holds — the merged row `a` by default — as
  /// its picture.
  BitmapSurface mergedCel(EditorSessionManager s, [String id = 'a']) {
    final cut = s.requireActiveCut;
    final merged = cut.layers.byId(LayerId(id))!;
    return s.renderCaches.brushFrameStore.bakedSurfaceOrNull(
      s.brushFrameKeyForCut(cut, merged.id, merged.frames.single.id),
      read: CelRead.look,
    )!;
  }

  /// [cel]'s pixel at canvas ([x], [y]) — past the canvas too.
  List<int>? at(BitmapSurface cel, int x, int y) {
    final size = cel.tileSize;
    final (column, row) = ((x / size).floor(), (y / size).floor());
    return pixelOf(
      cel,
      TileCoord(x: column, y: row),
      x - column * size,
      y - row * size,
    );
  }

  /// Whether the press's wait window has gone.
  bool windowGone() => find
      .byKey(const ValueKey<String>('layer-merge-progress'))
      .evaluate()
      .isEmpty;

  /// Whether the press has made the rows one and its window has gone.
  bool merged(EditorSessionManager s) =>
      s.requireActiveCut.layers.byId(const LayerId('b')) == null &&
      windowGone();

  /// Whether the press has made `a`'s blocks one and its window has gone.
  bool blocksMerged(EditorSessionManager s) =>
      s.requireActiveCut.layers.byId(const LayerId('a'))!.timeline.length ==
          1 &&
      windowGone();

  testWidgets('🎯the rows become one row whose cel is what they showed '
      'together — a hidden row baked shown (Q7) — and one undo gives both '
      'back', (tester) async {
    final s = session(bShown: false);
    addTearDown(s.dispose);
    // Standing on a row the merge does not take: it stands on the merged
    // row after, as it would on any row it made.
    s.selectLayer(cameraLayerIdForCut(cutId));
    s.rowSelection.value = const [
      LayerRowAddress(LayerId('a')),
      LayerRowAddress(LayerId('b')),
    ];
    expect(s.activeLayer?.id, cameraLayerIdForCut(cutId), reason: 'premise');
    final before = s.requireActiveCut.layers;
    expect(s.layerMerging.mergesSelection, isTrue, reason: 'the button lit');
    final context = await hostedContext(tester);

    unawaited(mergeLayerRows(context, s));
    await settleBehindTheWaitWindow(tester, () => merged(s));

    final cut = s.requireActiveCut;
    expect([for (final layer in cut.layers) layer.id], [
      const LayerId('a'),
      cameraLayerIdForCut(cutId),
    ]);
    expect(cut.layers.first.frames, hasLength(1), reason: 'one picture');
    final cel = mergedCel(s);
    expect([at(cel, 160, 40), at(cel, 288, 40)], [red, green]);
    expect(at(cel, -80, 40), red, reason: 'past the canvas, as it showed');
    expect(at(cel, 40, 40)?[3] ?? 0, 0, reason: 'nothing where neither drew');
    expect(s.rowSelection.value, isEmpty);
    expect(s.activeLayer?.id, const LayerId('a'));

    s.undo();
    expect(s.requireActiveCut.layers, before);
    s.redo();
    expect(
      [at(mergedCel(s), 160, 40), at(mergedCel(s), 288, 40)],
      [red, green],
    );
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🎯an attach row the merge does not take rides the result, its '
      'cel baked wearing what it wore of its base — the result moves '
      'nowhere now — and one undo gives every row back (Q8)', (tester) async {
    final s = session(
      // A tile to the right of the canvas's centre.
      aMoves: TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>.empty().withKey(
          0,
          CanvasPoint(x: 384, y: 192),
        ),
      ),
      aRidden: true,
    );
    addTearDown(s.dispose);
    final before = s.requireActiveCut.layers;
    final context = await hostedContext(tester);

    unawaited(mergeLayerRows(context, s));
    await settleBehindTheWaitWindow(tester, () => merged(s));

    final cut = s.requireActiveCut;
    expect([for (final layer in cut.layers) layer.id], [
      const LayerId('a'),
      const LayerId('r'),
      cameraLayerIdForCut(cutId),
    ]);
    final result = cut.layers.first;
    expect(result.transformTrack.isEmpty, isTrue);
    final cel = mergedCel(s);
    expect([at(cel, 160, 40), at(cel, 416, 40)], [red, green]);
    expect(at(cel, 288, 40)?[3] ?? 0, 0, reason: 'a was drawn moved');
    final ridden = cut.layers.byId(const LayerId('r'))!;
    expect(ridden.attachedToLayerId, result.id);
    expect(ridden.baseFrameLinks, {
      result.frames.single.id: ridden.frames.single.id,
    });
    final riderCel = mergedCel(s, 'r');
    expect(at(riderCel, 160, 160), blue, reason: 'it wore a\'s move');
    expect(at(riderCel, 40, 160)?[3] ?? 0, 0);
    expect(at(riderCel, 416, 40)?[3] ?? 0, 0, reason: 'a\'s own is not in it');
    expect(ridden.opacity, 0.5, reason: 'its strength stays on its row');

    s.undo();
    expect(s.requireActiveCut.layers, before);
    s.redo();
    expect(at(mergedCel(s, 'r'), 160, 160), blue);
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🎯a row\'s blocks a band holds become one block over a cel '
      'laid of theirs — the leftmost on top — and one undo gives them back '
      '(Q4)', (tester) async {
    final s = session(aParted: true);
    addTearDown(s.dispose);
    s.rowSelection.value = const [];
    s.frameRangeSelection.value = const TimelineFrameRangeSelection(
      layerId: LayerId('a'),
      startIndex: 0,
      endIndexExclusive: 2,
    );
    final before = s.requireActiveCut.layers;
    expect(s.layerMerging.mergesBand, isTrue, reason: 'the button lit');
    final context = await hostedContext(tester);

    unawaited(mergeBlocks(context, s));
    await settleBehindTheWaitWindow(tester, () => blocksMerged(s));

    final cut = s.requireActiveCut;
    final block = cut.layers.byId(const LayerId('a'))!.timeline[0]!;
    expect(block.length, 2);
    final cel = mergedCel(s);
    expect([at(cel, 288, 40), at(cel, 40, 160)], [green, blue]);
    expect(at(cel, 160, 40)?[3] ?? 0, 0, reason: 'b is not in it');
    expect(cut.layers.byId(const LayerId('b')), before.first);
    expect(s.frameRangeSelection.value, isNull);

    s.undo();
    expect(s.requireActiveCut.layers, before);
    s.redo();
    expect(
      [at(mergedCel(s), 288, 40), at(mergedCel(s), 40, 160)],
      [green, blue],
    );
    s.playbackRig.prerenderScheduler.cancel();
  });

  /// A cel of straight [shade]s in each tile at [coords] — clear wherever
  /// the shade's alpha is nothing.
  BitmapSurface shadedAt(
    List<TileCoord> coords,
    List<int> Function(int x, int y) shade,
  ) {
    final pixels = Uint8List(tile * tile * 4);
    for (var y = 0; y < tile; y += 1) {
      for (var x = 0; x < tile; x += 1) {
        final rgba = shade(x, y);
        if (rgba[3] > 0) {
          pixels.setRange((y * tile + x) * 4, (y * tile + x + 1) * 4, rgba);
        }
      }
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: tile,
      tiles: {
        for (final coord in coords)
          coord: BitmapTile(size: tile, pixels: Uint8List.fromList(pixels)),
      },
    );
  }

  /// Every alpha across a tile, the colours down it — and [turned], the
  /// alphas down and the colours across, so that where the two lie one
  /// over the other every alpha meets every alpha.
  List<int> Function(int x, int y) everyShade({bool turned = false}) =>
      (x, y) {
        final (along, across) = turned ? (y, x) : (x, y);
        return [
          across * 2,
          255 - across * 2,
          (along + across * 3) & 255,
          along * 255 ~/ (tile - 1),
        ];
      };

  testWidgets('🎯a row\'s blocks merged lay its cels as a merge of rows lays '
      'the same cels each on a row of its own, in the same order — to the '
      'byte, where a half-clear cel lies over another and at the wall\'s '
      'edges (🧭관제 2026-11-14 (1): 「블록 머지 = 레이어 머지」)', (
    tester,
  ) async {
    final context = await hostedContext(tester);
    // `b` under `a`, each a cel of its own.
    final byRows = sessionOf([row('b'), row('a')]);
    addTearDown(byRows.dispose);
    final rowsCut = byRows.requireActiveCut;
    final wall = byRows.pasteboardOf(canvasSize);
    // Where both lie: a tile inside the canvas, and the tiles the wall's
    // left and right edges run through.
    final coords = [
      TileCoord(x: 1, y: 0),
      TileCoord(x: (wall.left / tile).floor(), y: 1),
      TileCoord(x: ((wall.rightExclusive - 1) / tile).floor(), y: 2),
    ];
    final under = shadedAt(coords, everyShade());
    final over = shadedAt(coords, everyShade(turned: true));
    for (final (id, cel) in [('b', under), ('a', over)]) {
      bakeCelSurface(
        byRows.renderCaches.brushFrameStore,
        byRows.brushFrameKeyForCut(rowsCut, LayerId(id), FrameId('$id-1')),
        cel,
      );
    }
    byRows.rowSelection.value = const [
      LayerRowAddress(LayerId('a')),
      LayerRowAddress(LayerId('b')),
    ];
    unawaited(mergeLayerRows(context, byRows));
    await settleBehindTheWaitWindow(tester, () => merged(byRows));

    // `a`'s two blocks: the leftmost lies on top (Q17).
    final byBlocks = sessionOf([parted(row('a'))]);
    addTearDown(byBlocks.dispose);
    final blocksCut = byBlocks.requireActiveCut;
    for (final (cel, surface) in [('1', over), ('2', under)]) {
      bakeCelSurface(
        byBlocks.renderCaches.brushFrameStore,
        byBlocks.brushFrameKeyForCut(
          blocksCut,
          const LayerId('a'),
          FrameId('a-$cel'),
        ),
        surface,
      );
    }
    byBlocks.frameRangeSelection.value = const TimelineFrameRangeSelection(
      layerId: LayerId('a'),
      startIndex: 0,
      endIndexExclusive: 2,
    );
    unawaited(mergeBlocks(context, byBlocks));
    await settleBehindTheWaitWindow(tester, () => blocksMerged(byBlocks));

    final (rows, blocks) = (mergedCel(byRows), mergedCel(byBlocks));
    expect(
      at(rows, tile + 100, 100)?[3],
      inExclusiveRange(0, 255),
      reason: '⛔premise: half-clear over half-clear',
    );
    expect(
      rows.tiles.keys.toSet(),
      containsAll(coords),
      reason: '⛔premise: the wall\'s edges are in it',
    );
    expect(blocks.tiles.keys.toSet(), rows.tiles.keys.toSet());
    var apart = 0;
    String? first;
    for (final MapEntry(key: coord, value: laid) in rows.tiles.entries) {
      final other = blocks.tiles[coord]!.pixels;
      for (var byte = 0; byte < laid.pixels.length; byte += 1) {
        if (laid.pixels[byte] != other[byte]) {
          apart += 1;
          first ??= '$coord byte $byte: ${laid.pixels[byte]} by rows, '
              '${other[byte]} by blocks';
        }
      }
    }
    expect(apart, 0, reason: first);
    byRows.playbackRig.prerenderScheduler.cancel();
    byBlocks.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🎯a row\'s blocks merged lay its cels as they are — its keys '
      'and its fx stay on the row — and a synced row riding it merges its '
      'cels in the same order, the leftmost on top (Q18 ⓐ · ⓔ)', (
    tester,
  ) async {
    final a = parted(row('a')).copyWith(
      transformTrack: TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>.empty().withKey(
          0,
          CanvasPoint(x: 384, y: 192),
        ),
      ),
      effects: [
        LayerEffect(
          id: const EffectId('e-darker'),
          kind: EffectKind.brightnessContrast,
          parameters: {'brightness': EffectParameter(value: -40)},
        ),
      ],
    );
    final riding = Layer(
      id: const LayerId('r'),
      name: 'r',
      attachedToLayerId: const LayerId('a'),
      frames: [
        for (final cel in ['1', '2'])
          Frame(id: FrameId('r-$cel'), duration: 1, name: cel, strokes: []),
      ],
      baseFrameLinks: {
        const FrameId('a-1'): const FrameId('r-1'),
        const FrameId('a-2'): const FrameId('r-2'),
      },
      timeline: const {},
    );
    final s = sessionOf([a, riding]);
    addTearDown(s.dispose);
    final cut = s.requireActiveCut;
    for (final (id, cel, coords, rgba) in [
      ('a', '1', [TileCoord(x: 2, y: 0)], green),
      ('a', '2', [TileCoord(x: 2, y: 0), TileCoord(x: 0, y: 1)],
          blue),
      ('r', '1', [TileCoord(x: 1, y: 1)], red),
      ('r', '2', [TileCoord(x: 1, y: 1), TileCoord(x: 3, y: 2)],
          blue),
    ]) {
      bakeCelSurface(
        s.renderCaches.brushFrameStore,
        s.brushFrameKeyForCut(cut, LayerId(id), FrameId('$id-$cel')),
        inkAt(coords, rgba),
      );
    }
    s.frameRangeSelection.value = const TimelineFrameRangeSelection(
      layerId: LayerId('a'),
      startIndex: 0,
      endIndexExclusive: 2,
    );
    final context = await hostedContext(tester);

    unawaited(mergeBlocks(context, s));
    await settleBehindTheWaitWindow(tester, () => blocksMerged(s));

    final after = s.requireActiveCut.layers.byId(const LayerId('a'))!;
    expect(after.transformTrack, a.transformTrack, reason: 'on the row');
    expect(after.effects, a.effects, reason: 'on the row');
    final cel = mergedCel(s);
    expect(
      [at(cel, 288, 40), at(cel, 40, 160)],
      [green, blue],
      reason: 'where they lie, as they are: not moved, not darkened',
    );
    final ridden = mergedCel(s, 'r');
    expect([at(ridden, 160, 160), at(ridden, 416, 288)], [red, blue]);
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a merge that changes how the rows look asks first, and the '
      'answer no leaves them as they were (Q1)', (tester) async {
    final s = session(aBlend: LayerBlendMode.multiply);
    addTearDown(s.dispose);
    final before = s.requireActiveCut.layers;
    final context = await hostedContext(tester);

    unawaited(mergeLayerRows(context, s));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('layer-merge-changes-dialog')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('layer-merge-changes-cancel-button')),
    );
    await tester.pumpAndSettle();

    expect(s.requireActiveCut.layers, before);
    s.playbackRig.prerenderScheduler.cancel();
  });

  /// A synced attach row [id] riding `base` on its [placement] side.
  Layer riding(String id, AttachedPlacement placement) => Layer(
    id: LayerId(id),
    name: id,
    attachedToLayerId: const LayerId('base'),
    attachedPlacement: placement,
    frames: [Frame(id: FrameId('$id-1'), duration: 2, name: '1', strokes: [])],
    baseFrameLinks: {const FrameId('base-1'): FrameId('$id-1')},
    timeline: const {},
  );

  /// A reference row `still` laying a [width] × [height] file at the
  /// canvas's centre.
  Layer still(int width, int height) => row('still').copyWith(
    kind: LayerKind.image,
    mediaReference: MediaReference(
      assetPath: 'paper.png',
      pose: TransformPose(center: CanvasPoint(x: 256, y: 192)),
      pictureSize: CanvasSize(width: width, height: height),
    ),
  );

  testWidgets('the window names each change it warns of: a rider led over a '
      'picture, one led under one, a reference cut at the wall '
      '(Q13 · Q15)', (tester) async {
    final s = sessionOf([
      row('x'),
      riding('u', AttachedPlacement.below),
      row('base'),
      riding('o', AttachedPlacement.above),
      row('y'),
      still(5120, 3840),
    ]);
    addTearDown(s.dispose);
    s.rowSelection.value = const [
      LayerRowAddress(LayerId('x')),
      LayerRowAddress(LayerId('base')),
      LayerRowAddress(LayerId('y')),
      LayerRowAddress(LayerId('still')),
    ];
    final context = await hostedContext(tester);

    unawaited(mergeLayerRows(context, s));
    await tester.pumpAndSettle();

    final strings = AppText.strings;
    for (final (line, shown) in [
      (strings.tlMergeChangeRiderOver, findsOneWidget),
      (strings.tlMergeChangeRiderUnder, findsOneWidget),
      (strings.tlMergeChangeWall, findsOneWidget),
      (strings.tlMergeChangeBlend, findsNothing),
    ]) {
      expect(find.text(line), shown, reason: line);
    }
    await tester.tap(
      find.byKey(const ValueKey<String>('layer-merge-changes-cancel-button')),
    );
    await tester.pumpAndSettle();
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a bake\'s window names its changes in their order, whatever '
      'order its plan gathered them in — a track\'s conte merge gathers them '
      'cut by cut (Q20)', (tester) async {
    final s = session();
    addTearDown(s.dispose);
    final context = await hostedContext(tester);

    unawaited(
      bakeAfterAsking<LayerMergeChange>(context, s, (
        run: (
          title: 'Bake',
          icon: Icons.merge,
          windowKey: 'bake-progress',
          pictures: const [],
          land: () {},
        ),
        question: (
          slug: 'bake-changes',
          title: 'Bake?',
          body: 'Bake.',
          accept: 'Bake',
        ),
        changes: {LayerMergeChange.wall, LayerMergeChange.blend},
        lineOf: (change) => change.name,
      )),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('blend')).dy,
      lessThan(tester.getTopLeft(find.text('wall')).dy),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('bake-changes-cancel-button')),
    );
    await tester.pumpAndSettle();
    s.playbackRig.prerenderScheduler.cancel();
  });

  test('the wall it warns at is the project\'s pasteboard (Q15)', () {
    for (final (inUse, changes) in [
      (true, <LayerMergeChange>{}),
      (false, {LayerMergeChange.wall}),
    ]) {
      // Past the canvas, and inside a pasteboard three times its size.
      final s = sessionOf([row('a'), still(768, 576)], pasteboardInUse: inUse);
      addTearDown(s.dispose);
      s.rowSelection.value = const [
        LayerRowAddress(LayerId('a')),
        LayerRowAddress(LayerId('still')),
      ];

      expect(
        s.layerMerging.planOfSelection()!.changes,
        changes,
        reason: 'in use: $inUse',
      );
    }
  });

  test('…and a drawing\'s ink where the row shows it, as a reference\'s '
      'file is (Q19)', () {
    for (final (dx, inUse, changes) in [
      // b's tile past the canvas's left edge, the pasteboard's to hold.
      (128.0, true, <LayerMergeChange>{}),
      (128.0, false, {LayerMergeChange.wall}),
      // a's ink keyed past the pasteboard's right edge.
      (768.0, true, {LayerMergeChange.wall}),
    ]) {
      final s = session(
        aMoves: TransformTrack.empty().copyWith(
          position: PropertyTrack<CanvasPoint>.empty().withKey(
            0,
            CanvasPoint(x: 256 + dx, y: 192),
          ),
        ),
        pasteboardInUse: inUse,
      );
      addTearDown(s.dispose);

      expect(
        s.layerMerging.planOfSelection()!.changes,
        changes,
        reason: 'moved ${dx}px, in use: $inUse',
      );
    }
  });

  /// 🗣️I-78-Q9 (유저 2026-10-28): 「이어진 컷에서도 같이 병합한다」.
  group('a 겸용 row', () {
    const other = CutId('cut2');
    LayerLinkMember member(CutId cut, String id) => LayerLinkMember(
      trackId: const TrackId('track'),
      cutId: cut,
      layerId: LayerId(id),
    );
    final before = LayerLinkRegistry(
      groups: [
        // Its cels kept under the other cut's row.
        LayerLinkGroup(
          id: 'link-9',
          members: [member(other, 'a2'), member(cutId, 'a')],
        ),
      ],
    );

    /// A session over a cut of `b` under `a` — inked as [session] inks
    /// them, both selected, `b` shown at its first frame alone — and a cut
    /// of `a2`, ONE layer with `a`, moved by [a2Moves].
    EditorSessionManager linkedSession({TransformTrack? a2Moves}) {
      final a = row('a');
      Cut cutOf(CutId id, List<Layer> layers) => Cut(
        id: id,
        name: id.value,
        duration: 2,
        canvasSize: canvasSize,
        layers: [...layers, createCameraLayer(cutId: id)],
      );
      final s = EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('project'),
          name: 'Project',
          cameraSize: canvasSize,
          tracks: [
            Track(
              id: const TrackId('track'),
              name: 'Track',
              cuts: [
                cutOf(cutId, [
                  row('b').copyWith(
                    timeline: const {
                      0: TimelineExposure.drawing(FrameId('b-1'), length: 1),
                    },
                  ),
                  a,
                ]),
                cutOf(other, [
                  a.copyWith(
                    id: const LayerId('a2'),
                    transformTrack: a2Moves,
                  ),
                ]),
              ],
            ),
          ],
          linkRegistry: before,
          createdAt: DateTime.utc(2026),
        ),
      );
      for (final (id, coord, rgba) in [
        ('b', TileCoord(x: 1, y: 0), red),
        ('a', TileCoord(x: 2, y: 0), green),
      ]) {
        bakeCelSurface(
          s.renderCaches.brushFrameStore,
          s.brushFrameKeyForCut(
            s.requireActiveCut,
            LayerId(id),
            FrameId('$id-1'),
          ),
          inkAt([coord], rgba),
        );
      }
      s.rowSelection.value = const [
        LayerRowAddress(LayerId('a')),
        LayerRowAddress(LayerId('b')),
      ];
      return s;
    }

    testWidgets('🎯merges in every cut it is in: each cut\'s result shows '
        'its own picture, the cels kept where the link table kept the '
        'row\'s — and one undo gives both cuts and the table back', (
      tester,
    ) async {
      final s = linkedSession();
      addTearDown(s.dispose);
      final layersBefore = {
        for (final id in [cutId, other]) id: s.cutById(id)!.layers,
      };
      final context = await hostedContext(tester);

      unawaited(mergeLayerRows(context, s));
      await settleBehindTheWaitWindow(tester, () => merged(s));

      /// The picture the row [id] of [cut] shows.
      BitmapSurface shown(CutId cut, String id) {
        final at = s.cutById(cut)!;
        final result = at.layers.byId(LayerId(id))!;
        return s.renderCaches.brushFrameStore.bakedSurfaceOrNull(
          s.brushFrameKeyForCut(at, result.id, result.timeline[0]!.frameId!),
          read: CelRead.look,
        )!;
      }

      final after = LayerLinkRegistry(
        groups: [
          LayerLinkGroup(
            id: 'link-1',
            members: [member(other, 'a2'), member(cutId, 'a')],
          ),
        ],
      );
      final there = shown(other, 'a2');
      expect([at(shown(cutId, 'a'), 160, 40), at(shown(cutId, 'a'), 288, 40)], [
        red,
        green,
      ]);
      expect(at(there, 288, 40), green);
      expect(at(there, 160, 40)?[3] ?? 0, 0, reason: 'b is no row of that cut');
      Layer result(CutId cut, String id) =>
          s.cutById(cut)!.layers.byId(LayerId(id))!;
      expect(
        [result(other, 'a2').frames, result(other, 'a2').frames.length],
        [result(cutId, 'a').frames, 2],
        reason: 'a alone, at the second frame here and both there, one cel',
      );
      expect(
        s.repository.requireProject().linkRegistry,
        after,
        reason: 'the results one layer, as the rows were',
      );

      s.undo();
      expect({
        for (final id in [cutId, other]) id: s.cutById(id)!.layers,
      }, layersBefore);
      expect(s.repository.requireProject().linkRegistry, before);
      s.redo();
      expect(at(shown(other, 'a2'), 288, 40), green);
      expect(s.repository.requireProject().linkRegistry, after);
      s.playbackRig.prerenderScheduler.cancel();
    });

    test('…and a picture another cut shows past the wall is warned of, as '
        'one of the cut pressed is (Q19)', () {
      final s = linkedSession(
        // a's ink keyed past the pasteboard's right edge — in cut2 alone.
        a2Moves: TransformTrack.empty().copyWith(
          position: PropertyTrack<CanvasPoint>.empty().withKey(
            0,
            CanvasPoint(x: 256 + 768, y: 192),
          ),
        ),
      );
      addTearDown(s.dispose);

      expect(s.layerMerging.planOfSelection()!.changes, {
        LayerMergeChange.wall,
      });
    });
  });

  /// 🗣️I-78-Q20 (유저 2026-10-30): 「트랙의 모든 컷에서 같이 병합」.
  group("the conte's rows", () {
    const other = CutId('cut2');

    /// A cut [id] of the conte [base] — one panel over both frames — and,
    /// riding it synced, the track's rows `K1` and `K2` as [rows] names
    /// them.
    Cut conteCut(CutId id, String base, (String, String) rows) {
      final conte = row(base).copyWith(kind: LayerKind.storyboard);
      Layer onIt(String rowId, String key) => Layer(
        id: LayerId(rowId),
        name: rowId,
        kind: LayerKind.storyboard,
        attachedToLayerId: conte.id,
        conteKey: ConteKey(key),
        frames: [
          Frame(id: FrameId('$rowId-1'), duration: 1, name: '1', strokes: []),
        ],
        baseFrameLinks: {FrameId('$base-1'): FrameId('$rowId-1')},
        timeline: const {},
      );
      return Cut(
        id: id,
        name: id.value,
        duration: 2,
        canvasSize: canvasSize,
        layers: [
          conte,
          onIt(rows.$1, 'K1'),
          onIt(rows.$2, 'K2'),
          createCameraLayer(cutId: id),
        ],
      );
    }

    testWidgets("🎯merge in every cut of the track — each cut's result its "
        'own picture, riding its conte, the track keeping one row of them — '
        'and one undo gives every cut back', (tester) async {
      final s = EditorSessionManager(
        initialProject: Project(
          id: const ProjectId('project'),
          name: 'Project',
          cameraSize: canvasSize,
          tracks: [
            Track(
              id: const TrackId('track'),
              name: 'Track',
              cuts: [
                conteCut(cutId, 's', ('k1', 'k2')),
                conteCut(other, 't', ('j1', 'j2')),
              ],
            ),
          ],
          createdAt: DateTime.utc(2026),
        ),
      );
      addTearDown(s.dispose);
      for (final (cut, id, coord, rgba) in [
        (cutId, 'k1', TileCoord(x: 1, y: 0), red),
        (cutId, 'k2', TileCoord(x: 2, y: 0), green),
        (other, 'j1', TileCoord(x: 1, y: 0), blue),
      ]) {
        bakeCelSurface(
          s.renderCaches.brushFrameStore,
          s.brushFrameKeyForCut(s.cutById(cut)!, LayerId(id), FrameId('$id-1')),
          inkAt([coord], rgba),
        );
      }
      s.rowSelection.value = const [
        LayerRowAddress(LayerId('k1')),
        LayerRowAddress(LayerId('k2')),
      ];
      final before = {
        for (final id in [cutId, other]) id: s.cutById(id)!.layers,
      };
      final context = await hostedContext(tester);

      unawaited(mergeLayerRows(context, s));
      await settleBehindTheWaitWindow(
        tester,
        () =>
            s.requireActiveCut.layers.byId(const LayerId('k1')) == null &&
            windowGone(),
      );

      /// The picture the result [id] of [cut] shows over its conte's panel.
      BitmapSurface shown(CutId cut, String id) {
        final at = s.cutById(cut)!;
        final result = at.layers.byId(LayerId(id))!;
        final conte = at.layers.byId(result.attachedToLayerId!)!;
        return s.renderCaches.brushFrameStore.bakedSurfaceOrNull(
          s.brushFrameKeyForCut(
            at,
            result.id,
            result.baseFrameLinks[conte.frames.single.id]!,
          ),
          read: CelRead.look,
        )!;
      }

      expect(
        [at(shown(cutId, 'k2'), 160, 40), at(shown(cutId, 'k2'), 288, 40)],
        [red, green],
      );
      expect(at(shown(other, 'j2'), 160, 40), blue);
      expect(
        at(shown(other, 'j2'), 288, 40)?[3] ?? 0,
        0,
        reason: "that cut's own rows, not the pressed one's",
      );
      expect(s.cutById(other)!.layers.byId(const LayerId('j1')), isNull);
      expect(
        [
          for (final entry
              in s.repository.requireProject().tracks.single.conte.entries)
            entry.key,
        ],
        [const ConteKey('K2')],
        reason: 'one row of the track',
      );

      s.undo();
      expect({
        for (final id in [cutId, other]) id: s.cutById(id)!.layers,
      }, before);
      s.playbackRig.prerenderScheduler.cancel();
    });
  });

  test('one row alone lights nothing', () {
    final s = session();
    addTearDown(s.dispose);
    s.rowSelection.value = const [LayerRowAddress(LayerId('a'))];

    expect(s.layerMerging.mergesSelection, isFalse);
    expect(s.layerMerging.planOfSelection(), isNull);
  });
}
