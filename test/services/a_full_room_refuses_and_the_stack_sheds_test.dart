import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/commands/brush_lift_move_history_command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/persistence/scratch_file.dart';
import 'package:anicel/src/services/persistence/session_scratch.dart';
import 'package:anicel/src/services/persistence/volatile_scratch_files.dart';

import '../helpers/brush_canvas_fixture.dart';

/// 🚨★★★**A FULL ROOM REFUSES, AND REFUSING IS ALREADY A LAW.** The undo
/// stack answers a refusal by standing the spill down and shedding from
/// the deep end — 「Deleting is what happens when the room refuses, and
/// only then」. A ceiling on the room is one more reason to refuse, not a
/// second way to delete: adding a deletion path here would have been the
/// same rule written twice, and the two would drift the first time one of
/// them learned something.
///
/// ⚠️Until this round the room had no ceiling at all. It could not grow
/// without bound — the stack's 200-entry cap takes parked files with the
/// entries that fall off — but 200 entries of a picture that will not
/// compress is gigabytes, and nothing said stop.
/// The same five confirms the crash round drives, which is what makes the
/// end-to-end case below comparable to it.
const _confirms = [
  (1200.0, 0xFF102030),
  (16.0, 0xFF405060),
  (16.0, 0xFF708090),
  (16.0, 0xFFA0B0C0),
  (16.0, 0xFFD0E0F0),
];

BrushDab _stampAt(double x, int colour) => BrushDab(
      center: CanvasPoint(x: x, y: 8),
      color: colour,
      size: 8,
      opacity: 1,
      flow: 1,
      hardness: 1,
      tipShape: BrushTipShape.square,
      pressure: 1,
      sequence: 0,
    );

/// What the room weighs, measured the way the room measures itself — the
/// production side is private, and a test that reimplemented it would be
/// grading its own homework.
int _volatileRoomBytes() {
  var total = 0;
  for (final entity in Directory(
    SessionScratch.volatileFolder(),
  ).listSync(followLinks: false)) {
    if (entity is File) {
      total += entity.statSync().size;
    }
  }
  return total;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    VolatileScratchFiles.ceilingBytes = 0;
  });

  final written = <String>[];
  tearDown(() {
    for (final path in written) {
      ScratchFile.remove(path);
    }
    written.clear();
    VolatileScratchFiles.ceilingBytes = 0;
  });

  test('with no ceiling the room takes what it is given', () {
    final path = VolatileScratchFiles.write(Uint8List(64 * 1024));
    if (path != null) written.add(path);
    expect(path, isNotNull);
  });

  test('🚨a write that would cross the ceiling is REFUSED', () {
    VolatileScratchFiles.ceilingBytes = 100 * 1024;

    final first = VolatileScratchFiles.write(Uint8List(60 * 1024));
    if (first != null) written.add(first);
    expect(first, isNotNull, reason: 'it fits');

    final second = VolatileScratchFiles.write(Uint8List(60 * 1024));
    expect(
      second,
      isNull,
      reason: '60 + 60 crosses 100, so the room says no and the caller '
          'keeps its bytes — which is what makes the stack shed',
    );
  });

  test('and space freed by a removed payload is space again', () {
    VolatileScratchFiles.ceilingBytes = 100 * 1024;

    final first = VolatileScratchFiles.write(Uint8List(60 * 1024))!;
    expect(
      VolatileScratchFiles.write(Uint8List(60 * 1024)),
      isNull,
      reason: 'setup: the room is full',
    );

    // What `dropPayloadsOf` does when an entry falls off the deep end.
    ScratchFile.remove(first);

    final third = VolatileScratchFiles.write(Uint8List(60 * 1024));
    if (third != null) written.add(third);
    expect(
      third,
      isNotNull,
      reason: 'the room MEASURES itself, so a file leaving is space back — '
          'a counter would have drifted here, because removal does not '
          'report to any room',
    );
  });

  test('🚨★★★and END TO END: a ceiling the real payloads cannot fit under '
      'costs entries, because refusing is what makes the stack shed', () async {
    final coordinator = BrushCanvasFixture.createCoordinator();
    final key = coordinator.activeFrameKey;

    // One byte — for RAM, and therefore for the room. Nothing can park.
    // ⚠️This value used to be the fixture for
    // `the_transforms_that_killed_the_app_keep_their_undo_test`, where it
    // meant only 「smaller than any entry」; a ceiling gave it a second
    // meaning, and this is the test the second meaning belongs to.
    final history = HistoryManager()..byteBudget = 1;
    addTearDown(history.dispose);

    for (final (x, colour) in _confirms) {
      history.execute(
        BrushLiftMoveHistoryCommand(
          coordinator: coordinator,
          frameKey: key,
          preLiftSurface: coordinator.currentSurfaceOf(key),
          landingDabs: [_stampAt(x, colour)],
        ),
      );
    }
    expect(history.undoCount, _confirms.length, reason: 'fixture premise');

    await history.drainSpilling();

    expect(
      history.undoCount,
      lessThan(_confirms.length),
      reason: 'the room took nothing, so the deep end had nowhere to go and '
          '`_shedOverBudget` — the ONE place that drops entries — ran. With '
          'room to park (16 KiB there against 1,318 bytes of files) the same '
          'five edits all survive; that is the other test',
    );
    expect(
      _volatileRoomBytes(),
      lessThanOrEqualTo(1),
      reason: 'and the ceiling held: nothing was written past it',
    );
  });

  test('🚨the stack sets the room ceiling from the same call as its own '
      'budget, so the two cannot drift', () {
    final history = HistoryManager();
    addTearDown(history.dispose);

    history.byteBudget = 42 * 1024 * 1024;

    expect(history.byteBudget, 42 * 1024 * 1024);
    expect(
      VolatileScratchFiles.ceilingBytes,
      42 * 1024 * 1024,
      reason: 'parking is this budget spent somewhere else, so the room may '
          'weigh what the stack was allowed to weigh',
    );
  });
}
