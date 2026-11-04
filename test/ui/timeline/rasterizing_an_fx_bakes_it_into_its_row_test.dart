import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart'
    show attachedMirrorCelId;
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/fx_basis.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_folder.dart' show createFolderLayer;
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_reference.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/property_track.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/timeline_coverage.dart'
    show exposedFrameIdAt;
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_run_behavior.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/transform_track.dart';
import 'package:anicel/src/services/brush_frame_store.dart' show CelRead;
import 'package:anicel/src/services/cut_frame_composite_plan.dart'
    show exposedCelIdAt;
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/editing/fx_bake_plan.dart'
    show BakedFrames, FxBakeChange, FxBakePlan, FxBakeWaits;
import 'package:anicel/src/services/import/raster_cel_import.dart'
    show bakeCelSurface;
import 'package:anicel/src/ui/canvas/layer_blend_shader.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/session/layer_merging.dart' show LayerMerging;
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/rasterize_fx_group.dart';

import '../../helpers/cel_text_fixture.dart' show pixelOf;
import '../../helpers/conte_track_fixture.dart';
import '../../helpers/wait_window.dart';

/// 🗣️I-120 (유저 2026-10-21 · 11-04): an fx group header's RASTERIZE bakes
/// the fx into the row's pictures as they show it (Q1 「스위치를 따른다 —
/// 늘 보이던 그대로」) — a picture wherever its value parts them — and puts
/// its values and keys back at their defaults, its line kept; an image row
/// that needs more than one picture becomes a drawing row; one undo gives
/// the row back. Q2 asks first where the fx alone, baked, changes the look;
/// Q4 switches off what changes the picture at its defaults; Q8 bakes no
/// row without a picture of its own.
void main() {
  // The difference blend below is an advanced one, drawn by the shader.
  setUpAll(LayerBlendShader.load);

  const canvasSize = CanvasSize(width: 64, height: 48);
  const cutId = CutId('cut');
  const green = [0, 160, 0, 255];
  const bright = EffectId('e-bright');

  /// Opaque tiles of [rgba] at [coords], 16 pixels a side.
  BitmapSurface inkAt(List<TileCoord> coords, List<int> rgba) {
    final pixels = Uint8List(16 * 16 * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels.setRange(i, i + 4, rgba);
    }
    return BitmapSurface(
      canvasSize: canvasSize,
      tileSize: 16,
      tiles: {
        for (final coord in coords)
          coord: BitmapTile(size: 16, pixels: Uint8List.fromList(pixels)),
      },
    );
  }

  /// A brightness fx — keyed 0 → 100 over frames 0..2 where [keyed], a
  /// still 60 otherwise — read by [basis].
  LayerEffect brightness({
    bool keyed = true,
    FxBasis basis = FxBasis.frame,
    bool enabled = true,
  }) => LayerEffect(
    id: bright,
    kind: EffectKind.brightnessContrast,
    enabled: enabled,
    basis: basis,
    parameters: {
      'brightness': keyed
          ? EffectParameter(
              track: PropertyTrack<double>(
                keys: {
                  0: const PropertyKey<double>(0),
                  2: const PropertyKey<double>(100),
                },
              ),
            )
          : EffectParameter(value: 60),
    },
  );

  /// Row `a` — its cel `1` held over frames 0..2, green in the canvas's
  /// third tile — wearing [effects] and [transformTrack].
  Layer rowA({
    List<LayerEffect>? effects,
    TransformTrack? transformTrack,
    LayerKind kind = LayerKind.animation,
    Map<int, TimelineExposure>? timeline,
    List<AudioClip> audioClips = const [],
  }) => Layer(
    id: const LayerId('a'),
    name: 'A',
    kind: kind,
    effects: effects ?? [brightness()],
    transformTrack: transformTrack,
    audioClips: audioClips,
    frames: [
      Frame(id: const FrameId('a-1'), duration: 3, name: '1', strokes: []),
    ],
    timeline:
        timeline ??
        {0: const TimelineExposure.drawing(FrameId('a-1'), length: 3)},
  );

  /// Row `r` riding [base] — synced to its cel `<base>-1`, or [free] on a
  /// timeline of its own — its cel `r-1` held over frames 0..2.
  Layer riderOf(String base, {bool free = false}) => Layer(
    id: const LayerId('r'),
    name: 'R',
    attachedToLayerId: LayerId(base),
    attachedPlacement: AttachedPlacement.above,
    attachedMode: free ? AttachedMode.free : AttachedMode.synced,
    frames: [
      Frame(id: const FrameId('r-1'), duration: 3, name: '1', strokes: []),
    ],
    baseFrameLinks: free
        ? const {}
        : {FrameId('$base-1'): const FrameId('r-1')},
    timeline: free
        ? {0: const TimelineExposure.drawing(FrameId('r-1'), length: 3)}
        : const {},
  );

  /// A session over one cut of [layers] and the camera, three frames long,
  /// `a`'s cel inked and `a` stood on.
  EditorSessionManager sessionOf(List<Layer> layers, {int duration = 3}) {
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
              Cut(
                id: cutId,
                name: 'Cut',
                duration: duration,
                canvasSize: canvasSize,
                layers: [...layers, createCameraLayer(cutId: cutId)],
              ),
            ],
          ),
        ],
        createdAt: DateTime.utc(2026),
      ),
    );
    final cut = s.requireActiveCut;
    for (final layer in cut.layers) {
      for (final cel in layer.frames) {
        bakeCelSurface(
          s.renderCaches.brushFrameStore,
          s.brushFrameKeyForCut(cut, layer.id, cel.id),
          inkAt([TileCoord(x: 2, y: 0)], green),
        );
      }
    }
    s.selectLayer(const LayerId('a'));
    return s;
  }

  Layer a(EditorSessionManager s) =>
      s.requireActiveCut.layers.byId(const LayerId('a'))!;

  /// A session over [layers] ([sessionOf]), let go after the test.
  EditorSessionManager plain(List<Layer> layers) {
    final s = sessionOf(layers);
    addTearDown(s.dispose);
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

  /// What [s]'s cut — [of], where given — shows at canvas ([x], [y]) on
  /// [frame], drawn as an export draws it.
  Future<List<int>> shownAt(
    WidgetTester tester,
    EditorSessionManager s,
    int frame,
    int x,
    int y, {
    Cut? of,
  }) async {
    final cut = of ?? s.requireActiveCut;
    final wall = s.pasteboardOf(cut.canvasSize);
    final rgba = await tester.runAsync(() async {
      final renderer = ExportFrameRenderer(
        session: s,
        background: const ui.Color(0x00000000),
      );
      try {
        final image = await renderer.renderPicture(
          cut,
          frame,
          width: wall.rect.width.round(),
          region: wall.rect,
        );
        try {
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawStraightRgba,
          ))!;
          final at = ((y - wall.top) * image.width + (x - wall.left)) * 4;
          return [for (var i = 0; i < 4; i += 1) bytes.getUint8(at + i)];
        } finally {
          image.dispose();
        }
      } finally {
        renderer.dispose();
      }
    });
    return rgba!;
  }

  /// [cel] of the row [of] as its picture, at canvas ([x], [y]).
  List<int>? celAt(
    EditorSessionManager s,
    FrameId cel,
    int x,
    int y, {
    LayerId of = const LayerId('a'),
  }) {
    final cut = s.requireActiveCut;
    final surface = s.renderCaches.brushFrameStore.bakedSurfaceOrNull(
      s.brushFrameKeyForCut(cut, of, cel),
      read: CelRead.look,
    )!;
    final size = surface.tileSize;
    final (column, row) = ((x / size).floor(), (y / size).floor());
    return pixelOf(
      surface,
      TileCoord(x: column, y: row),
      x - column * size,
      y - row * size,
    );
  }

  /// The colours of [seen] told apart by value — a list is only ever the
  /// same as itself.
  Set<String> coloursOf(List<List<int>> seen) => {
    for (final rgba in seen) rgba.join(','),
  };

  /// What RASTERIZE in [rowId]'s header for [effectId], scoped to [band],
  /// answers in [s]: `bakes`, what it waits for by name, or
  /// `nothing`.
  String outcomeOf(
    EditorSessionManager s,
    LayerId rowId,
    EffectId? effectId, [
    BakedFrames? band,
  ]) => switch (s.layerMerging.planOfFx(rowId, effectId, band: band)) {
    FxBakePlan() => 'bakes',
    FxBakeWaits(:final why) => why.name,
    null => 'nothing',
  };

  /// The cel `a` shows at each of frames 0..2.
  List<FrameId?> shownCels(EditorSessionManager s) => [
    for (var frame = 0; frame < 3; frame += 1)
      exposedFrameIdAt(a(s).timeline, frame),
  ];

  /// Presses `a`'s group header RASTERIZE for [effectId] — the transform's
  /// where null — scoped to [band] where one is given, and waits out its
  /// window.
  Future<void> rasterize(
    WidgetTester tester,
    EditorSessionManager s, [
    EffectId? effectId = bright,
    BakedFrames? band,
  ]) async {
    final before = a(s);
    final context = await hostedContext(tester);
    unawaited(
      rasterizeFxGroup(
        context,
        s,
        const LayerId('a'),
        effectId,
        'fx',
        band: band,
      ),
    );
    await settleBehindTheWaitWindow(
      tester,
      () =>
          a(s) != before &&
          find
              .byKey(const ValueKey<String>('fx-rasterize-progress'))
              .evaluate()
              .isEmpty,
    );
  }

  testWidgets('🎯a keyed fx read by the frame is baked a picture to a value '
      '— the cel parted with tails — the row shows what it showed, the fx '
      'stays at its defaults, and one undo gives the row back', (
    tester,
  ) async {
    final s = sessionOf([rowA()]);
    addTearDown(s.dispose);
    final before = s.requireActiveCut.layers;
    final seen = [
      for (var frame = 0; frame < 3; frame += 1)
        await shownAt(tester, s, frame, 36, 5),
    ];
    expect(coloursOf(seen), hasLength(3), reason: '⛔전제: every frame its own');
    expect(s.layerMerging.bakesFx(const LayerId('a'), bright), isTrue);

    await rasterize(tester, s);

    final row = a(s);
    expect([for (final cel in row.frames) cel.name], ['1', '1-2', '1-3']);
    expect(
      row.timeline.map((start, block) => MapEntry(start, block.length)),
      {0: 1, 1: 1, 2: 1},
    );
    expect(shownCels(s).toSet(), hasLength(3));
    expect(
      row.frames.map((cel) => cel.id),
      isNot(contains(const FrameId('a-1'))),
    );
    expect(
      row.effects.single,
      LayerEffect(id: bright, kind: EffectKind.brightnessContrast),
    );
    expect([
      for (var frame = 0; frame < 3; frame += 1)
        await shownAt(tester, s, frame, 36, 5),
    ], seen, reason: 'as it showed');
    expect([
      for (final cel in shownCels(s)) celAt(s, cel!, 36, 5),
    ], seen, reason: 'each picture baked in its cel');

    s.undo();
    expect(s.requireActiveCut.layers, before);
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🎯read by the block, the fx is one picture to a block: the '
      'cel keeps its name and its block, and the row shows what it showed', (
    tester,
  ) async {
    final s = sessionOf([rowA(effects: [brightness(basis: FxBasis.block)])]);
    addTearDown(s.dispose);
    final seen = await shownAt(tester, s, 2, 36, 5);

    await rasterize(tester, s);

    final row = a(s);
    expect([for (final cel in row.frames) cel.name], ['1']);
    expect(row.timeline.keys, [0]);
    expect(row.timeline[0]!.length, 3);
    expect(row.effects.single.basis, FxBasis.block, reason: 'its switch stays');
    expect(await shownAt(tester, s, 2, 36, 5), seen);
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🎯the transform rasterized moves the pictures where they '
      'showed, and the row stands still after — its fx untouched', (
    tester,
  ) async {
    final s = sessionOf([
      rowA(
        effects: [brightness(keyed: false, enabled: false)],
        transformTrack: TransformTrack.empty().copyWith(
          position: PropertyTrack<CanvasPoint>.empty().withKey(
            0,
            CanvasPoint(x: 48, y: 24),
          ),
        ),
      ),
    ]);
    addTearDown(s.dispose);
    final seen = [
      await shownAt(tester, s, 0, 52, 5),
      await shownAt(tester, s, 0, 36, 5),
    ];
    expect(seen.first, green, reason: '⛔전제: moved 16 to the right');

    await rasterize(tester, s, null);

    final row = a(s);
    expect(row.transformTrack.isEmpty, isTrue);
    expect(row.effects.single, brightness(keyed: false, enabled: false));
    expect([
      await shownAt(tester, s, 0, 52, 5),
      await shownAt(tester, s, 0, 36, 5),
    ], seen);
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🎯what stays on the row — its opacity, a transform that '
      'moves, an fx after the one baked — shows over the baked pictures as '
      'it showed over the cel', (tester) async {
    // Brighter, not darker: a colour fx after one that pushes past white
    // would pull back what the baked picture clipped — I-120-Q13 asks
    // what to do there.
    final brighter = LayerEffect(
      id: const EffectId('e-after'),
      kind: EffectKind.brightnessContrast,
      parameters: {'brightness': EffectParameter(value: 40)},
    );
    final moving = TransformTrack.empty().copyWith(
      position: PropertyTrack<CanvasPoint>.empty()
          .withKey(0, CanvasPoint(x: 32, y: 24))
          .withKey(2, CanvasPoint(x: 48, y: 24)),
    );
    final s = sessionOf([
      rowA(
        effects: [brightness(), brighter],
        transformTrack: moving,
      ).copyWith(opacity: 0.5),
    ]);
    addTearDown(s.dispose);
    Future<List<List<int>>> seenNow() async => [
      for (var frame = 0; frame < 3; frame += 1)
        for (final x in [44, 52]) await shownAt(tester, s, frame, x, 5),
    ];
    final seen = await seenNow();
    expect(
      seen.where((rgba) => rgba[3] > 0 && rgba[3] < 255),
      isNotEmpty,
      reason: '⛔전제: half seen through',
    );
    expect(coloursOf(seen).length, greaterThan(3), reason: '⛔전제: it moves');

    await rasterize(tester, s);

    final row = a(s);
    expect(
      (row.opacity, row.transformTrack, row.effects.last),
      (0.5, moving, brighter),
    );
    expect(await seenNow(), seen);
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🎯a bundle read by the block goes on reading the head it '
      'read where the bake parts its block — the row shows what it showed', (
    tester,
  ) async {
    final s = sessionOf([
      rowA(
        transformTrack: TransformTrack.empty().copyWith(
          position: PropertyTrack<CanvasPoint>.empty()
              .withKey(0, CanvasPoint(x: 32, y: 24))
              .withKey(2, CanvasPoint(x: 48, y: 24)),
        ),
      ).copyWith(transformBasis: FxBasis.block),
    ]);
    addTearDown(s.dispose);
    Future<List<List<int>>> seenNow() async => [
      for (var frame = 0; frame < 3; frame += 1)
        for (final x in [36, 52]) await shownAt(tester, s, frame, x, 5),
    ];
    final seen = await seenNow();
    expect(seen[4][3], 255, reason: '⛔전제: still on the head at frame 2');

    await rasterize(tester, s);

    expect(a(s).timeline.keys, [0, 1, 2], reason: '⛔전제: its block parted');
    expect(await seenNow(), seen);
    s.playbackRig.prerenderScheduler.cancel();
  });

  final repeatedHold = {
    0: const TimelineExposure.drawing(
      FrameId('a-1'),
      length: 1,
      endEdge: TimelineRunEdgeMark(mode: TimelineRunEdgeMode.repeat),
    ),
  };

  testWidgets('a still fx over a repeated hold is one picture, and the '
      'repeat stays a repeat', (tester) async {
    final s = sessionOf([
      rowA(effects: [brightness(keyed: false)], timeline: repeatedHold),
    ]);
    addTearDown(s.dispose);
    Map<int, (int?, bool)> runs() => a(s).timeline.map(
      (start, block) => MapEntry(start, (block.length, block.ghost)),
    );
    final before = runs();
    expect(before.values.where((run) => run.$2), isNotEmpty);
    final seen = await shownAt(tester, s, 2, 36, 5);

    await rasterize(tester, s);

    expect(a(s).frames, hasLength(1));
    expect(runs(), before);
    expect(await shownAt(tester, s, 2, 36, 5), seen);
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🚨Q2 — a bake that changes how the row looks asks first: no '
      'leaves the row as it was, yes bakes it', (tester) async {
    final s = sessionOf([
      rowA(
        effects: [
          LayerEffect(id: const EffectId('e-key'), kind: EffectKind.colorKey),
          brightness(),
        ],
      ),
    ]);
    addTearDown(s.dispose);
    final before = a(s);
    final context = await hostedContext(tester);
    Future<void> press() async {
      unawaited(
        rasterizeFxGroup(context, s, const LayerId('a'), bright, 'fx'),
      );
      await tester.pumpAndSettle();
    }

    await press();
    expect(
      find.byKey(const ValueKey<String>('fx-rasterize-changes-dialog')),
      findsOneWidget,
    );
    expect(find.text(AppText.strings.tlFxBakeChangeOrder), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('fx-rasterize-changes-cancel-button')),
    );
    await tester.pumpAndSettle();
    expect(a(s), before);

    await press();
    await tester.tap(
      find.byKey(const ValueKey<String>('fx-rasterize-changes-confirm-button')),
    );
    await settleBehindTheWaitWindow(
      tester,
      () =>
          a(s) != before &&
          find
              .byKey(const ValueKey<String>('fx-rasterize-progress'))
              .evaluate()
              .isEmpty,
    );
    expect(
      a(s).effects.last,
      LayerEffect(id: bright, kind: EffectKind.brightnessContrast),
    );
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a hidden row is baked as it would show, its eye kept shut', (
    tester,
  ) async {
    final shown = sessionOf([rowA(effects: [brightness(keyed: false)])]);
    final hidden = sessionOf([
      rowA(effects: [brightness(keyed: false)]).copyWith(isVisible: false),
    ]);
    addTearDown(shown.dispose);
    addTearDown(hidden.dispose);

    await rasterize(tester, shown);
    await rasterize(tester, hidden);

    final ink = celAt(shown, a(shown).frames.single.id, 36, 5);
    expect(ink, isNot(green), reason: '⛔전제: brightened');
    expect(celAt(hidden, a(hidden).frames.single.id, 36, 5), ink);
    expect(a(hidden).isVisible, isFalse);
    shown.playbackRig.prerenderScheduler.cancel();
    hidden.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🎯what the row lays over the rows under it — its blend, its '
      'clip — stays on the row, and lays the baked pictures as it laid the '
      'cel', (tester) async {
    final s = sessionOf([
      Layer(
        id: const LayerId('b'),
        name: 'B',
        frames: [
          Frame(id: const FrameId('b-1'), duration: 3, name: '1', strokes: []),
        ],
        timeline: {
          0: const TimelineExposure.drawing(FrameId('b-1'), length: 3),
        },
      ),
      rowA(
        effects: [brightness(keyed: false)],
      ).copyWith(clipsToBelow: true, blendMode: LayerBlendMode.difference),
    ]);
    addTearDown(s.dispose);
    // `a` over two tiles, `b` under the first alone: the clip keeps `a`
    // where `b` is.
    bakeCelSurface(
      s.renderCaches.brushFrameStore,
      s.brushFrameKeyForCut(
        s.requireActiveCut,
        const LayerId('a'),
        const FrameId('a-1'),
      ),
      inkAt([TileCoord(x: 2, y: 0), TileCoord(x: 3, y: 0)], green),
    );
    Future<List<List<int>>> seenNow() async => [
      await shownAt(tester, s, 0, 36, 5),
      await shownAt(tester, s, 0, 52, 5),
    ];
    final seen = await seenNow();
    expect(seen.last[3], 0, reason: '⛔전제: clipped off where b is not');
    expect(seen.first, isNot(green), reason: '⛔전제: a laid over b');

    await rasterize(tester, s);

    expect(
      (a(s).clipsToBelow, a(s).blendMode),
      (true, LayerBlendMode.difference),
    );
    expect(await seenNow(), seen);
    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a hold repeated past its run is made of blocks of its own '
      'where each repeat shows another picture', (tester) async {
    final s = sessionOf([rowA(timeline: repeatedHold)]);
    addTearDown(s.dispose);
    expect(
      a(s).timeline.values.where((block) => block.ghost),
      isNotEmpty,
      reason: '⛔전제: the repeat shows the cel again',
    );
    final seen = [
      for (var frame = 0; frame < 3; frame += 1)
        await shownAt(tester, s, frame, 36, 5),
    ];

    await rasterize(tester, s);

    expect(shownCels(s).toSet(), hasLength(3));
    expect([
      for (var frame = 0; frame < 3; frame += 1)
        await shownAt(tester, s, frame, 36, 5),
    ], seen);
    s.playbackRig.prerenderScheduler.cancel();
  });

  group('the plan', () {
    test('an image row that needs more than one picture becomes a drawing '
        'row; one that needs one stays an image', () {
      final parted = plain([rowA(kind: LayerKind.image)]);
      final still = plain([
        rowA(kind: LayerKind.image, effects: [brightness(keyed: false)]),
      ]);
      expect([
        parted.layerMerging.bakeOf(const LayerId('a'), bright)!.row.kind,
        still.layerMerging.bakeOf(const LayerId('a'), bright)!.row.kind,
      ], [LayerKind.animation, LayerKind.image]);
    });

    test('a cel\'s sounds go with its first picture', () {
      final s = plain([
        rowA(
          audioClips: [
            AudioClip(filePath: 'ping.wav', frameId: const FrameId('a-1')),
          ],
        ),
      ]);
      final row = s.layerMerging.bakeOf(const LayerId('a'), bright)!.row;
      expect(row.audioClips.single.frameId, row.frames.first.id);
    });

    test('🚨Q2 — an fx on that runs before the one baked asks first; one '
        'off does not; the transform asks first under any fx on', () {
      LayerEffect key({bool enabled = true}) => LayerEffect(
        id: const EffectId('e-key'),
        kind: EffectKind.colorKey,
        enabled: enabled,
      );
      Set<FxBakeChange> changes(List<LayerEffect> effects, EffectId? baked) =>
          plain([rowA(effects: effects)]).layerMerging
              .bakeOf(const LayerId('a'), baked)!
              .changes;

      expect([
        changes([key(), brightness()], bright),
        changes([key(enabled: false), brightness()], bright),
        changes([brightness(), key()], bright),
        changes([brightness()], null),
        changes([brightness(enabled: false)], null),
      ], [
        {FxBakeChange.order},
        <FxBakeChange>{},
        <FxBakeChange>{},
        {FxBakeChange.order},
        <FxBakeChange>{},
      ]);
    });

    test('🚨Q4 — the cel number, which writes at its defaults, is switched '
        'off; a fx that changes nothing at its defaults stays on', () {
      const number = EffectId('e-number');
      final s = plain([
        rowA(
          effects: [
            LayerEffect(id: number, kind: EffectKind.celNumber),
            brightness(),
          ],
        ),
      ]);
      final verbs = s.layerMerging;
      expect([
        verbs.bakeOf(const LayerId('a'), number)!.row.effects.first.enabled,
        verbs.bakeOf(const LayerId('a'), bright)!.row.effects.last.enabled,
      ], [false, true]);
    });

    test('a picture past the wall is warned of, as a merge warns of it', () {
      final s = plain([
        rowA(
          effects: const [],
          transformTrack: TransformTrack.empty().copyWith(
            position: PropertyTrack<CanvasPoint>.empty().withKey(
              0,
              CanvasPoint(x: 32 + 2000, y: 24),
            ),
          ),
        ),
      ]);
      expect(
        s.layerMerging.bakeOf(const LayerId('a'), null)!.changes,
        {FxBakeChange.wall},
      );
    });

    test('a cel the row does not show stays in its bank as it is', () {
      final idle = Frame(
        id: const FrameId('a-9'),
        duration: 1,
        name: '9',
        strokes: [],
      );
      final s = plain([
        rowA().copyWith(frames: [...rowA().frames, idle]),
      ]);
      final row = s.layerMerging.bakeOf(const LayerId('a'), bright)!.row;
      expect([for (final cel in row.frames) cel.name], [
        '1',
        '1-2',
        '1-3',
        '9',
      ]);
      expect(row.frames.last, idle);
    });

    test('🗣️I-132-Q23 — a row the fx reads stands by its pictures hidden, '
        'as it is; the row itself, read, is drawn as itself; no other row '
        'is drawn into them', () {
      LayerEffect lens(String map) => LayerEffect.defaults(
        id: const EffectId('e-lens'),
        kind: EffectKind.cameraLensBlur,
      ).withLayer('blurMapLayer', LayerId(map));
      Layer still(String id) => Layer(
        id: LayerId(id),
        name: id.toUpperCase(),
        frames: [Frame(id: FrameId('$id-1'), duration: 3, strokes: [])],
        timeline: {0: TimelineExposure.drawing(FrameId('$id-1'), length: 3)},
      );
      ({List<(LayerId, bool)> rows, List<LayerEffect> worn}) drawnFrom(
        String map,
      ) {
        final s = plain([
          still('m'),
          still('o'),
          rowA(effects: [lens(map), brightness()]),
        ]);
        final from = s.layerMerging
            .bakeOf(const LayerId('a'), const EffectId('e-lens'))!
            .pictures
            .first
            .from;
        return (
          rows: [for (final row in from.layers) (row.id, row.isVisible)],
          worn: from.layers.byId(const LayerId('a'))!.effects,
        );
      }

      final other = drawnFrom('m');
      expect(other.rows, [
        (const LayerId('m'), false),
        (const LayerId('a'), true),
      ]);
      expect(other.worn, [lens('m')]);
      final itself = drawnFrom('a');
      expect(itself.rows, [(const LayerId('a'), true)]);
      expect(itself.worn, [lens('a')]);
    });
  });

  group('②b — a row\'s riders wear its fx and its transform, and are baked '
      'with it (07-21 「어태치 레이어는 주인과 같이 굽는다」)', () {
    const blue = [0, 0, 200, 255];
    const r = LayerId('r');

    /// `a` wearing [effects] and [transformTrack], ridden by [rider] —
    /// whose cel is blue in the canvas's first tile of the second row —
    /// the two in [folder] where one is given.
    EditorSessionManager ridden(
      Layer rider, {
      List<LayerEffect>? effects,
      TransformTrack? transformTrack,
      Layer? folder,
    }) {
      final rows = [
        rowA(effects: effects, transformTrack: transformTrack),
        rider,
      ];
      final s = sessionOf([
        for (final row in rows) row.copyWith(folderId: folder?.id),
        ?folder,
      ]);
      addTearDown(s.dispose);
      bakeCelSurface(
        s.renderCaches.brushFrameStore,
        s.brushFrameKeyForCut(s.requireActiveCut, r, const FrameId('r-1')),
        inkAt([TileCoord(x: 0, y: 1)], blue),
      );
      return s;
    }

    Layer rOf(EditorSessionManager s) => s.requireActiveCut.layers.byId(r)!;

    /// What [s]'s cut shows at canvas (5, 20) — `r`'s ink — on frames 0..2.
    Future<List<List<int>>> seenOfR(
      WidgetTester tester,
      EditorSessionManager s,
    ) async => [
      for (var frame = 0; frame < 3; frame += 1)
        await shownAt(tester, s, frame, 5, 20),
    ];

    /// The cel `r` shows at each of frames 0..2.
    List<FrameId?> celsOfR(EditorSessionManager s) => [
      for (var frame = 0; frame < 3; frame += 1)
        exposedCelIdAt(cut: s.requireActiveCut, layerId: r, frameIndex: frame),
    ];

    testWidgets('🎯a synced rider takes a cel for each of its row\'s new ones '
        '— named as its cel was, under its mirror\'s id — each the picture '
        'it showed there, and one undo gives both rows back', (tester) async {
      final s = ridden(riderOf('a'));
      final before = s.requireActiveCut.layers;
      final seen = await seenOfR(tester, s);
      expect(coloursOf(seen), hasLength(3), reason: '⛔전제: it wears a\'s fx');

      await rasterize(tester, s);

      final row = a(s);
      final rider = rOf(s);
      expect([for (final cel in rider.frames) cel.name], ['1', '1-2', '1-3']);
      expect(rider.baseFrameLinks, {
        for (final cel in row.frames) cel.id: attachedMirrorCelId(r, cel.id),
      });
      expect(await seenOfR(tester, s), seen);
      expect([
        for (final cel in celsOfR(s)) celAt(s, cel!, 5, 20, of: r),
      ], seen, reason: 'each picture baked in its cel');
      expect([
        for (final cel in celsOfR(s)) celAt(s, cel!, 36, 5, of: r)?[3] ?? 0,
      ], [0, 0, 0], reason: 'none of a\'s picture in them');

      s.undo();
      expect(s.requireActiveCut.layers, before);
      s.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets('a free rider parts where its own picture does, into blocks '
        'of its own, its strength staying on its row', (tester) async {
      final s = ridden(riderOf('a', free: true).copyWith(opacity: 0.5));
      final seen = await seenOfR(tester, s);

      await rasterize(tester, s);

      final rider = rOf(s);
      expect([for (final cel in rider.frames) cel.name], ['1', '1-2', '1-3']);
      expect(
        rider.timeline.map((start, block) => MapEntry(start, block.length)),
        {0: 1, 1: 1, 2: 1},
      );
      expect(rider.opacity, 0.5);
      expect(await seenOfR(tester, s), seen);
      s.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets('🎯the row\'s transform rasterized moves its rider\'s '
        'pictures where they showed', (tester) async {
      final s = ridden(
        riderOf('a'),
        effects: [brightness(keyed: false, enabled: false)],
        transformTrack: TransformTrack.empty().copyWith(
          position: PropertyTrack<CanvasPoint>.empty().withKey(
            0,
            CanvasPoint(x: 48, y: 24),
          ),
        ),
      );
      Future<List<List<int>>> seenNow() async => [
        await shownAt(tester, s, 0, 21, 20),
        await shownAt(tester, s, 0, 5, 20),
      ];
      final seen = await seenNow();
      expect(seen.first, blue, reason: '⛔전제: it rides a 16 to the right');

      await rasterize(tester, s, null);

      expect(a(s).transformTrack.isEmpty, isTrue);
      expect(await seenNow(), seen);
      s.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets('a row and its rider in a folder are each drawn as they '
        'showed there, the folder staying over them', (tester) async {
      final s = ridden(
        riderOf('a'),
        folder: createFolderLayer(id: const LayerId('f'), name: 'F'),
      );
      Future<List<List<int>>> seenNow() async => [
        for (var frame = 0; frame < 3; frame += 1)
          for (final (x, y) in [(5, 20), (36, 5)])
            await shownAt(tester, s, frame, x, y),
      ];
      final seen = await seenNow();
      expect(
        coloursOf(seen),
        hasLength(5),
        reason: '⛔전제: both wear a\'s fx — white alike at its full',
      );

      await rasterize(tester, s);

      expect(rOf(s).folderId, const LayerId('f'));
      expect(await seenNow(), seen);
      s.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets('a free rider parts where its own cels do too: each cel its '
        'own picture', (tester) async {
      final s = ridden(
        riderOf('a', free: true).copyWith(
          frames: [
            ...riderOf('a').frames,
            Frame(
              id: const FrameId('r-2'),
              duration: 1,
              name: '2',
              strokes: [],
            ),
          ],
          timeline: {
            0: const TimelineExposure.drawing(FrameId('r-1'), length: 2),
            2: const TimelineExposure.drawing(FrameId('r-2'), length: 1),
          },
        ),
        effects: [brightness(keyed: false)],
      );
      bakeCelSurface(
        s.renderCaches.brushFrameStore,
        s.brushFrameKeyForCut(s.requireActiveCut, r, const FrameId('r-2')),
        inkAt([TileCoord(x: 1, y: 1)], blue),
      );
      Future<List<List<int>>> seenNow() async => [
        for (var frame = 0; frame < 3; frame += 1)
          for (final x in [5, 21]) await shownAt(tester, s, frame, x, 20),
      ];
      final seen = await seenNow();

      await rasterize(tester, s);

      final rider = rOf(s);
      expect([for (final cel in rider.frames) cel.name], ['1', '2']);
      expect(
        rider.timeline.map((start, block) => MapEntry(start, block.length)),
        {0: 2, 2: 1},
      );
      expect(await seenNow(), seen);
      s.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets('🎯over a band (Q3), a synced rider keeps its cel where its '
        'row keeps its own, and takes the band\'s picture under its '
        'mirror\'s id', (tester) async {
      final s = ridden(riderOf('a'));
      final seen = await seenOfR(tester, s);

      await rasterize(tester, s, bright, (start: 1, end: 2));

      final made = a(s).frames.last.id;
      final rider = rOf(s);
      expect([for (final cel in rider.frames) cel.name], ['1', '1-2']);
      expect(rider.frames.first.id, const FrameId('r-1'));
      expect(rider.baseFrameLinks, {
        const FrameId('a-1'): const FrameId('r-1'),
        made: attachedMirrorCelId(r, made),
      });
      expect(celsOfR(s), [
        const FrameId('r-1'),
        attachedMirrorCelId(r, made),
        const FrameId('r-1'),
      ]);
      expect(await seenOfR(tester, s), seen);
      expect(
        celAt(s, attachedMirrorCelId(r, made), 5, 20, of: r),
        seen[1],
        reason: 'the band\'s picture baked in its cel',
      );
      s.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets('over a band, a free rider parts there alone', (tester) async {
      final s = ridden(riderOf('a', free: true));
      final seen = await seenOfR(tester, s);

      await rasterize(tester, s, bright, (start: 1, end: 2));

      final rider = rOf(s);
      expect([for (final cel in rider.frames) cel.name], ['1', '1-2']);
      expect(rider.frames.first.id, const FrameId('r-1'));
      expect(
        rider.timeline.map((start, block) => MapEntry(start, block.length)),
        {0: 1, 1: 1, 2: 1},
      );
      expect(await seenOfR(tester, s), seen);
      s.playbackRig.prerenderScheduler.cancel();
    });

    test('a folder riding the row lays no picture, so it is no rider', () {
      final s = sessionOf([
        rowA(),
        Layer(
          id: const LayerId('f'),
          name: 'F',
          kind: LayerKind.folder,
          attachedToLayerId: const LayerId('a'),
          frames: const [],
          timeline: const {},
        ),
      ]);
      addTearDown(s.dispose);
      final plan = s.layerMerging.bakeOf(const LayerId('a'), bright)!;
      expect(plan.riders, isEmpty);
    });

    test('a free rider\'s sounds go with its cel\'s first picture', () {
      final s = ridden(
        riderOf('a', free: true).copyWith(
          audioClips: [
            AudioClip(filePath: 'ping.wav', frameId: const FrameId('r-1')),
          ],
        ),
      );
      final rider = s.layerMerging
          .bakeOf(const LayerId('a'), bright)!
          .riders
          .single;
      expect(rider.audioClips.single.frameId, rider.frames.first.id);
    });

    test('a synced rider of an image row that comes to hold more than one '
        'picture becomes a drawing row with it', () {
      final s = ridden(riderOf('a').copyWith(kind: LayerKind.image));
      final plan = s.layerMerging.bakeOf(const LayerId('a'), bright);
      expect(plan!.riders.single.kind, LayerKind.animation);
    });

    test('a synced rider keeps the links of its row\'s cels the row does not '
        'show — to the first picture of a cel that was baked', () {
      Frame idle(String id) =>
          Frame(id: FrameId(id), duration: 1, name: '9', strokes: []);
      final s = sessionOf([
        rowA().copyWith(
          frames: [...rowA().frames, idle('a-8'), idle('a-9')],
        ),
        riderOf('a').copyWith(
          frames: [...riderOf('a').frames, idle('r-8')],
          baseFrameLinks: {
            const FrameId('a-1'): const FrameId('r-1'),
            const FrameId('a-8'): const FrameId('r-8'),
            const FrameId('a-9'): const FrameId('r-1'),
          },
        ),
      ]);
      addTearDown(s.dispose);
      final rider = s.layerMerging
          .bakeOf(const LayerId('a'), bright)!
          .riders
          .single;
      expect(
        {
          for (final base in ['a-1', 'a-8', 'a-9'])
            base: rider.baseFrameLinks[FrameId(base)],
        },
        {
          'a-1': null,
          'a-8': const FrameId('r-8'),
          'a-9': rider.frames.first.id,
        },
      );
    });

    test('the bake links each of the row\'s new cels to its synced rider\'s '
        'cel over it itself — left to the mirroring a session does on its '
        'own, a picture could land where no link reaches', () {
      final s = ridden(riderOf('a'));
      final plan = s.layerMerging.bakeOf(const LayerId('a'), bright)!;
      expect(plan.riders.single.baseFrameLinks, {
        for (final cel in plan.row.frames)
          cel.id: attachedMirrorCelId(r, cel.id),
      });
    });
  });

  group('③ — a band over the header bakes its frames alone, every frame '
      'outside showing what it showed (Q3 「범위 안만 굽고, 범위 밖은 보이던 '
      '그대로」)', () {
    const band = (start: 1, end: 2);

    /// What [s]'s cut shows at canvas ([x], 5) on frames 0..2.
    Future<List<List<int>>> seenOf(
      WidgetTester tester,
      EditorSessionManager s, [
      List<int> xs = const [36],
    ]) async => [
      for (var frame = 0; frame < 3; frame += 1)
        for (final x in xs) await shownAt(tester, s, frame, x, 5),
    ];

    Map<int, Object?> keysOf(PropertyTrack<Object?> track) =>
        track.keys.map((frame, key) => MapEntry(frame, key.value));

    testWidgets('🎯a keyed fx read by the frame: the band\'s frame takes a '
        'picture of its own, the cel stays where it still shows, the fx is '
        'at rest over the band alone, and one undo gives the row back', (
      tester,
    ) async {
      final s = sessionOf([rowA()]);
      addTearDown(s.dispose);
      final before = s.requireActiveCut.layers;
      final seen = await seenOf(tester, s);
      expect(coloursOf(seen), hasLength(3), reason: '⛔전제: every frame its own');

      await rasterize(tester, s, bright, band);

      final row = a(s);
      final made = row.frames.last.id;
      expect([for (final cel in row.frames) cel.name], ['1', '1-2']);
      expect(row.frames.first.id, const FrameId('a-1'));
      expect(shownCels(s), [const FrameId('a-1'), made, const FrameId('a-1')]);
      expect(keysOf(row.effects.single.parameterOf('brightness').track), {
        0: 0,
        1: 0,
        2: 100,
      });
      expect(await seenOf(tester, s), seen);
      expect(celAt(s, made, 36, 5), seen[1], reason: 'baked in its cel');
      expect(celAt(s, const FrameId('a-1'), 36, 5), green);

      s.undo();
      expect(s.requireActiveCut.layers, before);
      s.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets('🎯read by the block, the fx is at rest over the band, and '
        'the part of a block the band leaves after it goes on showing what '
        'its head showed', (tester) async {
      // Brightened from its head on, short of white so twice shows: falling
      // 30 → 0 over frames 0..2.
      final s = sessionOf([
        rowA(
          effects: [
            brightness(basis: FxBasis.block).copyWith(
              parameters: {
                'brightness': EffectParameter(
                  track: PropertyTrack<double>(
                    keys: {
                      0: const PropertyKey<double>(30),
                      2: const PropertyKey<double>(0),
                    },
                  ),
                ),
              },
            ),
          ],
        ),
      ]);
      addTearDown(s.dispose);
      final seen = await seenOf(tester, s);
      expect(coloursOf(seen), hasLength(1), reason: '⛔전제: the head\'s, all');
      expect(seen.first, isNot(green), reason: '⛔전제: brightened');

      await rasterize(tester, s, bright, band);

      expect(a(s).timeline.keys, [0, 1, 2], reason: '⛔전제: its block parted');
      expect(await seenOf(tester, s), seen);
      s.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets('🎯a bundle it leaves, read by the block, shows what its '
        'head showed in the band and after it', (tester) async {
      final s = sessionOf([
        rowA(
          transformTrack: TransformTrack.empty().copyWith(
            position: PropertyTrack<CanvasPoint>.empty()
                .withKey(0, CanvasPoint(x: 32, y: 24))
                .withKey(2, CanvasPoint(x: 48, y: 24)),
          ),
        ).copyWith(transformBasis: FxBasis.block),
      ]);
      addTearDown(s.dispose);
      final seen = await seenOf(tester, s, [36, 52]);

      await rasterize(tester, s, bright, band);

      expect(a(s).timeline.keys, [0, 1, 2], reason: '⛔전제: its block parted');
      expect(await seenOf(tester, s, [36, 52]), seen);
      s.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets('a band over a repeat bakes its frame alone, a transform read '
        'by the block stepping on each repeat as it did', (tester) async {
      final s = sessionOf([
        rowA(
          timeline: repeatedHold,
          transformTrack: TransformTrack.empty().copyWith(
            position: PropertyTrack<CanvasPoint>.empty()
                .withKey(0, CanvasPoint(x: 32, y: 24))
                .withKey(2, CanvasPoint(x: 48, y: 24)),
          ),
        ).copyWith(transformBasis: FxBasis.block),
      ]);
      addTearDown(s.dispose);
      expect(
        a(s).timeline.values.where((block) => block.ghost),
        isNotEmpty,
        reason: '⛔전제: the repeat shows the cel again',
      );
      final seen = await seenOf(tester, s, [36, 52]);

      await rasterize(tester, s, bright, band);

      expect(a(s).frames.first.id, const FrameId('a-1'));
      expect(await seenOf(tester, s, [36, 52]), seen);
      s.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets('🎯the transform rasterized over a band moves the band\'s '
        'picture where it showed, and keeps moving the row outside it', (
      tester,
    ) async {
      final s = sessionOf([
        rowA(
          effects: [brightness(keyed: false, enabled: false)],
          transformTrack: TransformTrack.empty().copyWith(
            position: PropertyTrack<CanvasPoint>.empty()
                .withKey(0, CanvasPoint(x: 32, y: 24))
                .withKey(2, CanvasPoint(x: 48, y: 24)),
          ),
        ),
      ]);
      addTearDown(s.dispose);
      final seen = await seenOf(tester, s, [36, 44, 52]);
      expect(
        seen.sublist(0, 3),
        isNot(seen.sublist(6, 9)),
        reason: '⛔전제: it moves',
      );

      await rasterize(tester, s, null, band);

      expect(keysOf(a(s).transformTrack.position), {
        0: CanvasPoint(x: 32, y: 24),
        1: CanvasPoint(x: 32, y: 24),
        2: CanvasPoint(x: 48, y: 24),
      });
      expect(await seenOf(tester, s, [36, 44, 52]), seen);
      s.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets('🚨Q14 — over a band, an fx that draws at its defaults bakes '
        'nothing and says why: its switch has no key to be off by there '
        'alone', (tester) async {
      const number = EffectId('e-number');
      final s = sessionOf([
        rowA(effects: [LayerEffect(id: number, kind: EffectKind.celNumber)]),
      ]);
      addTearDown(s.dispose);
      final before = a(s);
      final context = await hostedContext(tester);

      unawaited(
        rasterizeFxGroup(
          context,
          s,
          const LayerId('a'),
          number,
          'fx',
          band: band,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey<String>('fx-rasterize-cannot-keep-the-rest'),
        ),
        findsOneWidget,
      );
      expect(
        find.text(AppText.strings.tlFxBakeCannotKeepTheRest),
        findsOneWidget,
      );
      expect(a(s), before);
      expect(
        [
          for (final over in <BakedFrames?>[
            band,
            (start: 0, end: 2),
            (start: 1, end: 9),
            (start: -1, end: 9),
            null,
          ])
            outcomeOf(s, const LayerId('a'), number, over),
        ],
        ['rest', 'rest', 'rest', 'bakes', 'bakes'],
        reason: 'over every frame it bakes',
      );
    });

    test('a band is cut to the frames the cut draws; one over every one of '
        'them bakes the row whole, as no band does; one holding none of '
        'them bakes nothing', () {
      final s = plain([rowA()]);
      FxBakePlan? over(BakedFrames band) =>
          s.layerMerging.bakeOf(const LayerId('a'), bright, band: band);
      List<FrameId> cels(FxBakePlan plan) => [
        for (final cel in plan.row.frames) cel.id,
      ];

      final past = over((start: 1, end: 9))!;
      expect([for (final cel in past.row.frames) cel.name], [
        '1',
        '1-2',
        '1-3',
      ]);
      expect(cels(past).first, const FrameId('a-1'));
      expect(
        cels(over((start: 0, end: 2))!).first,
        const FrameId('a-1'),
        reason: 'shown after it',
      );
      final every = over((start: -4, end: 9))!;
      expect(cels(every), isNot(contains(const FrameId('a-1'))));
      expect(
        every.row.effects.single,
        LayerEffect(id: bright, kind: EffectKind.brightnessContrast),
      );
      expect(over((start: 3, end: 9)), isNull);
    });

    test('a cel kept where it still shows keeps its sounds', () {
      final s = plain([
        rowA(
          audioClips: [
            AudioClip(filePath: 'ping.wav', frameId: const FrameId('a-1')),
          ],
        ),
      ]);
      final row = s.layerMerging
          .bakeOf(const LayerId('a'), bright, band: band)!
          .row;
      expect(row.audioClips.single.frameId, const FrameId('a-1'));
    });

    test('an fx it leaves, read by the block on a row it parts, keeps its '
        'switch and the row it reads', () {
      final number = LayerEffect(
        id: const EffectId('e-number'),
        kind: EffectKind.celNumber,
        basis: FxBasis.block,
      );
      final lens = LayerEffect.defaults(
        id: const EffectId('e-lens'),
        kind: EffectKind.cameraLensBlur,
      ).withLayer('blurMapLayer', const LayerId('a')).copyWith(
        basis: FxBasis.block,
      );
      final s = plain([rowA(effects: [number, lens, brightness()])]);
      final row = s.layerMerging.bakeOf(const LayerId('a'), bright)!.row;
      expect(row.timeline.keys, [0, 1, 2], reason: '⛔전제: its block parted');
      expect(row.effects.take(2), [number, lens]);
    });
  });

  group('④ — a 겸용 row is baked in every cut it is used in, each by its own '
      'values and timing, into the one bank its cels are (Q6 「같은 셀을 보는 '
      '다른 컷도 같이 굽는다 — 한 장에 못 담으면 막고 경고」)', () {
    /// `a`'s use in the cut [s] stands in — the cut linked to `a`'s.
    Layer twinOf(EditorSessionManager s) =>
        s.requireActiveCut.layers.firstWhere((layer) => layer.name == 'A');

    /// [layers] in one cut ([sessionOf]) and a cut linked to it, stood in —
    /// `a`'s use there showing `a`'s timing, values and keys, made [twin] of
    /// that where given. A 겸용컷 is made with its lanes empty (F-555).
    EditorSessionManager linkedOf(
      List<Layer> layers, {
      Layer Function(Layer use)? twin,
    }) {
      final s = plain(layers);
      s.cutVerbs.createLinkedCutFromActiveCut();
      final a = layers.firstWhere((layer) => layer.id == const LayerId('a'));
      final use = twinOf(s).copyWith(
        timeline: a.timeline,
        effects: a.effects,
        transformTrack: a.transformTrack,
      );
      s.repository.replaceLayer(layer: twin == null ? use : twin(use));
      return s;
    }

    /// The cuts of [s]'s track: `a`'s and the one linked to it.
    List<Cut> cutsOf(EditorSessionManager s) =>
        s.repository.requireProject().tracks.single.cuts;

    /// Each cut's rows.
    List<List<Layer>> rowsOf(EditorSessionManager s) => [
      for (final cut in cutsOf(s)) cut.layers,
    ];

    /// `a` in its own cut, wherever [s] stands.
    Layer aIn(EditorSessionManager s) => cutsOf(
      s,
    ).firstWhere((cut) => cut.id == cutId).layers.byId(const LayerId('a'))!;

    /// What each cut shows at canvas (36, 5) on frames 0..2.
    Future<List<List<int>>> seenIn(
      WidgetTester tester,
      EditorSessionManager s,
    ) async => [
      for (final cut in cutsOf(s))
        for (var frame = 0; frame < 3; frame += 1)
          await shownAt(tester, s, frame, 36, 5, of: cut),
    ];

    /// The cel [row] shows at each of frames 0..2.
    List<FrameId?> celsOf(Layer row) => [
      for (var frame = 0; frame < 3; frame += 1)
        exposedFrameIdAt(row.timeline, frame),
    ];

    /// Presses [rowId]'s group header RASTERIZE for [effectId] — scoped to
    /// [band] where one is given — and waits out its window.
    Future<void> press(
      WidgetTester tester,
      EditorSessionManager s,
      LayerId rowId, [
      EffectId? effectId = bright,
      BakedFrames? band,
    ]) async {
      final before = s.repository.requireProject();
      final context = await hostedContext(tester);
      unawaited(
        rasterizeFxGroup(context, s, rowId, effectId, 'fx', band: band),
      );
      await settleBehindTheWaitWindow(
        tester,
        () =>
            !identical(s.repository.requireProject(), before) &&
            find
                .byKey(const ValueKey<String>('fx-rasterize-progress'))
                .evaluate()
                .isEmpty,
      );
    }

    testWidgets('🎯a still fx pressed in the linked cut: every use bakes it — '
        'its cel baked once into the one bank, the fx at rest in both cuts, '
        'each showing what it showed — and one undo gives both back', (
      tester,
    ) async {
      final s = linkedOf([
        rowA(effects: [brightness(keyed: false)]),
      ]);
      final before = rowsOf(s);
      final seen = await seenIn(tester, s);
      expect(seen.first, isNot(green), reason: '⛔전제: it wears the fx');

      await press(tester, s, twinOf(s).id);

      final (original, twin) = (aIn(s), twinOf(s));
      expect([for (final cel in original.frames) cel.name], ['1']);
      expect(original.frames.single.id, isNot(const FrameId('a-1')));
      expect(twin.frames, original.frames, reason: 'one bank');
      for (final row in [original, twin]) {
        expect(
          row.effects.single,
          LayerEffect(id: bright, kind: EffectKind.brightnessContrast),
        );
        expect(celsOf(row).toSet(), {original.frames.single.id});
      }
      expect(await seenIn(tester, s), seen);

      s.undo();
      expect(rowsOf(s), before);
      s.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets('🎯a keyed fx the uses read alike, pressed in its own cut: '
        'the cel each shows as three pictures parts into three cels both '
        'show alike — the linked cut, longer, over every frame it draws', (
      tester,
    ) async {
      final s = linkedOf(
        [rowA()],
        twin: (use) => use.copyWith(
          timeline: {
            0: const TimelineExposure.drawing(FrameId('a-1'), length: 5),
          },
        ),
      );
      final seen = await seenIn(tester, s);
      expect(coloursOf(seen), hasLength(3), reason: '⛔전제: three pictures');

      await press(tester, s, const LayerId('a'));

      final (original, twin) = (aIn(s), twinOf(s));
      expect([for (final cel in original.frames) cel.name], [
        '1',
        '1-2',
        '1-3',
      ]);
      expect(twin.frames, original.frames, reason: 'one bank');
      expect(celsOf(original).toSet(), hasLength(3));
      expect(celsOf(twin), celsOf(original));
      expect(
        [for (final frame in [3, 4]) exposedFrameIdAt(twin.timeline, frame)],
        [celsOf(original).last, celsOf(original).last],
        reason: 'its last key held',
      );
      expect(await seenIn(tester, s), seen);
      s.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets('🚨the uses reading the fx otherwise, a cel shown as other '
        'pictures in each cut: it bakes nothing, and says why', (tester) async {
      final s = linkedOf(
        [rowA()],
        twin: (use) => use.copyWith(effects: [brightness(keyed: false)]),
      );
      final before = rowsOf(s);
      final context = await hostedContext(tester);

      unawaited(
        rasterizeFxGroup(context, s, const LayerId('a'), bright, 'fx'),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('fx-rasterize-uses-apart')),
        findsOneWidget,
      );
      expect(find.text(AppText.strings.tlFxBakeUsesApart), findsOneWidget);
      expect(rowsOf(s), before);
    });

    test('🚨a use showing the cel over fewer frames shows it as fewer '
        'pictures, which one cel cannot hold — but for a band, which bakes '
        'the pressed cut alone', () {
      final s = linkedOf(
        [rowA()],
        twin: (use) => use.copyWith(
          timeline: {
            0: const TimelineExposure.drawing(FrameId('a-1'), length: 2),
          },
        ),
      );
      expect(
        [
          outcomeOf(s, const LayerId('a'), bright),
          outcomeOf(s, twinOf(s).id, bright),
        ],
        ['usesApart', 'usesApart'],
        reason: 'pressed in either cut',
      );
      expect(
        outcomeOf(s, const LayerId('a'), bright, (start: 0, end: 1)),
        'bakes',
      );
    });

    test('a band over every frame of the pressed cut keeps a cel the other '
        'use shows, its pictures all new', () {
      final s = linkedOf([rowA()]);
      final plan = s.layerMerging.bakeOf(
        const LayerId('a'),
        bright,
        band: (start: 0, end: 3),
      )!;
      expect([for (final cel in plan.row.frames) cel.name], [
        '1',
        '1-2',
        '1-3',
        '1-4',
      ]);
      expect(plan.row.frames.first.id, const FrameId('a-1'));
    });

    test('a cel a use does not show asks nothing of it: it is baked as the '
        'uses that show it show it', () {
      final s = linkedOf(
        [
          rowA(
            effects: [brightness(keyed: false)],
            timeline: {
              0: const TimelineExposure.drawing(FrameId('a-1'), length: 2),
              2: const TimelineExposure.drawing(FrameId('a-2'), length: 1),
            },
          ).copyWith(
            frames: [
              Frame(
                id: const FrameId('a-1'),
                duration: 2,
                name: '1',
                strokes: const [],
              ),
              Frame(
                id: const FrameId('a-2'),
                duration: 1,
                name: '2',
                strokes: const [],
              ),
            ],
          ),
        ],
        twin: (use) => use.copyWith(
          timeline: {
            0: const TimelineExposure.drawing(FrameId('a-1'), length: 3),
          },
        ),
      );
      final plan = s.layerMerging.bakeOf(const LayerId('a'), bright)!;
      expect([for (final cel in plan.row.frames) cel.name], ['1', '2']);
      final twin = plan.others.single.layers.firstWhere(
        (layer) => layer.name == 'A',
      );
      expect(twin.frames, plan.row.frames, reason: 'one bank');
      expect(celsOf(twin).toSet(), {celsOf(plan.row).first});

      final fromTheTwin = s.layerMerging.bakeOf(twinOf(s).id, bright)!;
      final two = fromTheTwin.row.frames.firstWhere((cel) => cel.name == '2');
      final drawn = fromTheTwin.pictures.singleWhere(
        (picture) => picture.frameId == two.id,
      );
      expect(
        (drawn.from.id, drawn.into.id, drawn.rowId),
        (cutId, cutId, const LayerId('a')),
        reason: 'drawn of the use that shows it',
      );
    });

    testWidgets('🎯a band bakes the pressed cut alone: the other use keeps '
        'its cels, its timing and its keys, its bank one with the band\'s '
        'new cel', (tester) async {
      final s = linkedOf([rowA()]);
      final before = rowsOf(s);
      final kept = twinOf(s);
      final seen = await seenIn(tester, s);

      await press(tester, s, const LayerId('a'), bright, (start: 1, end: 2));

      final (original, twin) = (aIn(s), twinOf(s));
      expect([for (final cel in original.frames) cel.name], ['1', '1-2']);
      expect(original.frames.first.id, const FrameId('a-1'));
      expect(twin.frames, original.frames, reason: 'one bank');
      expect(twin.timeline, kept.timeline);
      expect(twin.effects, kept.effects);
      expect(await seenIn(tester, s), seen);

      s.undo();
      expect(rowsOf(s), before);
      s.playbackRig.prerenderScheduler.cancel();
    });

    test('🚨Q14 — a band over every frame of the pressed cut leaves every '
        'frame of the other use: an fx that draws at its defaults waits', () {
      const number = EffectId('e-number');
      final effects = [LayerEffect(id: number, kind: EffectKind.celNumber)];
      String overEvery(EditorSessionManager s) =>
          outcomeOf(s, const LayerId('a'), number, (start: 0, end: 3));
      expect(
        [
          overEvery(linkedOf([rowA(effects: effects)])),
          overEvery(plain([rowA(effects: effects)])),
        ],
        ['rest', 'bakes'],
      );
    });

    test('the transform, each use\'s own: alike it bakes, apart it waits', () {
      TransformTrack movedTo(double x) => TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>.empty().withKey(
          0,
          CanvasPoint(x: x, y: 24),
        ),
      );
      final moved = rowA(transformTrack: movedTo(40));
      expect(
        [
          outcomeOf(linkedOf([moved]), const LayerId('a'), null),
          outcomeOf(
            linkedOf(
              [moved],
              twin: (use) => use.copyWith(transformTrack: movedTo(44)),
            ),
            const LayerId('a'),
            null,
          ),
        ],
        ['bakes', 'usesApart'],
      );
    });
  });

  group('🚨what it bakes nothing of yet — its button lit off, the slot kept '
      '(Q8, and the card\'s rounds ahead)', () {
    bool bakes(EditorSessionManager s, String row, [EffectId? fx = bright]) =>
        s.layerMerging.bakesFx(LayerId(row), fx);

    Layer withBright(Layer layer) => layer.copyWith(effects: [brightness()]);

    test('a row with no picture of its own: a folder, an adjustment row', () {
      final s = sessionOf([
        rowA(),
        withBright(
          Layer(
            id: const LayerId('f'),
            name: 'F',
            kind: LayerKind.folder,
            frames: const [],
            timeline: const {},
          ),
        ),
        withBright(
          Layer(
            id: const LayerId('adj'),
            name: 'Adj',
            kind: LayerKind.adjustment,
            frames: const [],
            timeline: const {},
          ),
        ),
      ]);
      addTearDown(s.dispose);
      expect([bakes(s, 'a'), bakes(s, 'f'), bakes(s, 'adj')], [
        true,
        false,
        false,
      ]);
    });

    test('an fx the row does not wear', () {
      final s = sessionOf([rowA()]);
      addTearDown(s.dispose);
      expect(bakes(s, 'a', const EffectId('e-gone')), isFalse);
    });

    test('a row riding another, which wears its base\'s fx and none of its '
        'own (R9) — its base bakes (②b)', () {
      final s = sessionOf([rowA(), withBright(riderOf('a'))]);
      addTearDown(s.dispose);
      expect([bakes(s, 'a'), bakes(s, 'r')], [true, false]);
    });

    test('a reference row riding the row (⑤)', () {
      final s = sessionOf([
        rowA(),
        riderOf('a').copyWith(
          mediaReference: MediaReference(
            assetPath: 'ref.png',
            pose: TransformPose(center: CanvasPoint(x: 32, y: 24)),
            pictureSize: const CanvasSize(width: 16, height: 16),
          ),
        ),
      ]);
      addTearDown(s.dispose);
      expect(bakes(s, 'a'), isFalse);
    });

    test('a row riding the conte, which wears fx of its own (④c · I-99)', () {
      final project = conteTrackProject();
      final cut = project.tracks.single.cuts.first;
      final conte = cut.layers.firstWhere(
        (layer) => layer.kind == LayerKind.storyboard,
      );
      final s = EditorSessionManager(
        initialProject: project.copyWith(
          tracks: [
            project.tracks.single.copyWith(
              cuts: [
                cut.copyWith(
                  layers: [
                    ...cut.layers,
                    withBright(
                      riderOf(conte.id.value),
                    ).copyWith(kind: LayerKind.storyboard),
                  ],
                ),
                ...project.tracks.single.cuts.skip(1),
              ],
            ),
          ],
        ),
      );
      addTearDown(s.dispose);
      expect(s.layerMerging.bakesFx(const LayerId('r'), bright), isFalse);
    });

    test('a 겸용 row a row wearing its fx rides, in any of its cuts (④b)', () {
      final s = sessionOf([rowA()]);
      addTearDown(s.dispose);
      s.cutVerbs.createLinkedCutFromActiveCut();
      final cut = s.requireActiveCut;
      final twin = cut.layers.firstWhere((layer) => layer.name == 'A');
      expect(bakes(s, 'a'), isTrue, reason: '⛔전제: a 겸용 row bakes');

      s.repository.setCutLayers(
        cutId: cut.id,
        layers: [...cut.layers, riderOf(twin.id.value, free: true)],
      );

      expect([bakes(s, 'a'), bakes(s, twin.id.value)], [false, false]);
    });

    test('a reference row (⑤)', () {
      final s = sessionOf([
        rowA().copyWith(
          mediaReference: MediaReference(
            assetPath: 'ref.png',
            pose: TransformPose(center: CanvasPoint(x: 32, y: 24)),
            pictureSize: const CanvasSize(width: 16, height: 16),
          ),
        ),
      ]);
      addTearDown(s.dispose);
      expect(bakes(s, 'a'), isFalse);
    });

    test('the conte of a track (④c)', () {
      final s = EditorSessionManager(initialProject: conteTrackProject());
      addTearDown(s.dispose);
      final conte = s.activeTrack.cuts.first.layers.firstWhere(
        (layer) => layer.kind == LayerKind.storyboard,
      );
      expect(s.layerMerging.bakesFx(conte.id, null), isFalse);
    });
  });
}

extension on LayerMerging {
  /// The bake RASTERIZE in [rowId]'s header plans of [effectId] — null where
  /// it bakes nothing, or waits.
  FxBakePlan? bakeOf(LayerId rowId, EffectId? effectId, {BakedFrames? band}) =>
      switch (planOfFx(rowId, effectId, band: band)) {
        final FxBakePlan plan => plan,
        _ => null,
      };
}
