import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show gpuTileSide;

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/cel_pixel_overwrite.dart' show CelPixelVerb;
import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/services/commands/brush_lift_move_history_command.dart';
import 'package:anicel/src/services/commands/cel_pixel_overwrite_command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/services/repository_step_scope.dart';

/// 🗣️F-615 (유저 2026-11-19): 「여러 블록 색 삭제할때 진행창이 멈춤. 항상
/// 하듯이 ui안멈추게 뒤에서 돌게?하고 대상 프레임 수에 맞춰서 몇퍼센트인지
/// 표시. 말한것들은 다른 진행창뜨는거에 다 통일적용」.
///
/// A colour verb over a range worked every cel's pass out in the step, in
/// one turn of the UI isolate behind a window that could not draw. Each
/// pass is worked out AHEAD now, a cel at a time with the screen's turn
/// between two, told cel by cel; the step lands what was worked out. A
/// paste's landings are worked out the same way, a cel each, and every
/// step lands as ONE edit of the cels — its undo and its redo too.
void main() {
  // The engine's grid: a paste's landing is the engine's alone.
  final tileSize = gpuTileSide;
  final canvasSize = CanvasSize(width: tileSize * 2, height: tileSize * 2);

  BrushFrameKey key(String frameId) => BrushFrameKey(
    projectId: const ProjectId('project'),
    trackId: const TrackId('track'),
    cutId: const CutId('cut'),
    layerId: const LayerId('layer'),
    frameId: FrameId(frameId),
  );

  final cels = [key('frame-a'), key('frame-b'), key('frame-c')];

  /// Three cels, each its top-left tile black with a red pixel at (1, 1).
  BrushFrameEditingCoordinator seeded() {
    final coordinator = BrushFrameEditingCoordinator(
      initialFrameKey: cels.first,
      frameStore: BrushFrameStore(),
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: canvasSize,
        tileSize: tileSize,
      ),
      historyPolicy: const BrushHistoryPolicy(retainedSessionLimit: 4),
    );
    for (final cel in cels) {
      final bytes = Uint8List(tileSize * tileSize * 4);
      for (var pixel = 0; pixel < tileSize * tileSize; pixel += 1) {
        bytes.setRange(pixel * 4, pixel * 4 + 4, const [0, 0, 0, 255]);
      }
      final red = (tileSize + 1) * 4;
      bytes.setRange(red, red + 4, const [255, 0, 0, 255]);
      coordinator.restoreSurfaceSnapshot(
        cel,
        BitmapSurface(
          canvasSize: canvasSize,
          tileSize: tileSize,
          tiles: {
            TileCoord(x: 0, y: 0): BitmapTile(
              size: tileSize,
              pixels: bytes,
            ),
          },
        ),
      );
    }
    return coordinator;
  }

  CelPixelOverwriteCommand deleteBlack(
    BrushFrameEditingCoordinator coordinator,
  ) => CelPixelOverwriteCommand.forVerb(
    coordinator: coordinator,
    targets: [for (final cel in cels) CelPixelTarget(key: cel)],
    verb: CelPixelVerb.deleteColour,
    argb: 0xFF000000,
  );

  /// Every cel's top-left tile, byte for byte.
  List<List<int>> pixelsOf(BrushFrameEditingCoordinator coordinator) => [
    for (final cel in cels)
      coordinator
          .currentSurfaceOf(cel)
          .tileAt(TileCoord(x: 0, y: 0))!
          .readPixels((_, view) => List<int>.of(view)),
  ];

  /// Paints the whole of [cel]'s top-left tile red — drawn on since.
  void drawRed(BrushFrameEditingCoordinator coordinator, BrushFrameKey cel) {
    final red = Uint8List(tileSize * tileSize * 4);
    for (var pixel = 0; pixel < tileSize * tileSize; pixel += 1) {
      red.setRange(pixel * 4, pixel * 4 + 4, const [255, 0, 0, 255]);
    }
    coordinator.restoreSurfaceSnapshot(
      cel,
      BitmapSurface(
        canvasSize: canvasSize,
        tileSize: tileSize,
        tiles: {
          TileCoord(x: 0, y: 0): BitmapTile(size: tileSize, pixels: red),
        },
      ),
    );
  }

  /// A white square two across over each cel's top-left corner — what a
  /// paste lays down.
  final white = BrushDab(
    center: CanvasPoint(x: 1, y: 1),
    color: 0xFFFFFFFF,
    size: 2,
    opacity: 1,
    flow: 1,
    hardness: 1,
    tipShape: BrushTipShape.square,
    pressure: 1,
    sequence: 0,
  );

  /// Every cel's landing of [white], as a range's paste names them.
  List<BrushLiftMoveHistoryCommand> landingsOn(
    BrushFrameEditingCoordinator coordinator,
  ) => [
    for (final cel in cels)
      BrushLiftMoveHistoryCommand(
        coordinator: coordinator,
        frameKey: cel,
        landingDabs: [white],
        description: 'Paste pixels',
      ),
  ];

  /// The step a range's paste takes: every cel's landing as one.
  Command pasted(List<BrushLiftMoveHistoryCommand> landings) =>
      oneStepOf('Paste pixels', landings)!;

  test('the step lands every pass worked out ahead, making none of its '
      'own, and lands the very pixels a step with none ahead lands', () async {
    final bare = seeded();
    deleteBlack(bare).execute();

    final coordinator = seeded();
    final command = deleteBlack(coordinator);
    await command.workAhead(undo: false)!((_) {});
    expect(command.passesHere, 3, reason: 'one pass a cel, worked out ahead');
    command.execute();
    expect(command.passesHere, 3, reason: 'the step made no pass of its own');
    expect(pixelsOf(coordinator), pixelsOf(bare));
    expect(
      pixelsOf(coordinator).first.sublist(3 * 4, 3 * 4 + 4),
      [0, 0, 0, 0],
      reason: '⛔premise: the black went',
    );
  });

  test('what it worked out is told cel by cel — a cel two rows reach once',
      () async {
    final coordinator = seeded();
    final command = CelPixelOverwriteCommand.forVerb(
      coordinator: coordinator,
      targets: [
        for (final cel in [...cels, cels.first]) CelPixelTarget(key: cel),
      ],
      verb: CelPixelVerb.deleteColour,
      argb: 0xFF000000,
    );
    final told = <double>[];
    await command.workAhead(undo: false)!(told.add);
    expect(told, [1 / 3, 2 / 3, 1]);
  });

  test('🚨the screen has its turn between two cels it works out', () async {
    await expectTheScreensTurns(
      deleteBlack(seeded()).workAhead(undo: false)!,
    );
  });

  test('a cel drawn on after its pass was worked out is passed where the '
      'step lands it, over what it holds now', () async {
    final bare = seeded();
    final coordinator = seeded();
    final command = deleteBlack(coordinator);
    await command.workAhead(undo: false)!((_) {});
    // Cel b drawn on since, in the reference too.
    for (final drawnOn in [bare, coordinator]) {
      drawRed(drawnOn, cels[1]);
    }
    deleteBlack(bare).execute();

    command.execute();
    expect(command.passesHere, 4, reason: 'cel b passed again, the rest not');
    expect(pixelsOf(coordinator), pixelsOf(bare));
  });

  test('the undo and the redo land what is worked out ahead for each', () async {
    final before = pixelsOf(seeded());
    final bare = seeded();
    deleteBlack(bare).execute();

    final coordinator = seeded();
    final command = deleteBlack(coordinator)..execute();
    expect(command.passesHere, 3);

    await command.workAhead(undo: true)!((_) {});
    expect(command.passesHere, 6, reason: 'the undo\'s passes, ahead');
    command.undo();
    expect(command.passesHere, 6, reason: 'the undo made none of its own');
    expect(pixelsOf(coordinator), before);

    await command.workAhead(undo: false)!((_) {});
    command.execute();
    expect(command.passesHere, 9, reason: 'the redo made none of its own');
    expect(pixelsOf(coordinator), pixelsOf(bare));
  });

  test('what was worked out for the undo is not the redo\'s', () async {
    final coordinator = seeded();
    final command = deleteBlack(coordinator)..execute();
    await command.workAhead(undo: true)!((_) {});
    command.execute();
    expect(
      command.passesHere,
      9,
      reason: 'a step in the other direction works its passes out itself',
    );
  });

  group('a paste', () {
    WorkAhead aheadOf(Command step) =>
        (step as WorksAheadCommand).workAhead(undo: false)!;

    test('the step lands every landing worked out ahead, deriving none of '
        'its own, and lands the very pixels a step with none ahead lands',
        () async {
      final bare = seeded();
      pasted(landingsOn(bare)).execute();

      final coordinator = seeded();
      final landings = landingsOn(coordinator);
      final step = pasted(landings);
      await aheadOf(step)((_) {});
      expect([for (final one in landings) one.derivesHere], [1, 1, 1]);
      step.execute();
      expect(
        [for (final one in landings) one.derivesHere],
        [1, 1, 1],
        reason: 'the step derived none of its own',
      );
      expect(pixelsOf(coordinator), pixelsOf(bare));
      expect(
        pixelsOf(coordinator).first.sublist(0, 4),
        [255, 255, 255, 255],
        reason: '⛔premise: the white landed',
      );
    });

    test('what it worked out is told cel by cel, as the step\'s shares',
        () async {
      final told = <double>[];
      await aheadOf(pasted(landingsOn(seeded())))(told.add);
      expect(told, [1 / 3, 2 / 3, 1]);
    });

    test('🚨the screen has its turn between two cels it works out', () async {
      await expectTheScreensTurns(aheadOf(pasted(landingsOn(seeded()))));
    });

    test('a cel drawn on after its landing was worked out is derived again '
        'over what it holds now — and its undo puts back what it held',
        () async {
      final bare = seeded();
      final coordinator = seeded();
      final landings = landingsOn(coordinator);
      final step = pasted(landings);
      await aheadOf(step)((_) {});
      for (final drawnOn in [bare, coordinator]) {
        drawRed(drawnOn, cels[1]);
      }
      final drawn = pixelsOf(coordinator);
      pasted(landingsOn(bare)).execute();

      step.execute();
      expect(
        [for (final one in landings) one.derivesHere],
        [1, 2, 1],
        reason: 'cel b derived again, the rest not',
      );
      expect(pixelsOf(coordinator), pixelsOf(bare));

      step.undo();
      expect(
        pixelsOf(coordinator),
        drawn,
        reason: 'the pre-lift is the picture the landing found',
      );
    });

    test('an undo or a redo works nothing out ahead: it puts back a '
        'picture it holds', () {
      final step = pasted(landingsOn(seeded()))..execute();
      final works = step as WorksAheadCommand;
      expect(works.workAhead(undo: true), isNull);
      step.undo();
      expect(works.workAhead(undo: false), isNull);
    });
  });

  test('🔬a step is ONE edit of the cels — one pixel announcement naming '
      'every revision it left, one crossing naming every cel it crossed — '
      'and so are its undo and its redo, whichever verb lands it', () {
    for (final (verb, step, crossed) in <(
      String,
      Command Function(BrushFrameEditingCoordinator),
      bool,
    )>[
      (
        '픽셀 비우기',
        (coordinator) => CelPixelOverwriteCommand.clearPixels(
          coordinator: coordinator,
          targets: [for (final cel in cels) CelPixelTarget(key: cel)],
        ),
        true,
      ),
      (
        '픽셀 위 붙여넣기',
        (coordinator) => pasted(landingsOn(coordinator)),
        false,
      ),
    ]) {
      final coordinator = seeded();
      final store = coordinator.frameStore;
      final history = HistoryManager()
        ..scope = RepositoryStepScope(
          ProjectRepository(initialProject: createDefaultProject()),
          cels: store,
        );
      var pixels = 0;
      var crossings = 0;
      void heardPixels() => pixels += 1;
      void heardCrossings() => crossings += 1;
      store.celPixelRevision.addListener(heardPixels);
      store.celContentRevision.addListener(heardCrossings);
      final once = crossed ? 1 : 0;

      history.execute(step(coordinator));
      expect((pixels, crossings), (1, once), reason: verb);
      expect(store.revisionsLastLeft, hasLength(3), reason: verb);
      if (crossed) {
        expect(store.celsLastCrossed, {
          for (final cel in cels) store.canonicalKeyOf(cel),
        }, reason: '⛔premise: every cel emptied');
      }

      history.undo();
      expect((pixels, crossings), (2, 2 * once), reason: '$verb, undone');
      history.redo();
      expect((pixels, crossings), (3, 3 * once), reason: '$verb, redone');
      store.celPixelRevision.removeListener(heardPixels);
      store.celContentRevision.removeListener(heardCrossings);
    }
  });
}

/// [ahead] worked out while something else wants the UI isolate — a frame,
/// the window's spinner — as a zero timer that asks again each time it is
/// answered, until the last cel is out: the screen has had a turn between
/// every two cels it tells.
Future<void> expectTheScreensTurns(WorkAhead ahead) async {
  final events = <String>[];
  var asking = true;
  void ask() {
    if (!asking) {
      return;
    }
    events.add('turn');
    Timer.run(ask);
  }

  Timer.run(ask);
  await ahead((_) => events.add('cel'));
  asking = false;

  final done = [
    for (final (index, event) in events.indexed)
      if (event == 'cel') index,
  ];
  expect(done, hasLength(3), reason: '⛔premise: three cels');
  for (var at = 1; at < done.length; at += 1) {
    expect(
      events.sublist(done[at - 1], done[at]),
      contains('turn'),
      reason: 'between cel ${at - 1} and cel $at the screen had no turn',
    );
  }
}
