// The first lift compiles the kernels and the pool's: tens of seconds on a
// machine this busy.
@Timeout(Duration(minutes: 3))
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/canvas_selection.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/selection_clip.dart';
import 'package:anicel/src/services/selection_lift.dart';
import 'package:anicel/src/ui/canvas/canvas_selection_layer.dart';

import '../helpers/poll_until.dart';
import '../helpers/surface_rgba_in_place.dart';

/// 🚨WHAT A BOX AT REST CUTS AHEAD IS WHAT A PRESS CUTS, AND WAITS FOR NO
/// GPU (card opening-a-transform-box-holds-the-ui-over-half-a-second,
/// 2026-11-20): a cel's lift, its hole and its float each have a door that
/// is asked and told later — `buildSelectionLiftDabsOnceTold`,
/// `materializeStampOnceTold` and what stands on it — beside the one a
/// press waits at. Held here pixel for pixel to the waited ones, over boxes
/// that straddle tile edges, whole pixels or a feather's, under a
/// selection's mask too; and asked while the engine's thread stands still.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const side = 128;
  const canvas = CanvasSize(width: 512, height: 512);
  final ledger = EngineTileLedger.instance;

  BitmapTile tileOf(int seed) {
    final bytes = Uint8List(side * side * 4);
    for (var i = 0; i < side * side; i += 1) {
      final o = i * 4;
      if ((i + seed) % 5 == 0) {
        continue;
      }
      bytes
        ..[o] = (i * 31 + seed) % 256
        ..[o + 1] = (i * 17) % 256
        ..[o + 2] = (i * 13 + 5) % 256
        ..[o + 3] = (i * 7 + seed) % 256;
    }
    return BitmapTile(size: side, pixels: bytes);
  }

  BitmapSurface artwork() => BitmapSurface(
    canvasSize: canvas,
    tileSize: side,
    tiles: {
      TileCoord(x: 0, y: 0): tileOf(0),
      TileCoord(x: 1, y: 0): tileOf(3),
      TileCoord(x: 0, y: 1): tileOf(7),
      TileCoord(x: -1, y: -1): tileOf(11),
    },
  );

  BitmapSurface bare() => BitmapSurface(canvasSize: canvas, tileSize: side);

  CanvasSelectionRegion rect(int left, int top, int right, int bottom) =>
      CanvasSelectionRegion.shape(
        CanvasSelectionShape.rect(
          left: left.toDouble(),
          top: top.toDouble(),
          right: right.toDouble(),
          bottom: bottom.toDouble(),
        ),
      );

  /// How many pixels of [got] differ from [from]'s — failing at the first
  /// where it parts from [want], over the box the artwork and every outline
  /// here lie in.
  int changedAs(
    BitmapSurface got,
    BitmapSurface want, {
    required BitmapSurface from,
  }) {
    var changed = 0;
    for (var y = -40; y < 260; y += 1) {
      for (var x = -40; x < 260; x += 1) {
        final has = surfaceRgbaInPlace(got, x, y);
        final wants = surfaceRgbaInPlace(want, x, y);
        if (has != wants) {
          fail(
            '$x,$y: told ${has?.toRadixString(16)} where the waited one has '
            '${wants?.toRadixString(16)}',
          );
        }
        if (has != surfaceRgbaInPlace(from, x, y)) {
          changed += 1;
        }
      }
    }
    return changed;
  }

  /// [dab] laid on [surface] waited for, under [selection] if any.
  BrushSurfaceMaterialization waited(
    BitmapSurface surface,
    BrushDab dab, {
    SelectionClip? selection,
  }) => materializeBrushDabSequenceOnBitmapSurface(
    surface: surface,
    sequence: BrushDabSequence([dab]),
    selection: selection,
  );

  /// How many landings were told unput ([told]), once the engine has done
  /// all it was handed.
  var unput = 0;
  setUp(() => unput = 0);

  /// [dab] laid on [surface] once told, under [selection] if any.
  Future<BrushSurfaceMaterialization> told(
    BitmapSurface surface,
    BrushDab dab, {
    SelectionClip? selection,
  }) => patiently(
    materializeStampOnceTold(
      surface: surface,
      dab: dab,
      selection: selection,
      unput: () => unput += 1,
    ),
  );

  final outlines = <String, CanvasSelectionRegion>{
    'across a tile edge': rect(100, 20, 160, 40),
    'across four tiles, one of them none': rect(100, 100, 160, 160),
    'off the top-left': rect(-30, -20, 20, 20),
    'an ellipse across a tile edge': CanvasSelectionRegion.shape(
      CanvasSelectionShape.ellipse(
        left: 90.5,
        top: 10.25,
        right: 170.75,
        bottom: 70.5,
      ),
    ),
  };
  const softnesses = [
    SelectionMaskOptions.none,
    SelectionMaskOptions(featherPx: 4),
  ];

  for (final MapEntry(key: name, value: region) in outlines.entries) {
    for (final options in softnesses) {
      test('$name, feather ${options.featherPx}: the lift, its hole and its '
          'float once told are the ones waited for', () async {
        final surface = artwork();
        final reads = ledger.debugTileReads;
        final press = buildSelectionLiftDabs(
          region: region,
          surface: surface,
          liftId: 'press',
          options: options,
        );
        final built = debugSelectionLiftsBuilt;
        final ahead = await patiently(
          buildSelectionLiftDabsOnceTold(
            region: region,
            surface: surface,
            liftId: 'ahead',
            options: options,
          ),
        );
        expect(press, isNotNull, reason: '⛔premise: it takes something');
        expect(ahead, isNotNull);
        expect(debugSelectionLiftsBuilt, built + 1, reason: 'a lift built');
        expect(ledger.debugTileReads, reads, reason: 'no tile read back');
        expect(ahead!.stampDab.center, press!.stampDab.center);
        expect(ahead.stampDab.size, press.stampDab.size);
        expect(ahead.eraseDab.center, press.eraseDab.center);
        expect(ahead.eraseDab.erase, isTrue);
        expect(ahead.stampDab.stamp!.id, 'lift-stamp-ahead');
        expect(ahead.eraseDab.stamp!.id, 'lift-erase-ahead');

        // Each of the told one's dabs over the surface it was lifted off:
        // the hole, then the float on a ground of its own.
        final hole = await told(surface, ahead.eraseDab);
        final holeWaited = waited(surface, press.eraseDab);
        expect(hole.dirtyTiles.coords, holeWaited.dirtyTiles.coords);
        expect(
          changedAs(hole.surface, holeWaited.surface, from: surface),
          isNonZero,
          reason: '⛔premise: the hole takes something',
        );

        final float = await told(bare(), ahead.stampDab);
        final floatWaited = waited(bare(), press.stampDab);
        expect(float.dirtyTiles.coords, floatWaited.dirtyTiles.coords);
        expect(
          changedAs(float.surface, floatWaited.surface, from: bare()),
          isNonZero,
          reason: '⛔premise: the float carries something',
        );

        await patiently(appGpuEngine.done());
        expect(unput, 0, reason: 'every tile told was put');
      });
    }
  }

  test('a tile the hole leaves as it was is the very tile, and one it clears '
      'whole is gone — as the waited one leaves them', () async {
    final surface = artwork();
    // The whole of the origin tile, and an edge of the two beside it.
    final lift = buildSelectionLiftDabs(
      region: rect(0, 0, 140, 140),
      surface: surface,
      liftId: 'whole',
    )!;

    final hole = await told(surface, lift.eraseDab);

    final origin = TileCoord(x: 0, y: 0);
    final beside = TileCoord(x: 1, y: 0);
    final below = TileCoord(x: 0, y: 1);
    final away = TileCoord(x: -1, y: -1);
    expect(hole.dirtyTiles.coords, {origin, beside, below});
    expect(hole.surface.tileAt(origin), isNull, reason: 'cleared whole');
    expect(hole.surface.tileAt(beside), isNot(same(surface.tileAt(beside))));
    expect(hole.surface.tileAt(below), isNot(same(surface.tileAt(below))));
    expect(hole.surface.tileAt(away), same(surface.tileAt(away)));
    changedAs(
      hole.surface,
      waited(surface, lift.eraseDab).surface,
      from: surface,
    );
  });

  test('a selection that takes nothing is no lift, told or waited for: over '
      'no tile, and over a pixel nothing is painted on', () async {
    final surface = artwork();
    for (final region in [rect(300, 300, 340, 340), rect(0, 0, 1, 1)]) {
      expect(
        buildSelectionLiftDabs(region: region, surface: surface, liftId: 'a'),
        isNull,
        reason: '⛔premise: the waited one takes nothing',
      );
      expect(
        await patiently(
          buildSelectionLiftDabsOnceTold(
            region: region,
            surface: surface,
            liftId: 'b',
          ),
        ),
        isNull,
      );
    }
  });

  test('a stamp that changes nothing leaves the surface it was laid on, the '
      'very one, and one past the wall is not asked at all', () async {
    final surface = artwork();
    final lift = buildSelectionLiftDabs(
      region: rect(100, 20, 160, 40),
      surface: surface,
      liftId: 'nothing',
    )!;
    final cut = (await told(surface, lift.eraseDab)).surface;

    // Cut again where it is already cut: every tile the same.
    final again = await told(cut, lift.eraseDab);
    expect(again.hasChanges, isFalse);
    expect(again.surface, same(cut));

    final away = lift.stampDab.copyWith(
      center: CanvasPoint(x: 9000, y: 9000),
    );
    final walled = BitmapSurface(
      canvasSize: canvas,
      tileSize: side,
      pasteboardReach: PasteboardReach.none,
    );
    final asked = ledger.debugSlotsAsked;
    final past = await told(walled, away);
    expect(past.hasChanges, isFalse);
    expect(past.surface, same(walled));
    expect(ledger.debugSlotsAsked, asked, reason: 'no tile asked for');
    expect(
      waited(walled, away).hasChanges,
      isFalse,
      reason: '⛔premise: the waited one lands nothing there',
    );
  });

  test('under a selection\'s mask a stamp laid once told is the stamp laid '
      'waited — and a selection that covers none of it is not asked', () async {
    final surface = artwork();
    final lift = buildSelectionLiftDabs(
      region: rect(100, 100, 160, 160),
      surface: surface,
      liftId: 'masked',
    )!;
    final moved = lift.stampDab.copyWith(
      center: CanvasPoint(
        x: lift.stampDab.center.x - 40,
        y: lift.stampDab.center.y - 50,
      ),
    );
    SelectionClip clipOf(CanvasSelectionRegion region) => SelectionClip.of(
      region,
      wall: surface.pasteboard,
      options: const SelectionMaskOptions(featherPx: 3),
    );
    final within = clipOf(rect(70, 60, 110, 100));

    final laid = await told(surface, moved, selection: within);
    final laidWaited = waited(surface, moved, selection: within);

    expect(laid.dirtyTiles.coords, laidWaited.dirtyTiles.coords);
    final changed = changedAs(laid.surface, laidWaited.surface, from: surface);
    expect(changed, isNonZero, reason: '⛔premise: it lands something');
    final whole = waited(surface, moved).surface;
    expect(
      changedAs(whole, whole, from: surface),
      greaterThan(changed),
      reason: '⛔premise: the mask cuts the stamp',
    );

    final elsewhere = clipOf(rect(300, 300, 330, 330));
    final asked = ledger.debugSlotsAsked;
    final none = await told(surface, moved, selection: elsewhere);
    expect(none.hasChanges, isFalse);
    expect(none.surface, same(surface));
    expect(ledger.debugSlotsAsked, asked, reason: 'no tile asked for');
  });

  test('where the gather is Dart\'s the waited lift answers — the engine\'s '
      'thread standing still, it is not asked', () async {
    final surface = artwork();
    final region = rect(100, 20, 160, 40);
    debugSelectionLiftInDart = true;
    addTearDown(() => debugSelectionLiftInDart = false);
    final inDart = buildSelectionLiftDabs(
      region: region,
      surface: surface,
      liftId: 'dart',
    )!;
    await patiently(appGpuEngine.done());
    appGpuEngine.debugStandStill(const Duration(seconds: 2));
    final asked = Stopwatch()..start();

    final lift = await patiently(
      buildSelectionLiftDabsOnceTold(
        region: region,
        surface: surface,
        liftId: 'told',
      ),
    );

    expect(
      asked.elapsed,
      lessThan(const Duration(seconds: 1)),
      reason: 'a lift asked of the engine',
    );
    expect(lift!.stampDab.stamp!.rgba, inDart.stampDab.stamp!.rgba);
    await patiently(appGpuEngine.done());
  });

  test('a dab that is no stamp is refused: a stroke lands by its stroke',
      () async {
    final lift = buildSelectionLiftDabs(
      region: rect(100, 20, 160, 40),
      surface: artwork(),
      liftId: 'refused',
    )!;
    final stroke = BrushDab(
      center: lift.stampDab.center,
      color: 0xFF000000,
      size: 8,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: lift.stampDab.tipShape,
      pressure: 1,
      sequence: 0,
    );
    await expectLater(
      materializeStampOnceTold(surface: artwork(), dab: stroke, unput: () {}),
      throwsArgumentError,
    );
  });

  group('the doors a box at rest goes by', () {
    BrushFrameKey key(String frameId) => BrushFrameKey(
      projectId: const ProjectId('project'),
      trackId: const TrackId('track'),
      cutId: const CutId('cut'),
      layerId: const LayerId('layer'),
      frameId: FrameId(frameId),
    );

    test('a cel\'s hole derived once told is the hole derived waited, of the '
        'cel named — and null where it changes nothing', () async {
      final standing = key('standing');
      final other = key('other');
      final coordinator = BrushFrameEditingCoordinator(
        initialFrameKey: standing,
        frameStore: BrushFrameStore(),
        sessionStore: BrushFrameEditSessionStore(
          canvasSize: canvas,
          tileSize: side,
        ),
        historyPolicy: const BrushHistoryPolicy(retainedSessionLimit: 4),
      );
      coordinator.restoreSurfaceSnapshot(other, artwork());
      final lift = buildSelectionLiftDabs(
        region: rect(100, 100, 160, 160),
        surface: coordinator.currentSurfaceOf(other),
        liftId: 'derived',
      )!;

      final hole = await patiently(
        coordinator.deriveSurfaceOnceTold(
          lift.eraseDab,
          key: other,
          unput: () => unput += 1,
        ),
      );
      final holeWaited = coordinator.deriveSurfaceWith([
        lift.eraseDab,
      ], key: other);

      final uncut = coordinator.currentSurfaceOf(other);
      expect(
        changedAs(hole!, holeWaited!, from: uncut),
        isNonZero,
        reason: '⛔premise: the hole takes something',
      );
      expect(
        coordinator.currentSurfaceOf(other).tileAt(TileCoord(x: 0, y: 0)),
        isNotNull,
        reason: 'nothing is committed',
      );
      // The cel stood on holds nothing: the same erase changes nothing.
      expect(
        coordinator.deriveSurfaceWith([lift.eraseDab]),
        isNull,
        reason: '⛔premise: the waited one answers null',
      );
      expect(
        await patiently(
          coordinator.deriveSurfaceOnceTold(
            lift.eraseDab,
            unput: () => unput += 1,
          ),
        ),
        isNull,
      );
      await patiently(appGpuEngine.done());
      expect(unput, 0);
    });

    test('a float\'s surface laid once told is the one laid waited, and '
        'counted as one laid', () async {
      final surface = artwork();
      final lift = buildSelectionLiftDabs(
        region: rect(-30, -20, 20, 20),
        surface: surface,
        liftId: 'float',
      )!;
      final wall = surface.pasteboard;
      final made = debugFloatSurfacesMade;

      final float = await patiently(
        floatSurfaceOnceTold(lift.stampDab, wall, unput: () => unput += 1),
      );

      expect(debugFloatSurfacesMade, made + 1);
      expect(float.pasteboard, wall);
      expect(
        changedAs(
          float,
          floatSurfaceOf(lift.stampDab, wall),
          from: BitmapSurface(
            canvasSize: wall.canvas,
            pasteboardReach: wall.reach,
          ),
        ),
        isNonZero,
        reason: '⛔premise: the float carries something',
      );
    });
  });

  // 🔬What it is for: a box at rest cut a cel a turn, and each turn stood
  // for the GPU — 4 to 18 ms, and 31 to 63 with the GPU's queue full (공통,
  // S5_BA cut 352, 메인 PC 테스트 VM).
  test('🚨a lift, a hole and a float are asked while the engine\'s thread '
      'stands still — a cut ahead waits for no turn there', () async {
    final surface = artwork();
    final region = rect(100, 100, 160, 160);
    // ⛔premise: the kernels compiled, the pool's pages and the selection's
    // mask made — the engine's thread's work, which stands still below.
    final press = buildSelectionLiftDabs(
      region: region,
      surface: surface,
      liftId: 'press',
    )!;
    await told(surface, press.eraseDab);
    await told(bare(), press.stampDab);
    await patiently(appGpuEngine.done());
    appGpuEngine.debugStandStill(const Duration(seconds: 2));
    final asked = Stopwatch()..start();

    final lift = buildSelectionLiftDabsOnceTold(
      region: region,
      surface: surface,
      liftId: 'ahead',
    );
    final hole = materializeStampOnceTold(
      surface: surface,
      dab: press.eraseDab,
      unput: () => unput += 1,
    );
    final float = materializeStampOnceTold(
      surface: bare(),
      dab: press.stampDab,
      unput: () => unput += 1,
    );

    expect(
      asked.elapsed,
      lessThan(const Duration(seconds: 1)),
      reason: 'a wait for the engine\'s thread',
    );
    expect(await patiently(lift), isNotNull, reason: 'LIVENESS: it lifts');
    expect((await patiently(hole)).hasChanges, isTrue, reason: 'LIVENESS');
    expect((await patiently(float)).hasChanges, isTrue, reason: 'LIVENESS');
    expect(
      asked.elapsed,
      greaterThan(const Duration(seconds: 1)),
      reason: '⛔premise: the engine\'s thread stood still meanwhile',
    );
  });
}
