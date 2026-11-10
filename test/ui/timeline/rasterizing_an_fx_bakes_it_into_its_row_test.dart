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
import 'package:anicel/src/models/conte_key.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/exposure_memo.dart';
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
import 'package:anicel/src/models/layer_link_registry.dart';
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
    show BakedFrames, FxBakePlan;
import 'package:anicel/src/services/import/raster_cel_import.dart'
    show bakeCelSurface;
import 'package:anicel/src/ui/canvas/layer_blend_shader.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/rasterize_fx_group.dart';

import '../../helpers/cel_text_fixture.dart' show pixelOf;
import '../../helpers/wait_window.dart';

/// 🗣️I-120 (유저 2026-10-21 · 11-04): an fx group header's RASTERIZE bakes
/// the fx into the row's pictures as they show it (Q1 「스위치를 따른다 —
/// 늘 보이던 그대로」) — a picture wherever its value parts them — and puts
/// its values and keys back at their defaults, its line kept; an image row
/// that needs more than one picture becomes a drawing row; one undo gives
/// the row back. Q21 asks nothing first, baking every fx on up to its line;
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

  const darker = EffectId('e-darker');

  /// A still brightness fx of -40: run before [brightness] or after it,
  /// the row shows otherwise — a picture baked clips at white.
  LayerEffect darkening({bool enabled = true}) => LayerEffect(
    id: darker,
    kind: EffectKind.brightnessContrast,
    enabled: enabled,
    parameters: {'brightness': EffectParameter(value: -40)},
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

  /// A session over [layers] ([sessionOf]), [duration] frames long, let go
  /// after the test.
  EditorSessionManager plain(List<Layer> layers, {int duration = 3}) {
    final s = sessionOf(layers, duration: duration);
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

  /// What [s]'s cut — [of], where given — shows on [frame], drawn as an
  /// export draws it: the wall's pixels row by row, [width] to a row, the
  /// first at canvas ([left], [top]).
  Future<({List<int> rgba, int width, int left, int top})> wallAt(
    WidgetTester tester,
    EditorSessionManager s,
    int frame, {
    Cut? of,
  }) async {
    final cut = of ?? s.requireActiveCut;
    final wall = s.pasteboardOf(cut.canvasSize);
    final drawn = await tester.runAsync(() async {
      final renderer = ExportFrameRenderer(
        session: s,
        background: const ui.Color(0x00000000),
      );
      try {
        final image = await renderer.renderOver(cut, frame, wall.rect);
        try {
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawStraightRgba,
          ))!;
          return (
            rgba: bytes.buffer
                .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes)
                .toList(),
            width: image.width,
          );
        } finally {
          image.dispose();
        }
      } finally {
        renderer.dispose();
      }
    });
    return (
      rgba: drawn!.rgba,
      width: drawn.width,
      left: wall.left,
      top: wall.top,
    );
  }

  /// What [s]'s cut — [of], where given — shows at canvas ([x], [y]) on
  /// [frame] ([wallAt]).
  Future<List<int>> shownAt(
    WidgetTester tester,
    EditorSessionManager s,
    int frame,
    int x,
    int y, {
    Cut? of,
  }) async {
    final (:rgba, :width, :left, :top) = await wallAt(
      tester,
      s,
      frame,
      of: of,
    );
    final at = ((y - top) * width + (x - left)) * 4;
    return rgba.sublist(at, at + 4);
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

  testWidgets('🚨Q21 — a press asks nothing first: an fx on that runs before '
      'the one pressed is baked with it, and the row shows what it showed '
      '(유저 11-05 「순서는 안바뀌게. 최대한 자기선에서 래스터라이즈」)', (
    tester,
  ) async {
    final s = sessionOf([
      rowA(effects: [darkening(), brightness()]),
    ]);
    addTearDown(s.dispose);
    final seen = [
      for (var frame = 0; frame < 3; frame += 1)
        await shownAt(tester, s, frame, 36, 5),
    ];

    await rasterize(tester, s);

    expect(a(s).effects, [
      LayerEffect(id: darker, kind: EffectKind.brightnessContrast),
      LayerEffect(id: bright, kind: EffectKind.brightnessContrast),
    ]);
    expect([
      for (var frame = 0; frame < 3; frame += 1)
        await shownAt(tester, s, frame, 36, 5),
    ], seen);
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
        parted.layerMerging.planOfFx(const LayerId('a'), bright)!.row.kind,
        still.layerMerging.planOfFx(const LayerId('a'), bright)!.row.kind,
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
      final row = s.layerMerging.planOfFx(const LayerId('a'), bright)!.row;
      expect(row.audioClips.single.frameId, row.frames.first.id);
    });

    test('🚨Q21 — a press bakes its fx and each fx on that runs before it, '
        'none off nor after; the transform, each fx on', () {
      List<EffectId> baked(List<LayerEffect> effects, EffectId? pressed) {
        final row = plain([rowA(effects: effects)]).layerMerging
            .planOfFx(const LayerId('a'), pressed)!
            .row;
        return [
          for (final (index, fx) in row.effects.indexed)
            if (fx != effects[index]) fx.id,
        ];
      }

      expect([
        baked([darkening(), brightness()], bright),
        baked([darkening(enabled: false), brightness()], bright),
        baked([brightness(), darkening()], bright),
        baked([darkening(), brightness()], null),
        baked([darkening(enabled: false), brightness()], null),
      ], [
        [darker, bright],
        [bright],
        [bright],
        [darker, bright],
        [bright],
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
        verbs.planOfFx(const LayerId('a'), number)!.row.effects.first.enabled,
        verbs.planOfFx(const LayerId('a'), bright)!.row.effects.last.enabled,
      ], [false, true]);
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
      final row = s.layerMerging.planOfFx(const LayerId('a'), bright)!.row;
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
            .planOfFx(const LayerId('a'), const EffectId('e-lens'))!
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
      final plan = s.layerMerging.planOfFx(const LayerId('a'), bright)!;
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
          .planOfFx(const LayerId('a'), bright)!
          .riders
          .single;
      expect(rider.audioClips.single.frameId, rider.frames.first.id);
    });

    test('a synced rider of an image row that comes to hold more than one '
        'picture becomes a drawing row with it', () {
      final s = ridden(riderOf('a').copyWith(kind: LayerKind.image));
      final plan = s.layerMerging.planOfFx(const LayerId('a'), bright);
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
          .planOfFx(const LayerId('a'), bright)!
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
      final plan = s.layerMerging.planOfFx(const LayerId('a'), bright)!;
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
    const number = EffectId('e-number');

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

    testWidgets('🚨Q14 — over a band, an fx that draws at its defaults is '
        'baked into the band\'s frames and switched off, unasked (Q21): the '
        'frames outside show the row without it (유저 11-05 「범위 안만 '
        '굽고 스위치를 끈다」)', (tester) async {
      LayerEffect numbered({bool enabled = true}) => LayerEffect(
        id: number,
        kind: EffectKind.celNumber,
        enabled: enabled,
      );
      final s = sessionOf([
        rowA(effects: [numbered()]),
      ]);
      addTearDown(s.dispose);
      final bare = sessionOf([
        rowA(effects: [numbered(enabled: false)]),
      ]);
      addTearDown(bare.dispose);
      Future<List<List<int>>> walls(EditorSessionManager of) async => [
        for (var frame = 0; frame < 3; frame += 1)
          (await wallAt(tester, of, frame)).rgba,
      ];
      final (seen, off) = (await walls(s), await walls(bare));
      expect(seen[1], isNot(off[1]), reason: '⛔전제: the number draws');
      final before = a(s);

      await rasterize(tester, s, number, band);

      expect(a(s).effects.single, numbered(enabled: false));
      expect(await walls(s), [off[0], seen[1], off[2]]);
      s.undo();
      expect(a(s), before);
      s.playbackRig.prerenderScheduler.cancel();
      bare.playbackRig.prerenderScheduler.cancel();
    });

    test('🚨Q15 — a named key the cut paces anew keeps its name, and the name '
        'holds what each key of it moved — the way leaving one, the way '
        'arriving at another — every frame outside as it showed (유저 11-05 '
        '「같은 이름 키 전부에 새 손잡이」)', () {
      const eased = EaseSide(influence: 0.6, speed: 0);
      const n = PropertyKey<double>(
        0,
        incoming: eased,
        outgoing: eased,
        name: 'N',
      );
      final fx = LayerEffect(
        id: bright,
        kind: EffectKind.brightnessContrast,
        parameters: {
          'brightness': EffectParameter(
            track: PropertyTrack<double>(
              keys: {0: n, 4: const PropertyKey<double>(100), 8: n},
            ),
          ),
        },
      );
      final s = plain([
        rowA(
          effects: [fx],
          timeline: {
            0: const TimelineExposure.drawing(FrameId('a-1'), length: 9),
          },
        ),
      ], duration: 9);
      double at(List<LayerEffect> effects, int frame) =>
          effectParameterValueAt(effects, bright, 'brightness', frame);

      final row = s.layerMerging
          .planOfFx(const LayerId('a'), bright, band: (start: 2, end: 6))!
          .row;

      final keys = row.effects.single.parameters['brightness']!.track.keys;
      expect([keys[0]!.name, keys[8]!.name], ['N', 'N']);
      expect(keys[8]!.held, keys[0]!.held, reason: 'one key');
      expect(
        [keys[0]!.outgoing, keys[0]!.incoming],
        everyElement(isNot(eased)),
        reason: 'the way leaving 0 and the way arriving at 8 paced anew',
      );
      for (final frame in [0, 1, 6, 7, 8]) {
        expect(
          at(row.effects, frame),
          closeTo(at([fx], frame), 1e-6),
          reason: 'frame $frame',
        );
      }
    });

    test('🚨Q15 — the transform\'s too: a named key its band\'s cut paces '
        'anew keeps its name, and the name holds what each key of it '
        'moved', () {
      const eased = EaseSide(influence: 0.6, speed: 0);
      const n = PropertyKey<double>(
        0,
        incoming: eased,
        outgoing: eased,
        name: 'N',
      );
      final turning = TransformTrack.empty().copyWith(
        rotation: PropertyTrack<double>(
          keys: {0: n, 4: const PropertyKey<double>(90), 8: n},
        ),
      );
      final s = plain([
        rowA(
          effects: const [],
          transformTrack: turning,
          timeline: {
            0: const TimelineExposure.drawing(FrameId('a-1'), length: 9),
          },
        ),
      ], duration: 9);
      double at(TransformTrack track, int frame) => track.rotation.resolveAt(
        frameIndex: frame,
        orElse: () => 0,
        space: doubleKeySpace,
      );

      final track = s.layerMerging
          .planOfFx(const LayerId('a'), null, band: (start: 2, end: 6))!
          .row
          .transformTrack;

      final keys = track.rotation.keys;
      expect([keys[0]!.name, keys[8]!.name], ['N', 'N']);
      expect(keys[8]!.held, keys[0]!.held, reason: 'one key');
      expect(
        [keys[0]!.outgoing, keys[0]!.incoming],
        everyElement(isNot(eased)),
        reason: 'the way leaving 0 and the way arriving at 8 paced anew',
      );
      for (final frame in [0, 1, 6, 7, 8]) {
        expect(
          at(track, frame),
          closeTo(at(turning, frame), 1e-6),
          reason: 'frame $frame',
        );
      }
    });

    test('a band is cut to the frames the cut draws; one over every one of '
        'them bakes the row whole, as no band does; one holding none of '
        'them bakes nothing', () {
      final s = plain([rowA()]);
      FxBakePlan? over(BakedFrames band) =>
          s.layerMerging.planOfFx(const LayerId('a'), bright, band: band);
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
          .planOfFx(const LayerId('a'), bright, band: band)!
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
      final s = plain([rowA(effects: [brightness(), number, lens])]);
      final row = s.layerMerging.planOfFx(const LayerId('a'), bright)!.row;
      expect(row.timeline.keys, [0, 1, 2], reason: '⛔전제: its block parted');
      expect(row.effects.skip(1), [number, lens]);
    });
  });

  /// The cuts of [s]'s track.
  List<Cut> cutsOf(EditorSessionManager s) =>
      s.repository.requireProject().tracks.single.cuts;

  /// Each cut's rows.
  List<List<Layer>> rowsOf(EditorSessionManager s) => [
    for (final cut in cutsOf(s)) cut.layers,
  ];

  /// [row] in [cut] of [s].
  Layer rowIn(EditorSessionManager s, CutId cut, String row) => cutsOf(
    s,
  ).firstWhere((at) => at.id == cut).layers.byId(LayerId(row))!;

  const red = [200, 0, 0, 255];

  /// Every cel of every cut of [s] inked: a row riding none green in the
  /// canvas's third tile, a row riding one red in the second.
  void inkEveryCel(EditorSessionManager s) {
    for (final at in cutsOf(s)) {
      for (final layer in at.layers) {
        final rides = layer.attachedToLayerId != null;
        for (final cel in layer.frames) {
          bakeCelSurface(
            s.renderCaches.brushFrameStore,
            s.brushFrameKeyForCut(at, layer.id, cel.id),
            inkAt([TileCoord(x: rides ? 1 : 2, y: 0)], rides ? red : green),
          );
        }
      }
    }
  }

  /// What each cut shows at canvas (36, 5) on frames 0..2 — and at each
  /// point of [also] after.
  Future<List<List<int>>> seenIn(
    WidgetTester tester,
    EditorSessionManager s, {
    List<(int, int)> also = const [],
  }) async => [
    for (final cut in cutsOf(s))
      for (final (x, y) in [(36, 5), ...also])
        for (var frame = 0; frame < 3; frame += 1)
          await shownAt(tester, s, frame, x, y, of: cut),
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

  group('④ — a 겸용 row is baked in every cut it is used in, each by its own '
      'values and timing, into the one bank its cels are (Q6 「같은 셀을 보는 '
      '다른 컷도 같이 굽는다」) — a cel shown as other pictures in each cut '
      'parted into a cel for each, its link kept (Q20)', () {
    /// `a`'s use in the cut [s] stands in — the cut linked to `a`'s.
    Layer twinOf(EditorSessionManager s) =>
        s.requireActiveCut.layers.firstWhere((layer) => layer.name == 'A');

    /// `r`'s use in the cut [s] stands in — the cut linked to `a`'s.
    Layer riderTwinOf(EditorSessionManager s) =>
        s.requireActiveCut.layers.firstWhere((layer) => layer.name == 'R');

    /// [layers] in one cut ([sessionOf]) and a cut linked to it, stood in —
    /// `a`'s use there showing `a`'s timing, values and keys, made [twin] of
    /// that where given, and `r`'s, where it rides, showing `r`'s timing,
    /// made [riderTwin] of that. A 겸용컷 is made with its lanes empty
    /// (F-555).
    EditorSessionManager linkedOf(
      List<Layer> layers, {
      Layer Function(Layer use)? twin,
      Layer Function(Layer use)? riderTwin,
      int duration = 3,
    }) {
      final s = plain(layers, duration: duration);
      s.cutVerbs.createLinkedCutFromActiveCut();
      final a = layers.firstWhere((layer) => layer.id == const LayerId('a'));
      final use = twinOf(s).copyWith(
        timeline: a.timeline,
        effects: a.effects,
        transformTrack: a.transformTrack,
      );
      s.repository.replaceLayer(layer: twin == null ? use : twin(use));
      for (final r in layers.where((layer) => layer.id == const LayerId('r'))) {
        final ridden = riderTwinOf(s).copyWith(timeline: r.timeline);
        s.repository.replaceLayer(
          layer: riderTwin == null ? ridden : riderTwin(ridden),
        );
      }
      return s;
    }

    /// `a` in its own cut, wherever [s] stands.
    Layer aIn(EditorSessionManager s) => cutsOf(
      s,
    ).firstWhere((cut) => cut.id == cutId).layers.byId(const LayerId('a'))!;

    /// The cel [row] shows at each of frames 0..2.
    List<FrameId?> celsOf(Layer row) => [
      for (var frame = 0; frame < 3; frame += 1)
        exposedFrameIdAt(row.timeline, frame),
    ];

    test('🗣️I-120 「참조fx의 래스터라이즈할때처럼 같은 법」 · I-120-Q22 — an image '
        'baked into a bank of more than one picture becomes an animation '
        'row, though each cut shows one (F-572-Q2 unanswered)', () {
      final s = linkedOf(
        [
          rowA(kind: LayerKind.image, effects: [brightness(keyed: false)]),
        ],
        twin: (use) => use.copyWith(
          effects: [
            LayerEffect(
              id: bright,
              kind: EffectKind.brightnessContrast,
              parameters: {'brightness': EffectParameter(value: 20)},
            ),
          ],
        ),
      );

      final plan = s.layerMerging.planOfFx(const LayerId('a'), bright)!;

      expect(
        plan.row.frames,
        hasLength(greaterThan(1)),
        reason: '⛔전제: the bank holds more than one picture',
      );
      expect(plan.row.kind, LayerKind.animation);
    });

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

    testWidgets('🎯the uses reading the fx otherwise, a cel shown as other '
        'pictures in each cut: it is parted in the one bank — the linked '
        "cut's picture a cel of its own, tailed after the pressed cut's — "
        'each cut showing its own, the link kept, nothing said; one undo '
        'gives both back', (tester) async {
      final s = linkedOf(
        [rowA()],
        twin: (use) => use.copyWith(effects: [brightness(keyed: false)]),
      );
      final before = rowsOf(s);
      final links = s.repository.requireProject().linkRegistry;
      final seen = await seenIn(tester, s);
      expect(coloursOf(seen), hasLength(4), reason: '⛔전제: four pictures');

      await press(tester, s, const LayerId('a'));

      final (original, twin) = (aIn(s), twinOf(s));
      expect([for (final cel in original.frames) cel.name], [
        '1',
        '1-2',
        '1-3',
        '1-4',
      ]);
      expect(twin.frames, original.frames, reason: 'one bank');
      expect(celsOf(original), [
        for (final cel in original.frames.take(3)) cel.id,
      ]);
      expect(celsOf(twin).toSet(), {original.frames.last.id});
      expect(s.repository.requireProject().linkRegistry, links);
      expect(await seenIn(tester, s), seen);
      expect(
        find.byKey(const ValueKey<String>('fx-rasterize-rows-freed')),
        findsNothing,
      );

      s.undo();
      expect(rowsOf(s), before);
      s.playbackRig.prerenderScheduler.cancel();
    });

    test('🚨a use showing the cel over fewer frames shows the pictures the '
        'other shows first — the same picture one cel and one name, pressed '
        'in either cut', () {
      final s = linkedOf(
        [rowA()],
        twin: (use) => use.copyWith(
          timeline: {
            0: const TimelineExposure.drawing(FrameId('a-1'), length: 2),
          },
        ),
      );
      final twinId = twinOf(s).id;
      for (final pressed in [const LayerId('a'), twinId]) {
        final plan = s.layerMerging.planOfFx(pressed, bright)!;
        final rows = [...plan.layers, ...plan.others.single.layers];
        String? nameAt(LayerId id, int frame) {
          final row = rows.firstWhere((row) => row.id == id);
          final cel = exposedFrameIdAt(row.timeline, frame);
          return row.frames.firstWhere((each) => each.id == cel).name;
        }

        expect(
          [
            for (final frame in [0, 1, 2]) nameAt(const LayerId('a'), frame),
            for (final frame in [0, 1]) nameAt(twinId, frame),
          ],
          ['1', '1-2', '1-3', '1', '1-2'],
          reason: 'pressed in $pressed',
        );
        expect(plan.pictures, hasLength(3));
      }
    });

    test('a band over every frame of the pressed cut keeps a cel the other '
        'use shows, its pictures all new', () {
      final s = linkedOf([rowA()]);
      final plan = s.layerMerging.planOfFx(
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
      final plan = s.layerMerging.planOfFx(const LayerId('a'), bright)!;
      expect([for (final cel in plan.row.frames) cel.name], ['1', '2']);
      final twin = plan.others.single.layers.firstWhere(
        (layer) => layer.name == 'A',
      );
      expect(twin.frames, plan.row.frames, reason: 'one bank');
      expect(celsOf(twin).toSet(), {celsOf(plan.row).first});

      final fromTheTwin = s.layerMerging.planOfFx(twinOf(s).id, bright)!;
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
        'frame of the other use: an fx that draws at its defaults goes off '
        'in both — one switch', () {
      const number = EffectId('e-number');
      final effects = [LayerEffect(id: number, kind: EffectKind.celNumber)];
      final linked = linkedOf([rowA(effects: effects)]).layerMerging.planOfFx(
        const LayerId('a'),
        number,
        band: (start: 0, end: 3),
      )!;
      expect(
        [
          linked.row,
          linked.others.single.layers.firstWhere((row) => row.name == 'A'),
        ].map((row) => row.effects.single.enabled),
        [false, false],
      );
    });

    test('🚨Q15 — what a band\'s cut moved of a named key reaches every key '
        'of the name: on its lane — the way after it bending anew — and on '
        'the lane of the other use, one naming space', () {
      const eased = EaseSide(influence: 0.6, speed: 0);
      const n = PropertyKey<double>(
        0,
        incoming: eased,
        outgoing: eased,
        name: 'N',
      );
      const hundred = PropertyKey<double>(100);
      LayerEffect brightnessOf(Map<int, PropertyKey<double>> keys) =>
          LayerEffect(
            id: bright,
            kind: EffectKind.brightnessContrast,
            parameters: {
              'brightness': EffectParameter(
                track: PropertyTrack<double>(keys: keys),
              ),
            },
          );
      final mine = brightnessOf({0: n, 4: hundred, 6: n, 8: hundred});
      final theirs = brightnessOf({
        0: const PropertyKey<double>(50),
        3: n,
        8: hundred,
      });
      final s = linkedOf(
        [
          rowA(
            effects: [mine],
            timeline: {
              0: const TimelineExposure.drawing(FrameId('a-1'), length: 9),
            },
          ),
        ],
        twin: (use) => use.copyWith(effects: [theirs]),
        duration: 9,
      );
      Map<int, PropertyKey<double>> keysOf(Layer row) =>
          row.effects.single.parameters['brightness']!.track.keys;
      double at(Layer row, int frame) =>
          effectParameterValueAt(row.effects, bright, 'brightness', frame);

      final plan = s.layerMerging.planOfFx(
        const LayerId('a'),
        bright,
        band: (start: 2, end: 3),
      )!;

      final row = keysOf(plan.row);
      final twin = keysOf(
        plan.others.single.layers.firstWhere((layer) => layer.name == 'A'),
      );
      expect(
        row[0]!.outgoing,
        isNot(eased),
        reason: '⛔전제: the cut paced the way leaving it anew',
      );
      expect([row[6]!.held, twin[3]!.held], [row[0]!.held, row[0]!.held]);
      expect([row[6]!.name, twin[3]!.name], ['N', 'N']);
      expect([
        twin[0],
        twin[8],
      ], const [PropertyKey<double>(50), hundred], reason: 'as they were');
      expect(
        at(plan.row, 7),
        isNot(closeTo(at(rowA(effects: [mine]), 7), 1e-6)),
        reason: 'the way leaving 6 is paced as the way leaving 0 is now',
      );
    });

    test("the transform, each use's own: alike, the uses share each "
        'picture; apart, each has its own in the one bank', () {
      TransformTrack movedTo(double x) => TransformTrack.empty().copyWith(
        position: PropertyTrack<CanvasPoint>.empty().withKey(
          0,
          CanvasPoint(x: x, y: 24),
        ),
      );
      final moved = rowA(transformTrack: movedTo(40));
      int celsBaked(EditorSessionManager s) =>
          s.layerMerging.planOfFx(const LayerId('a'), null)!.row.frames.length;
      expect([
        celsBaked(linkedOf([moved])),
        celsBaked(
          linkedOf(
            [moved],
            twin: (use) => use.copyWith(transformTrack: movedTo(44)),
          ),
        ),
      ], [3, 6]);
    });

    group('④b — the rows riding it, which wear its fx, are baked with it in '
        "every cut, a rider's uses sharing one bank as the row's do", () {
      /// `r` in `a`'s own cut, wherever [s] stands.
      Layer rIn(EditorSessionManager s) => cutsOf(
        s,
      ).firstWhere((cut) => cut.id == cutId).layers.byId(const LayerId('r'))!;

      testWidgets('🎯a still fx pressed in its own cut, the linked cut '
          'longer: a synced rider is baked with it in both cuts, a cel for '
          "each of the row's new ones in one bank — each cut showing what it "
          'showed — and one undo gives both back', (tester) async {
        final s = linkedOf(
          [
            rowA(effects: [brightness(keyed: false)]),
            riderOf('a'),
          ],
          twin: (use) => use.copyWith(
            timeline: {
              0: const TimelineExposure.drawing(FrameId('a-1'), length: 5),
            },
          ),
        );
        final before = rowsOf(s);
        final seen = await seenIn(tester, s);

        await press(tester, s, const LayerId('a'));

        final (original, twin) = (rIn(s), riderTwinOf(s));
        expect(original.frames.single.id, isNot(const FrameId('r-1')));
        expect(twin.frames, original.frames, reason: 'one bank');
        for (final (rider, base) in [(original, aIn(s)), (twin, twinOf(s))]) {
          expect(rider.baseFrameLinks, {
            base.frames.single.id: original.frames.single.id,
          });
        }
        expect(await seenIn(tester, s), seen);

        s.undo();
        expect(rowsOf(s), before);
        s.playbackRig.prerenderScheduler.cancel();
      });

      testWidgets('🎯a keyed fx: a free rider parts its cel in both cuts '
          'alike, one bank', (tester) async {
        final s = linkedOf([rowA(), riderOf('a', free: true)]);
        final seen = await seenIn(tester, s);
        expect(coloursOf(seen), hasLength(3), reason: '⛔전제: three pictures');

        await press(tester, s, const LayerId('a'));

        final (original, twin) = (rIn(s), riderTwinOf(s));
        expect([for (final cel in original.frames) cel.name], [
          '1',
          '1-2',
          '1-3',
        ]);
        expect(twin.frames, original.frames, reason: 'one bank');
        expect(celsOf(twin), celsOf(original));
        expect(celsOf(original).toSet(), hasLength(3));
        expect(await seenIn(tester, s), seen);
        s.playbackRig.prerenderScheduler.cancel();
      });

      testWidgets('🚨a cel of the row only the linked cut shows: the synced '
          "rider's cel over it is named by that cut's new cel — a cel for "
          "each of the row's, every one its own", (tester) async {
        const second = FrameId('a-2');
        final s = linkedOf(
          [
            rowA(effects: [brightness(keyed: false)]).copyWith(
              frames: [
                Frame(
                  id: const FrameId('a-1'),
                  duration: 3,
                  name: '1',
                  strokes: const [],
                ),
                Frame(id: second, duration: 1, name: '2', strokes: const []),
              ],
            ),
            riderOf('a').copyWith(
              frames: [
                Frame(
                  id: const FrameId('r-1'),
                  duration: 3,
                  name: '1',
                  strokes: const [],
                ),
                Frame(
                  id: const FrameId('r-2'),
                  duration: 1,
                  name: '2',
                  strokes: const [],
                ),
              ],
              baseFrameLinks: {
                const FrameId('a-1'): const FrameId('r-1'),
                second: const FrameId('r-2'),
              },
            ),
          ],
          twin: (use) => use.copyWith(
            timeline: {
              0: const TimelineExposure.drawing(second, length: 1),
              1: const TimelineExposure.drawing(FrameId('a-1'), length: 2),
            },
          ),
        );
        final seen = await seenIn(tester, s);

        await press(tester, s, const LayerId('a'));

        final (original, twin) = (rIn(s), riderTwinOf(s));
        expect({for (final cel in original.frames) cel.id}, hasLength(2));
        expect(twin.frames, original.frames, reason: 'one bank');
        final base = twinOf(s);
        expect(twin.baseFrameLinks, {
          for (final (index, cel) in base.frames.indexed)
            cel.id: original.frames[index].id,
        });
        expect(await seenIn(tester, s), seen);
        s.playbackRig.prerenderScheduler.cancel();
      });

      testWidgets('a band over the pressed cut bakes its riders there alone — '
          "the linked cut's showing what they showed", (tester) async {
        final s = linkedOf([rowA(), riderOf('a', free: true)]);
        final seen = await seenIn(tester, s);

        await press(
          tester,
          s,
          const LayerId('a'),
          bright,
          (start: 1, end: 3),
        );

        expect(celsOf(riderTwinOf(s)).toSet(), {const FrameId('r-1')});
        expect(celsOf(rIn(s)).first, const FrameId('r-1'));
        expect(celsOf(rIn(s)).toSet(), hasLength(3));
        expect(await seenIn(tester, s), seen);
        s.playbackRig.prerenderScheduler.cancel();
      });

      testWidgets("🚨a rider's cel shown as other pictures in each cut — the "
          "linked cut's row reading the fx otherwise — is parted in its one "
          "bank as the row's is, each cut's rider showing its own", (
        tester,
      ) async {
        final s = linkedOf(
          [rowA(), riderOf('a', free: true)],
          twin: (use) => use.copyWith(effects: [brightness(keyed: false)]),
        );
        final seen = await seenIn(tester, s);

        await press(tester, s, const LayerId('a'));

        final (original, twin) = (rIn(s), riderTwinOf(s));
        expect([for (final cel in original.frames) cel.name], [
          '1',
          '1-2',
          '1-3',
          '1-4',
        ]);
        expect(twin.frames, original.frames, reason: 'one bank');
        expect(celsOf(original), [
          for (final cel in original.frames.take(3)) cel.id,
        ]);
        expect(celsOf(twin).toSet(), {original.frames.last.id});
        expect(await seenIn(tester, s), seen);
        s.playbackRig.prerenderScheduler.cancel();
      });

      test('a row riding it in one of its cuts alone is baked there', () {
        final s = sessionOf([rowA()]);
        addTearDown(s.dispose);
        s.cutVerbs.createLinkedCutFromActiveCut();
        final cut = s.requireActiveCut;
        final twin = cut.layers.firstWhere((layer) => layer.name == 'A');
        s.repository.setCutLayers(
          cutId: cut.id,
          layers: [...cut.layers, riderOf(twin.id.value, free: true)],
        );

        final plan = s.layerMerging.planOfFx(twin.id, bright)!;
        expect(plan.riders.single.id, const LayerId('r'));
        expect(
          [for (final cel in plan.riders.single.frames) cel.name],
          ['1', '1-2', '1-3'],
        );
        expect(plan.others.single.layers.byId(const LayerId('r')), isNull);
        expect(s.layerMerging.bakesFx(const LayerId('a'), bright), isTrue);
      });

      test("🚨a synced rider showing another cel over the row's one cel in "
          'each cut: each picture is a cel of its own in the one bank — '
          'never two cels of one id '
          '(conte-pair-merge-mints-one-cel-id-for-two-pictures)', () {
        final s = linkedOf(
          [
            rowA(effects: [brightness(keyed: false)]),
            riderOf('a').copyWith(
              frames: [
                Frame(
                  id: const FrameId('r-1'),
                  duration: 3,
                  name: '1',
                  strokes: const [],
                ),
                Frame(
                  id: const FrameId('r-2'),
                  duration: 1,
                  name: '2',
                  strokes: const [],
                ),
              ],
            ),
          ],
          riderTwin: (ridden) => ridden.copyWith(
            baseFrameLinks: {const FrameId('a-1'): const FrameId('r-2')},
          ),
        );
        expect(
          [rIn(s).baseFrameLinks, riderTwinOf(s).baseFrameLinks],
          [
            {const FrameId('a-1'): const FrameId('r-1')},
            {const FrameId('a-1'): const FrameId('r-2')},
          ],
          reason: "⛔전제: over the row's one cel, each cut shows its own",
        );
        final twin = riderTwinOf(s).id;

        final plan = s.layerMerging.planOfFx(const LayerId('a'), bright)!;

        final bank = plan.riders.single.frames;
        final ids = [for (final cel in bank) cel.id];
        expect(ids.toSet(), hasLength(ids.length), reason: 'one id a cel');
        expect(
          plan.others.single.layers.byId(twin)!.frames,
          bank,
          reason: 'one bank',
        );
        final drawn = [
          for (final picture in plan.pictures)
            if (ids.contains(picture.frameId)) picture,
        ];
        expect(
          {for (final picture in drawn) picture.frameId},
          hasLength(drawn.length),
          reason: 'one picture a cel',
        );
        expect(
          {for (final picture in drawn) picture.from.id},
          {cutId, s.requireActiveCut.id},
          reason: 'what each cut showed is baked — neither lost',
        );
      });

      group('🗣️Q19 — a rider linked to a row riding one that is no use of the '
          "row, its cels that row's too, which the press does not reach", () {
        const second = CutId('cut2');
        Cut cutOf(CutId id, Layer row, String rider, {required bool free}) =>
            Cut(
              id: id,
              name: id.value,
              duration: 3,
              canvasSize: canvasSize,
              layers: [
                row,
                riderOf(row.id.value, free: free).copyWith(id: LayerId(rider)),
                createCameraLayer(cutId: id),
              ],
            );
        LayerLinkMember member(CutId cut, String row) => LayerLinkMember(
          trackId: const TrackId('track'),
          cutId: cut,
          layerId: LayerId(row),
        );

        /// `r` riding `a` in its cut, and `q` riding `b` in [second] — [free]
        /// or synced, `r` and `q` one where [linked] — every row's cel green
        /// in the canvas's third tile, every rider's red in the second.
        EditorSessionManager ridersOf({
          required bool linked,
          bool free = true,
        }) {
          final b = rowA().copyWith(id: const LayerId('b'));
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
                    cutOf(cutId, rowA(), 'r', free: free),
                    cutOf(second, b, 'q', free: free),
                  ],
                ),
              ],
              linkRegistry: LayerLinkRegistry(
                groups: [
                  if (linked)
                    LayerLinkGroup(
                      id: 'riders',
                      members: [member(cutId, 'r'), member(second, 'q')],
                    ),
                ],
              ),
              createdAt: DateTime.utc(2026),
            ),
          );
          addTearDown(s.dispose);
          expect(
            s.repository.requireProject().linkRegistry.groups,
            hasLength(linked ? 1 : 0),
            reason: '⛔전제: the riders are one where linked',
          );
          inkEveryCel(s);
          return s;
        }

        testWidgets('🎯it is baked, its link kept: its new cels join the one '
            'bank beside the cel the other row shows, which shows what it '
            'showed — nothing said — and one undo gives all back', (
          tester,
        ) async {
          final s = ridersOf(linked: true);
          final before = rowsOf(s);
          final links = s.repository.requireProject().linkRegistry;
          final seen = await seenIn(tester, s, also: const [(20, 5)]);
          final q = rowIn(s, second, 'q');

          await press(tester, s, const LayerId('a'));

          final (r, self) = (rowIn(s, cutId, 'r'), rowIn(s, second, 'q'));
          expect([for (final cel in r.frames) cel.name], [
            '1',
            '1-2',
            '1-3',
            '1-4',
          ]);
          expect(r.frames.first.id, const FrameId('r-1'));
          expect(self.frames, r.frames, reason: 'one bank');
          expect(self.timeline, q.timeline, reason: 'its cel kept');
          expect(celsOf(r), [for (final cel in r.frames.skip(1)) cel.id]);
          expect(s.repository.requireProject().linkRegistry, links);
          expect(await seenIn(tester, s, also: const [(20, 5)]), seen);
          expect(
            find.byKey(const ValueKey<String>('fx-rasterize-rows-freed')),
            findsNothing,
          );

          s.undo();
          expect(rowsOf(s), before);
          s.playbackRig.prerenderScheduler.cancel();
        });

        testWidgets('🎯synced, alike: the other row keeps its links to the '
            "cel it showed, and the rider's ride the row's new cels", (
          tester,
        ) async {
          final s = ridersOf(linked: true, free: false);
          final before = rowsOf(s);
          final seen = await seenIn(tester, s, also: const [(20, 5)]);
          final q = rowIn(s, second, 'q');

          await press(tester, s, const LayerId('a'));

          final (r, self) = (rowIn(s, cutId, 'r'), rowIn(s, second, 'q'));
          expect(r.frames, hasLength(4));
          expect(r.frames.first.id, const FrameId('r-1'));
          expect(self.frames, r.frames, reason: 'one bank');
          expect(self.baseFrameLinks, q.baseFrameLinks, reason: 'kept');
          expect(self.timeline, q.timeline);
          expect(r.baseFrameLinks, {
            for (final (index, cel) in aIn(s).frames.indexed)
              cel.id: r.frames[index + 1].id,
          });
          expect(await seenIn(tester, s, also: const [(20, 5)]), seen);

          s.undo();
          expect(rowsOf(s), before);
          s.playbackRig.prerenderScheduler.cancel();
        });

        test('one not linked to it is none of its: the bake leaves its cut '
            'be', () {
          final plan = ridersOf(
            linked: false,
          ).layerMerging.planOfFx(const LayerId('a'), bright)!;
          expect(plan.others, isEmpty);
          expect(
            [for (final cel in plan.riders.single.frames) cel.name],
            ['1', '1-2', '1-3'],
          );
        });
      });
    });
  });

  /// 🗣️I-120-Q7 (유저 2026-11-04 「트랙의 콘티가 있는 컷 전부에서 같이
  /// 굽는다」) — a panel shown as more than one picture parted (Q17), and a
  /// row synced on the conte showing more than one over a panel made free
  /// (Q18).
  group("④c — a row of a track's conte is baked in every cut of the track "
      'that has the conte, each by its own values and timing into a bank of '
      'its own (Q7)', () {
    const other = CutId('cut2');
    const bare = CutId('cut3');

    /// A brightness fx standing still at [value].
    LayerEffect still(double value) => LayerEffect(
      id: bright,
      kind: EffectKind.brightnessContrast,
      parameters: {'brightness': EffectParameter(value: value)},
    );

    /// A cut [id] of the conte [base] — its panel `1` over frames 0..1 and
    /// `2` over frame 2 — wearing [fx], and riding it the track's row `K1`
    /// as [rider] names it, its cels `1` · `2` one for each panel: synced,
    /// or [free] on blocks of its own, wearing [riderFx].
    Cut conteCut(
      CutId id,
      String base,
      String rider, {
      List<LayerEffect> fx = const [],
      List<LayerEffect> riderFx = const [],
      bool free = false,
    }) {
      FrameId cel(String row, int n) => FrameId('$row-$n');
      List<Frame> cels(String row) => [
        for (final n in [1, 2])
          Frame(id: cel(row, n), duration: 1, name: '$n', strokes: const []),
      ];
      Map<int, TimelineExposure> panels(String row) => {
        0: TimelineExposure.drawing(
          cel(row, 1),
          length: 2,
          memo: const ExposureMemo(actionMemo: 'PAN', inkId: 'ink-1'),
        ),
        2: TimelineExposure.drawing(cel(row, 2), length: 1),
      };
      return Cut(
        id: id,
        name: id.value,
        duration: 3,
        canvasSize: canvasSize,
        layers: [
          Layer(
            id: LayerId(base),
            name: 'Conte',
            kind: LayerKind.storyboard,
            effects: fx,
            frames: cels(base),
            timeline: panels(base),
          ),
          Layer(
            id: LayerId(rider),
            name: 'K1',
            kind: LayerKind.storyboard,
            attachedToLayerId: LayerId(base),
            attachedPlacement: AttachedPlacement.above,
            attachedMode: free ? AttachedMode.free : AttachedMode.synced,
            conteKey: const ConteKey('K1'),
            effects: riderFx,
            frames: cels(rider),
            baseFrameLinks: free
                ? const {}
                : {cel(base, 1): cel(rider, 1), cel(base, 2): cel(rider, 2)},
            timeline: free ? panels(rider) : const {},
          ),
          createCameraLayer(cutId: id),
        ],
      );
    }

    /// A track of the cut stood in — its conte `s`, `k` riding it — and
    /// [other] — its conte `t`, `j` riding it — each made by [cut], and a
    /// cut with no conte after: every conte's cel green in the canvas's
    /// third tile, every rider's red in the second.
    EditorSessionManager trackOf(
      Cut Function(CutId id, String base, String rider) cut,
    ) {
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
                cut(cutId, 's', 'k'),
                cut(other, 't', 'j'),
                Cut(
                  id: bare,
                  name: 'bare',
                  duration: 3,
                  canvasSize: canvasSize,
                  layers: [createCameraLayer(cutId: bare)],
                ),
              ],
            ),
          ],
          createdAt: DateTime.utc(2026),
        ),
      );
      addTearDown(s.dispose);
      inkEveryCel(s);
      return s;
    }

    /// [row]'s blocks: each one's start, its length and its cel's name.
    Map<int, (int?, String?)> blocksOf(Layer row) => {
      for (final MapEntry(key: start, value: block) in row.timeline.entries)
        start: (
          block.length,
          row.frames.firstWhere((cel) => cel.id == block.frameId).name,
        ),
    };

    /// What each cut shows of its conte and of the row riding it.
    Future<List<List<int>>> seen(WidgetTester tester, EditorSessionManager s) =>
        seenIn(tester, s, also: const [(20, 5)]);

    testWidgets("🎯a still fx on the conte: every cut of the track's conte "
        'bakes it by its own value into cels of its own, its panels as they '
        'were — the row synced on it showing what it showed, linked to its '
        'new cels — and one undo gives every cut back', (tester) async {
      final s = trackOf(
        (id, base, rider) =>
            conteCut(id, base, rider, fx: [still(id == cutId ? 60 : 30)]),
      );
      final before = rowsOf(s);
      final looks = await seen(tester, s);
      expect(looks[0], isNot(looks[6]), reason: '⛔전제: each its own value');

      await press(tester, s, const LayerId('t'));

      for (final (index, (cut, base, rider)) in [
        (cutId, 's', 'k'),
        (other, 't', 'j'),
      ].indexed) {
        final conte = rowIn(s, cut, base);
        expect(blocksOf(conte), {0: (2, '1'), 2: (1, '2')});
        expect(
          conte.timeline[0]!.memo,
          const ExposureMemo(actionMemo: 'PAN', inkId: 'ink-1'),
          reason: "the sheet's writing on its panel",
        );
        expect(
          conte.frames.map((cel) => cel.id),
          isNot(contains(FrameId('$base-1'))),
        );
        expect(
          conte.effects.single,
          LayerEffect(id: bright, kind: EffectKind.brightnessContrast),
        );
        final riding = rowIn(s, cut, rider);
        expect(riding.frames, before[index].byId(LayerId(rider))!.frames);
        expect(riding.baseFrameLinks, {
          conte.frames[0].id: FrameId('$rider-1'),
          conte.frames[1].id: FrameId('$rider-2'),
        });
      }
      expect(
        rowIn(s, cutId, 's').frames.toSet().intersection(
          rowIn(s, other, 't').frames.toSet(),
        ),
        isEmpty,
        reason: 'a bank of its own',
      );
      expect(rowsOf(s).last, before.last, reason: 'a cut with no conte');
      expect(await seen(tester, s), looks);

      s.undo();
      expect(rowsOf(s), before);
      s.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets('🚨Q17 — a keyed fx read by the frame shows a panel as two '
        'pictures: the conte parts it as any row parts its block, the head '
        "keeping the sheet's writing, and the row synced on it keeps over the "
        'new panel a copy of the picture it showed there, named with a tail — '
        'nothing said, and one undo gives every cut back (유저 11-05 「칸을 '
        '나눈다(보통 레이어와 같은 법)」)', (tester) async {
      final s = trackOf(
        (id, base, rider) => conteCut(id, base, rider, fx: [brightness()]),
      );
      final before = rowsOf(s);
      final looks = await seen(tester, s);

      await press(tester, s, const LayerId('s'));

      for (final (cut, base, rider) in [
        (cutId, 's', 'k'),
        (other, 't', 'j'),
      ]) {
        final conte = rowIn(s, cut, base);
        expect(blocksOf(conte), {0: (1, '1'), 1: (1, '1-2'), 2: (1, '2')});
        expect(
          [conte.timeline[0]!.memo, conte.timeline[1]!.memo],
          [const ExposureMemo(actionMemo: 'PAN', inkId: 'ink-1'), null],
        );
        final riding = rowIn(s, cut, rider);
        expect(riding.attachedMode, AttachedMode.synced);
        expect([for (final cel in riding.frames) cel.name], ['1', '1-2', '2']);
        expect(
          [riding.frames[0].id, riding.frames[2].id],
          [FrameId('$rider-1'), FrameId('$rider-2')],
        );
        expect(riding.baseFrameLinks, {
          for (final (index, block) in conte.timeline.values.indexed)
            block.frameId!: riding.frames[index].id,
        });
      }
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('fx-rasterize-rows-freed')),
        findsNothing,
      );
      expect(await seen(tester, s), looks, reason: 'the copy its picture');

      s.undo();
      expect(rowsOf(s), before);
      s.playbackRig.prerenderScheduler.cancel();
    });

    test('🚨a band whose edge falls inside a panel parts it there (Q17): the '
        "panel's cel kept where the band leaves it, the row synced on it "
        'keeping its own there and a copy over the part — minted under the '
        'id its settle gives a mirror; one along its panels bakes the pressed '
        'cut alone', () {
      final s = trackOf(
        (id, base, rider) => conteCut(id, base, rider, fx: [still(60)]),
      );
      final before = rowsOf(s);

      final parted = s.layerMerging.planOfFx(
        const LayerId('s'),
        bright,
        band: (start: 1, end: 3),
      )!;
      final cels = parted.layers.byId(const LayerId('s'))!;
      expect(blocksOf(cels), {0: (1, '1'), 1: (1, '1-2'), 2: (1, '2')});
      expect(cels.timeline[0]!.frameId, const FrameId('s-1'));
      final part = cels.timeline[1]!.frameId!;
      final riding = parted.layers.byId(const LayerId('k'))!;
      expect([for (final cel in riding.frames) cel.id], [
        const FrameId('k-1'),
        attachedMirrorCelId(const LayerId('k'), part),
        const FrameId('k-2'),
      ]);
      expect(riding.frames[1].name, '1-2');
      expect(riding.baseFrameLinks, {
        const FrameId('s-1'): const FrameId('k-1'),
        part: riding.frames[1].id,
        cels.timeline[2]!.frameId!: const FrameId('k-2'),
      });
      final copy = parted.copies.single;
      expect((copy.cut.id, copy.row), (cutId, const LayerId('k')));
      expect(copy.minted, {const FrameId('k-1'): riding.frames[1].id});

      final plan = s.layerMerging.planOfFx(
        const LayerId('s'),
        bright,
        band: (start: 2, end: 3),
      )!;
      final conte = plan.layers.byId(const LayerId('s'))!;
      expect(blocksOf(conte), {0: (2, '1'), 2: (1, '2')});
      expect(conte.timeline[0]!.frameId, const FrameId('s-1'));
      expect(conte.timeline[2]!.frameId, isNot(const FrameId('s-2')));
      expect(
        {for (final cut in plan.others) cut.cut.id: cut.layers},
        {other: before[1]},
        reason: 'the other cut showing what it showed',
      );
    });

    testWidgets('🎯a still fx on a row riding the conte, which wears its own '
        '(I-99): it bakes in every cut, staying synced — a cel for each of '
        "the conte's, the conte as it was", (tester) async {
      final s = trackOf(
        (id, base, rider) =>
            conteCut(id, base, rider, riderFx: [still(id == cutId ? 60 : 30)]),
      );
      final before = rowsOf(s);
      final looks = await seen(tester, s);

      await press(tester, s, const LayerId('k'));

      for (final (index, (cut, base, rider)) in [
        (cutId, 's', 'k'),
        (other, 't', 'j'),
      ].indexed) {
        final riding = rowIn(s, cut, rider);
        expect(riding.attachedMode, AttachedMode.synced);
        expect(riding.timeline, isEmpty);
        expect([for (final cel in riding.frames) cel.name], ['1', '2']);
        expect(
          riding.frames.map((cel) => cel.id),
          isNot(contains(FrameId('$rider-1'))),
        );
        expect(riding.baseFrameLinks, {
          FrameId('$base-1'): riding.frames[0].id,
          FrameId('$base-2'): riding.frames[1].id,
        });
        expect(rowIn(s, cut, base), before[index].byId(LayerId(base)));
      }
      expect(await seen(tester, s), looks);
      s.playbackRig.prerenderScheduler.cancel();
    });

    testWidgets("🚨Q18 — keyed, two pictures over one of the conte's panels: "
        "that cut's row goes free on a timing of its own, its block parted "
        'where its picture changes, riding the conte still — a cut whose row '
        'shows one picture a panel stays synced — and the press says so '
        'after; one undo gives every cut back (유저 11-05 「그 행을 자유(자기 '
        '타이밍)로 바꾼다 — 병합과 같은 법」)', (tester) async {
      final s = trackOf(
        (id, base, rider) => conteCut(
          id,
          base,
          rider,
          riderFx: [if (id == cutId) brightness() else still(30)],
        ),
      );
      final before = rowsOf(s);
      final looks = await seen(tester, s);

      await press(tester, s, const LayerId('k'));

      final freed = rowIn(s, cutId, 'k');
      expect(
        (freed.attachedToLayerId, freed.attachedMode),
        (const LayerId('s'), AttachedMode.free),
      );
      expect(freed.baseFrameLinks, isEmpty);
      expect(blocksOf(freed), {0: (1, '1'), 1: (1, '1-2'), 2: (1, '2')});
      final kept = rowIn(s, other, 'j');
      expect(kept.attachedMode, AttachedMode.synced);
      expect(kept.timeline, isEmpty);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('fx-rasterize-rows-freed')),
        findsOneWidget,
      );
      expect(
        find.text(
          AppText.strings.tlFxBakeRowsFreedTemplate.replaceAll('{names}', 'K1'),
        ),
        findsOneWidget,
      );
      expect(await seen(tester, s), looks);

      s.undo();
      expect(rowsOf(s), before);
      s.playbackRig.prerenderScheduler.cancel();
    });

    test("🚨Q18 — the timing is the link group's: a 겸용 cut's row goes free "
        'with the one that shows two pictures over a panel, though it shows '
        'one a panel itself — a mount is synced only where every use agrees '
        "— and holds each cel its timing shows, the bank's every one", () {
      final s = trackOf(
        (id, base, rider) => conteCut(
          id,
          base,
          rider,
          riderFx: [if (id == cutId) brightness() else still(30)],
        ),
      );
      s.cutVerbs.createLinkedCutFromActiveCut();
      // Its own still, one picture a panel there.
      s.repository.replaceLayer(
        layer: s.requireActiveCut.layers
            .firstWhere((row) => row.name == 'K1')
            .copyWith(effects: [still(30)]),
      );
      final plan = s.layerMerging.planOfFx(const LayerId('k'), bright)!;
      final rows = {
        for (final (:cut, :layers) in [
          (cut: plan.cut, layers: plan.layers),
          ...plan.others,
        ])
          for (final row in layers)
            if (row.name == 'K1') cut.id: row,
      };
      final twin = rows.entries.singleWhere(
        (row) => row.key != cutId && row.key != other,
      );
      expect(
        [rows[cutId]!.attachedMode, twin.value.attachedMode],
        [AttachedMode.free, AttachedMode.free],
      );
      expect(rows[other]!.attachedMode, AttachedMode.synced);
      expect(plan.freed, ['K1']);
      for (final row in [rows[cutId]!, twin.value]) {
        expect(
          {for (final block in row.timeline.values) block.frameId},
          everyElement(isIn({for (final cel in row.frames) cel.id})),
          reason: '${row.id.value} shows only cels it holds',
        );
      }
    });

    testWidgets('a free row riding the conte parts its own block where its '
        'picture changes, in every cut, each showing what it showed', (
      tester,
    ) async {
      final s = trackOf(
        (id, base, rider) =>
            conteCut(id, base, rider, riderFx: [brightness()], free: true),
      );
      final looks = await seen(tester, s);
      expect(
        coloursOf(looks.sublist(3, 6)),
        hasLength(3),
        reason: '⛔전제: it wears its own fx',
      );

      await press(tester, s, const LayerId('k'));

      for (final (cut, rider) in [(cutId, 'k'), (other, 'j')]) {
        expect(blocksOf(rowIn(s, cut, rider)), {
          0: (1, '1'),
          1: (1, '1-2'),
          2: (1, '2'),
        });
      }
      expect(await seen(tester, s), looks);
      s.playbackRig.prerenderScheduler.cancel();
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
  });
}
