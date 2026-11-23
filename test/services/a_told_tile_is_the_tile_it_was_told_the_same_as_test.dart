import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_blend_mode.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/services/bitmap_surface_brush_commit.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/brush_live_stroke_rasterizer.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/services/commands/brush_stroke_history_command.dart';
import 'package:anicel/src/services/history_manager.dart';

import '../helpers/poll_until.dart';
import '../helpers/tiles_on_the_engine.dart';

/// 🚨★A TILE TOLD THE SAME AS THE ONE IT LANDED ON IS THAT ONE (관제
/// 2026-11-24, card the-start-of-every-stroke-stalls-on-the-galaxy-tab ③-1):
/// pen-up hands the cel the tiles the stroke's steps put, their ink to be
/// told (③-2). Told, one the same as the tile under it is that tile's pixels
/// held twice, and one with no ink left is a tile of nothing — so the cel
/// takes the picture a compared landing would have left (「Same → 원래 객체 ·
/// Cleared → 버림」), and the step whose after it was takes it with the cel:
/// the bill drops by what the two share again, and the handed tile is held
/// by nobody. ㉠ No step is made of it, and only the top step, with nothing
/// undone, takes it — the one place its after is nobody else's before.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canvasSize = CanvasSize(width: 384, height: 256);
  const tileSize = 128;
  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('l'),
    frameId: FrameId('f'),
  );
  final wall = canvasSize.pasteboardAt(PasteboardReach.whole);

  /// Inked; the eraser takes a bare part of it: told the same as it was.
  final bare = TileCoord(x: 0, y: 0);

  /// Inked; the eraser takes part of the ink: ink of its own.
  final cut = TileCoord(x: 1, y: 0);

  /// One dot; the eraser takes all of it: no ink left.
  final wiped = TileCoord(x: 2, y: 0);

  /// Nothing under; the eraser takes nothing: the same as none.
  final paper = TileCoord(x: 1, y: 1);

  BrushDab dab(
    double x,
    double y, {
    required int sequence,
    double size = 20,
    double hardness = 1,
    int color = 0xD0994411,
  }) => BrushDab(
    center: CanvasPoint(x: x, y: y),
    color: color,
    size: size,
    opacity: 1,
    flow: 1,
    hardness: hardness,
    tipShape: BrushTipShape.round,
    pressure: 1,
    sequence: sequence,
  );

  /// A band of ink across [bare] and [cut], and a dot on [wiped].
  BitmapSurface painted() => materializeBrushDabSequenceOnBitmapSurface(
    surface: BitmapSurface(canvasSize: canvasSize, tileSize: tileSize),
    sequence: BrushDabSequence([
      for (var i = 0; i < 9; i += 1)
        dab(18.5 + i * 22.0, 40.5, size: 34, hardness: 0.45, sequence: i),
      dab(300.5, 60.5, size: 10, sequence: 9),
    ]),
  ).surface;

  /// Whole strength: an eraser takes as much as its colour's alpha says.
  List<BrushDab> eraser() => [
    dab(60.5, 110.5, sequence: 1, color: 0xFF000000),
    dab(150.5, 40.5, sequence: 2, color: 0xFF000000),
    dab(300.5, 60.5, size: 40, sequence: 3, color: 0xFF000000),
    dab(200.5, 200.5, sequence: 4, color: 0xFF000000),
  ];

  /// The eraser drawn over [base] as the canvas draws it, and the tiles
  /// pen-up hands over — each the one its step put.
  List<PromotedStrokeTile> erased(BitmapSurface base) {
    final stroke = BrushLiveStrokeRasterizer(
      pasteboard: wall,
      tileSize: tileSize,
    );
    final region = stroke.blendFrom(eraser(), from: 0);
    final shown = <TileCoord, ({BitmapTile tile, int revision})>{};
    for (final coord
        in region?.toTileCoords(tileSize: tileSize) ?? const <TileCoord>{}) {
      final tile = stroke.preBlendedOverlayTile(
        tileX: coord.x,
        tileY: coord.y,
        base: base,
        mode: BrushBlendMode.erase,
        erase: true,
      );
      if (tile != null) {
        shown[coord] = (tile: tile.landed, revision: tile.revision);
      }
    }
    final promoted = stroke.promoteStrokeTiles(
      base: base,
      mode: BrushBlendMode.erase,
      erase: true,
      dabs: eraser(),
      shown: shown,
    );
    stroke.clear();
    return promoted;
  }

  /// A cel standing at [painted], with its history; the eraser's tiles
  /// handed over, and its step made — not yet taken.
  ({
    BrushFrameEditingCoordinator coordinator,
    BrushFrameStore store,
    HistoryManager history,
    BitmapSurface base,
    Map<TileCoord, BitmapTile> handed,
    BrushStrokeHistoryCommand stroke,
  })
  scene() {
    final store = BrushFrameStore();
    final coordinator = BrushFrameEditingCoordinator(
      initialFrameKey: key,
      frameStore: store,
      sessionStore: BrushFrameEditSessionStore(canvasSize: canvasSize),
      historyPolicy: const BrushHistoryPolicy(),
    );
    final base = painted();
    // Its bytes here: what the bill weighs (`BitmapTile.ownBytes`).
    theCopiesComeOf([base]);
    coordinator.restoreSurfaceSnapshot(key, base);
    final promoted = erased(base);
    final handed = {for (final one in promoted) one.coord: one.tile};
    expect(
      handed.keys.toSet(),
      {bare, cut, wiped, paper},
      reason: '⛔premise: each answer is asked of a tile handed over',
    );
    final stroke = BrushStrokeHistoryCommand(
      coordinator: coordinator,
      strokeData: BrushStrokeCommitData(
        sourceDabs: eraser(),
        blendMode: BrushBlendMode.erase,
        promotedBase: base,
        promotedTiles: [
          for (final one in promoted) (coord: one.coord, tile: one.tile),
        ],
      ),
    );
    return (
      coordinator: coordinator,
      store: store,
      history: HistoryManager(),
      base: base,
      handed: handed,
      stroke: stroke,
    );
  }

  /// Every tile handed over, told.
  Future<void> told(Map<TileCoord, BitmapTile> handed) async {
    await patiently(
      Future.wait([for (final tile in handed.values) ?tile.inkTold]),
    );
    // What waited on the same answer has heard it.
    await pumpEventQueue();
  }

  /// How many of the cel's and its step's holds have [tile] at [at]: the
  /// session's picture, the baked truth, its display cache, and the two
  /// halves of the step.
  int holdersOf(
    BitmapTile tile,
    TileCoord at, {
    required BrushFrameEditingCoordinator coordinator,
    required BrushFrameStore store,
    required BrushStrokeHistoryCommand stroke,
  }) =>
      [
        coordinator.currentSurfaceOf(key).tileAt(at),
        store.displayCacheOrNull(key)?.previewSurface.tileAt(at),
        stroke.surfaces?.before.heldHere?.tileAt(at),
        stroke.surfaces?.after.heldHere?.tileAt(at),
      ].where((held) => identical(held, tile)).length +
      (store.holdsTile(at, tile) ? 1 : 0);

  Map<TileCoord, Uint8List> bytesOf(BitmapSurface surface) => {
    for (final MapEntry(:key, :value) in surface.tiles.entries)
      key: value.pixels,
  };

  test('told, the cel and its step take the picture a compared landing would '
      'have left: the same bytes, the bill down by the tile shared again, '
      'and each handed tile it let go of held by nobody', () async {
    final (:coordinator, :store, :history, :base, :handed, :stroke) =
        scene();
    history.execute(stroke);
    final taken = coordinator.currentSurfaceOf(key);
    for (final MapEntry(key: at, value: tile) in handed.entries) {
      expect(
        identical(taken.tileAt(at), tile),
        isTrue,
        reason: '⛔premise: $at is the tile handed over',
      );
    }
    final billed = history.retainedBytes;
    for (final at in [bare, wiped, paper]) {
      expect(
        holdersOf(
          handed[at]!,
          at,
          coordinator: coordinator,
          store: store,
          stroke: stroke,
        ),
        greaterThan(0),
        reason: '⛔premise: $at is held before it is told',
      );
    }

    await told(handed);

    final now = coordinator.currentSurfaceOf(key);
    expect(identical(now, taken), isFalse, reason: 'the cel took another');
    expect(
      identical(now.tileAt(bare), base.tileAt(bare)),
      isTrue,
      reason: 'told the same as the tile it landed on: that tile',
    );
    expect(now.tileAt(wiped), isNull, reason: 'told no ink is left: none');
    expect(now.tileAt(paper), isNull, reason: 'told the same as none: none');
    expect(
      identical(now.tileAt(cut), handed[cut]),
      isTrue,
      reason: 'told ink of its own: it stays',
    );
    expect(
      identical(stroke.surfaces!.after.heldHere, now),
      isTrue,
      reason: 'the step took what the cel took',
    );
    expect(
      identical(store.displayCacheOrNull(key)?.previewSurface, now),
      isTrue,
      reason: 'the display cache with it',
    );
    expect(history.undoCount, 1, reason: '㉠ no step is made of it');

    // ② The same pixels: what the cel took, byte for byte what it held.
    final was = bytesOf(taken);
    final is_ = bytesOf(now);
    for (final at in {...was.keys, ...is_.keys}) {
      final one = was[at];
      final other = is_[at];
      if (one == null || other == null) {
        expect(
          (one ?? other!).every((byte) => byte == 0),
          isTrue,
          reason: '$at holds ink on one side alone',
        );
        continue;
      }
      expect(one, other, reason: '$at: the same bytes');
    }

    // ④ What it let go of is held by nobody, and the bill says so.
    for (final at in [bare, wiped, paper]) {
      expect(
        holdersOf(
          handed[at]!,
          at,
          coordinator: coordinator,
          store: store,
          stroke: stroke,
        ),
        0,
        reason: '$at: the handed tile is held by nobody',
      );
    }
    expect(
      billed - history.retainedBytes,
      base.tileAt(bare)!.ownBytes,
      reason: 'the before shares the tile under [bare] with the after again',
    );

    history.undo();
    expect(
      identical(coordinator.currentSurfaceOf(key), base),
      isTrue,
      reason: 'undo puts back what the cel stood at',
    );
    history.redo();
    expect(
      identical(coordinator.currentSurfaceOf(key), now),
      isTrue,
      reason: 'and redo what it took',
    );
  });

  group('⛔not taken — the cel and every step as they were', () {
    /// [before] the tiles are told, [after] they are, of a scene whose step
    /// was taken — the cel's picture, the step's halves, and the bill all
    /// as they were.
    Future<void> keeps(
      String why, {
      required FutureOr<void> Function(
        HistoryManager history,
        BrushStrokeHistoryCommand stroke,
        BrushFrameEditingCoordinator coordinator,
      )
      before,
    }) async {
      final (:coordinator, store: _, :history, :base, :handed, :stroke) =
          scene();
      history.execute(stroke);
      await before(history, stroke, coordinator);
      final cel = coordinator.currentSurfaceOf(key);
      final halves = (stroke.surfaces!.before, stroke.surfaces!.after);
      final billed = history.retainedBytes;

      await told(handed);

      expect(
        identical(
          EngineTileLedger.instance.toldInPlaceOf(handed[bare]!),
          base.tileAt(bare),
        ),
        isTrue,
        reason: '⛔premise ($why): told the same as the tile under it',
      );
      expect(
        identical(coordinator.currentSurfaceOf(key), cel),
        isTrue,
        reason: '$why: the cel keeps its picture',
      );
      expect(
        identical(stroke.surfaces!.before, halves.$1) &&
            identical(stroke.surfaces!.after, halves.$2),
        isTrue,
        reason: '$why: the step keeps its halves',
      );
      expect(history.retainedBytes, billed, reason: '$why: and its bill');
    }

    test('a step above it', () => keeps(
      'a step above it',
      before: (history, stroke, coordinator) => history.execute(_Mark()),
    ));

    test('a step undone above it', () => keeps(
      'a step undone above it',
      before: (history, stroke, coordinator) {
        history.execute(_Mark());
        history.undo();
      },
    ));

    test('its before let go to the room', () => keeps(
      'its before parked',
      before: (history, stroke, coordinator) async => expect(
        await stroke.surfaces!.before.park(),
        isTrue,
        reason: '⛔premise: the room took it',
      ),
    ));

    test('the cel moved on', () => keeps(
      'the cel moved on',
      before: (history, stroke, coordinator) {
        final at = coordinator.currentSurfaceOf(key);
        coordinator.restoreSurfaceSnapshot(
          key,
          at.putTiles([
            (coord: TileCoord(x: 0, y: 1), tile: at.tileAt(cut)!),
          ]),
        );
      },
    ));
  });
}

/// A step that holds no picture.
class _Mark implements Command {
  @override
  String get description => 'mark';

  @override
  void execute() {}

  @override
  void undo() {}
}
