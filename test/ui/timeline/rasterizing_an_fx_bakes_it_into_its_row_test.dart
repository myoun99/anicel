import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:anicel/src/models/layer_effect.dart';
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
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/editing/fx_bake_plan.dart'
    show FxBakeChange;
import 'package:anicel/src/services/import/raster_cel_import.dart'
    show bakeCelSurface;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/export/export_frame_renderer.dart';
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

  /// What [s]'s cut shows at canvas ([x], [y]) on [frame], drawn as an
  /// export draws it.
  Future<List<int>> shownAt(
    WidgetTester tester,
    EditorSessionManager s,
    int frame,
    int x,
    int y,
  ) async {
    final cut = s.requireActiveCut;
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

  /// [cel] of `a` as its picture, at canvas ([x], [y]).
  List<int>? celAt(EditorSessionManager s, FrameId cel, int x, int y) {
    final cut = s.requireActiveCut;
    final surface = s.renderCaches.brushFrameStore.bakedSurfaceOrNull(
      s.brushFrameKeyForCut(cut, const LayerId('a'), cel),
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

  /// The cel `a` shows at each of frames 0..2.
  List<FrameId?> shownCels(EditorSessionManager s) => [
    for (var frame = 0; frame < 3; frame += 1)
      exposedFrameIdAt(a(s).timeline, frame),
  ];

  /// Presses `a`'s group header RASTERIZE for [effectId] — the transform's
  /// where null — and waits out its window.
  Future<void> rasterize(
    WidgetTester tester,
    EditorSessionManager s, [
    EffectId? effectId = bright,
  ]) async {
    final before = a(s);
    final context = await hostedContext(tester);
    unawaited(
      rasterizeFxGroup(context, s, const LayerId('a'), effectId, 'fx'),
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
    expect(seen.toSet(), hasLength(3), reason: '⛔전제: every frame its own');
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

  testWidgets('a hold repeated past its run is made of blocks of its own '
      'where each repeat shows another picture', (tester) async {
    final s = sessionOf([
      rowA(
        timeline: {
          0: const TimelineExposure.drawing(
            FrameId('a-1'),
            length: 1,
            endEdge: TimelineRunEdgeMark(mode: TimelineRunEdgeMode.repeat),
          ),
        },
      ),
    ]);
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
    EditorSessionManager plain(List<Layer> layers) {
      final s = sessionOf(layers);
      addTearDown(s.dispose);
      return s;
    }

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

    test('🚨Q2 — an fx on that runs before the one baked asks first; one '
        'off does not; the transform asks first under any fx on', () {
      LayerEffect key({bool enabled = true}) => LayerEffect(
        id: const EffectId('e-key'),
        kind: EffectKind.colorKey,
        enabled: enabled,
      );
      Set<FxBakeChange> changes(List<LayerEffect> effects, EffectId? baked) =>
          plain([rowA(effects: effects)]).layerMerging
              .planOfFx(const LayerId('a'), baked)!
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
        verbs.planOfFx(const LayerId('a'), number)!.row.effects.first.enabled,
        verbs.planOfFx(const LayerId('a'), bright)!.row.effects.last.enabled,
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
        s.layerMerging.planOfFx(const LayerId('a'), null)!.changes,
        {FxBakeChange.wall},
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

    test('a row ridden, and the row riding it (②b)', () {
      final s = sessionOf([
        rowA(),
        withBright(
          Layer(
            id: const LayerId('r'),
            name: 'R',
            attachedToLayerId: const LayerId('a'),
            attachedPlacement: AttachedPlacement.above,
            frames: [
              Frame(id: const FrameId('r-1'), duration: 3, strokes: []),
            ],
            timeline: {
              0: const TimelineExposure.drawing(FrameId('r-1'), length: 3),
            },
          ),
        ),
      ]);
      addTearDown(s.dispose);
      expect([bakes(s, 'a'), bakes(s, 'r')], [false, false]);
    });

    test('a row another cut shows too — a 겸용 (④)', () {
      final s = sessionOf([rowA()]);
      addTearDown(s.dispose);
      s.cutVerbs.createLinkedCutFromActiveCut();
      final twin = s.requireActiveCut.layers.firstWhere(
        (layer) => layer.name == 'A',
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

    test('the conte of a track (④)', () {
      final s = EditorSessionManager(initialProject: conteTrackProject());
      addTearDown(s.dispose);
      final conte = s.activeTrack.cuts.first.layers.firstWhere(
        (layer) => layer.kind == LayerKind.storyboard,
      );
      expect(s.layerMerging.bakesFx(conte.id, null), isFalse);
    });
  });
}
