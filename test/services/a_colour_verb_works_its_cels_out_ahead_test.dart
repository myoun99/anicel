import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
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
import 'package:anicel/src/services/commands/cel_pixel_overwrite_command.dart';

/// 🗣️F-615 (유저 2026-11-19): 「여러 블록 색 삭제할때 진행창이 멈춤. 항상
/// 하듯이 ui안멈추게 뒤에서 돌게?하고 대상 프레임 수에 맞춰서 몇퍼센트인지
/// 표시」.
///
/// A colour verb over a range worked every cel's pass out in the step, in
/// one turn of the UI isolate behind a window that could not draw. Each
/// pass is worked out AHEAD now, a cel at a time with the screen's turn
/// between two, told cel by cel; the step lands what was worked out.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);
  const tileSize = 4;

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
      bytes.setRange(5 * 4, 5 * 4 + 4, const [255, 0, 0, 255]);
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
    final command = deleteBlack(seeded());
    final events = <String>[];
    // Something else that wants the UI isolate — a frame, the window's
    // spinner — as a zero timer that asks again each time it is answered,
    // until the last cel is out.
    var asking = true;
    void ask() {
      if (!asking) {
        return;
      }
      events.add('turn');
      Timer.run(ask);
    }

    Timer.run(ask);
    await command.workAhead(undo: false)!((_) => events.add('cel'));
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
  });

  test('a cel drawn on after its pass was worked out is passed where the '
      'step lands it, over what it holds now', () async {
    final bare = seeded();
    final coordinator = seeded();
    final command = deleteBlack(coordinator);
    await command.workAhead(undo: false)!((_) {});
    // Cel b drawn on since: all of it red now, in the reference too.
    for (final drawnOn in [bare, coordinator]) {
      final red = Uint8List(tileSize * tileSize * 4);
      for (var pixel = 0; pixel < tileSize * tileSize; pixel += 1) {
        red.setRange(pixel * 4, pixel * 4 + 4, const [255, 0, 0, 255]);
      }
      drawnOn.restoreSurfaceSnapshot(
        cels[1],
        BitmapSurface(
          canvasSize: canvasSize,
          tileSize: tileSize,
          tiles: {
            TileCoord(x: 0, y: 0): BitmapTile(
              size: tileSize,
              pixels: red,
            ),
          },
        ),
      );
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

  test('🔬the landing of many cels is heard as ONE edit — one pixel '
      'announcement naming every revision it left, one crossing naming '
      'every cel it emptied — and so is its undo', () async {
    final coordinator = seeded();
    final store = coordinator.frameStore;
    final command = CelPixelOverwriteCommand.clearPixels(
      coordinator: coordinator,
      targets: [for (final cel in cels) CelPixelTarget(key: cel)],
    );
    await command.workAhead(undo: false)!((_) {});
    var pixels = 0;
    var crossings = 0;
    void heardPixels() => pixels += 1;
    void heardCrossings() => crossings += 1;
    store.celPixelRevision.addListener(heardPixels);
    store.celContentRevision.addListener(heardCrossings);
    addTearDown(() {
      store.celPixelRevision.removeListener(heardPixels);
      store.celContentRevision.removeListener(heardCrossings);
    });

    command.execute();
    expect((pixels, crossings), (1, 1));
    expect(store.revisionsLastLeft, hasLength(3));
    expect(store.celsLastCrossed, {
      for (final cel in cels) store.canonicalKeyOf(cel),
    }, reason: '⛔premise: every cel emptied');

    command.undo();
    expect((pixels, crossings), (2, 2));
    expect(store.celsLastCrossed, hasLength(3));
  });
}
