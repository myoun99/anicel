import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/services/playback/frame_demand.dart';
import 'package:anicel/src/ui/playback/playback_pictures.dart';
import 'package:anicel/src/ui/playback/playback_prerender_scheduler.dart';
import 'package:anicel/src/ui/quiet_turns.dart';

/// Pictures weighed only when the test weighs them, and landed only when
/// it lands them: each frame's a part of its own.
final class _WeighedPictures implements PlaybackPictures {
  final Set<int> made = {};
  final Map<int, Completer<int>> _weighs = {};
  final Map<int, Completer<bool>> _landings = {};

  /// The frames asked their weight and not told it yet, and those being
  /// made, in the order asked.
  List<int> get weighing => _weighs.keys.toList();
  List<int> get making => _landings.keys.toList();

  void weigh(int frame, int bytes) => _weighs.remove(frame)!.complete(bytes);

  void land(int frame) {
    made.add(frame);
    _landings.remove(frame)!.complete(true);
  }

  @override
  bool has(DemandedPicture picture) => made.contains(picture.frameIndex);

  @override
  Set<Object> partsToMake(DemandedPicture picture) =>
      has(picture) ? const {} : {picture.frameIndex};

  @override
  PictureStanding standingOf(DemandedPicture picture) => (
    state: has(picture) ? PictureState.there : PictureState.toCome,
    cannotRead: false,
  );

  @override
  void noteFailure(DemandedPicture picture) {}

  @override
  Future<int> bytesToMake(DemandedPicture picture) =>
      (_weighs[picture.frameIndex] = Completer<int>()).future;

  @override
  Future<void> readIn(DemandedPicture picture) async {}

  @override
  void rest() {}

  @override
  bool get roomToAskAhead => true;

  @override
  int weighNew(DemandedPicture picture, Set<Object> seen) => 0;

  @override
  Future<bool> make(
    DemandedPicture picture, {
    required bool Function() shouldAbort,
    bool Function() due = notDue,
  }) => (_landings[picture.frameIndex] = Completer<bool>()).future;
}

/// A room that keeps what it was asked, and has room for the steps [has]
/// says.
final class _Room implements PictureRoom {
  final List<({int bytes, int step})> asked = [];
  bool Function(int step) has = (_) => true;

  @override
  int get bytes => 1 << 30;

  @override
  bool makeRoomFor({required int bytes, required int step}) {
    asked.add((bytes: bytes, step: step));
    return has(step);
  }
}

/// 🚨A picture asked for ahead is on its way from the ask, and asks its
/// room once it is weighed (F-610, 2026-11-19): a picture's weight is told
/// by the engine's thread, behind the pictures asked for before it
/// (`PlaybackPictures.bytesToMake`) — a cut's second weighed against its
/// first —, so the walk's ask ahead waits for none of it. ↩️Its room was
/// made as it was asked for, by a weight counted where it was asked: every
/// tile its plan lays on, several times what it comes to weigh.
void main() {
  final cut = Cut(
    id: const CutId('c'),
    name: 'c',
    duration: 8,
    canvasSize: const CanvasSize(width: 4, height: 4),
    layers: const [],
  );

  (_WeighedPictures, _Room) walking() {
    final pictures = _WeighedPictures();
    final room = _Room();
    final scheduler = PlaybackPrerenderScheduler(
      pictures: pictures,
      resolveCut: (_) => cut,
      room: room,
    );
    addTearDown(scheduler.dispose);
    scheduler.follow(
      PlayingDemand(
        totalFrames: 8,
        loops: () => true,
        playhead: () => 0,
        picturesOf: (frame) => [(
          cut: cut,
          frameIndex: frame,
          paintPaper: true,
          ghosts: FrameGhosts.none,
        )],
        playlistFrameOf: (_, frame) => frame,
      ),
    );
    return (pictures, room);
  }

  test('🚨asked for ahead, a picture takes its place before it is weighed '
      '— no more are asked for than may be on their way — and asks its '
      'room once its weight is told: for all that is being made as well',
      () async {
    final (pictures, room) = walking();
    await pumpEventQueue();
    expect(pictures.weighing, [0], reason: 'the walk weighs its own first');
    expect(room.asked, isEmpty);

    pictures.weigh(0, 10);
    await pumpEventQueue();
    expect(room.asked, [(bytes: 10, step: 0)]);
    expect(pictures.making, [0]);
    expect(
      pictures.weighing,
      [1, 2],
      reason: 'the two ahead are on their way: weighed, and no third asked',
    );

    pictures.weigh(1, 3);
    await pumpEventQueue();
    expect(
      room.asked.last,
      (bytes: 13, step: 1),
      reason: 'the walk\'s own is being made still',
    );
    expect(pictures.making, [0, 1]);

    pictures.weigh(2, 4);
    await pumpEventQueue();
    expect(
      room.asked.last,
      (bytes: 17, step: 2),
      reason: 'and the one ahead whose room is made',
    );
    expect(pictures.making, [0, 1, 2]);
    expect(pictures.weighing, isEmpty, reason: 'two ahead: no third');
  });

  test('🚨weighed once the walk\'s own has landed, a picture ahead asks '
      'room for itself alone: what landed is the room\'s to count', () async {
    final (pictures, room) = walking();
    await pumpEventQueue();
    pictures.weigh(0, 10);
    await pumpEventQueue();
    pictures.land(0);
    await pumpEventQueue();
    expect(
      pictures.weighing,
      [1, 2, 3],
      reason: '⛔premise: the walk waits for the first ahead, and asks past it',
    );

    pictures.weigh(1, 3);
    await pumpEventQueue();

    expect(room.asked.last, (bytes: 3, step: 1));
    expect(pictures.making, [1]);
  });

  test('🚨with no room for a picture ahead once it is weighed, it is not '
      'made — nor the one asked for after it in the same ask, which asks '
      'no room', () async {
    final (pictures, room) = walking();
    room.has = (step) => step != 1;
    await pumpEventQueue();
    pictures.weigh(0, 10);
    await pumpEventQueue();
    expect(pictures.weighing, [1, 2], reason: '⛔premise: two ahead');

    pictures.weigh(1, 3);
    await pumpEventQueue();
    pictures.weigh(2, 4);
    await pumpEventQueue();

    expect(room.asked, [(bytes: 10, step: 0), (bytes: 13, step: 1)]);
    expect(pictures.making, [0]);
  });

  test('a picture ahead that will not be weighed is one not asked for: the '
      'walk goes on, and weighs it itself where it gets to it', () async {
    final (pictures, room) = walking();
    await pumpEventQueue();
    pictures.weigh(0, 10);
    await pumpEventQueue();

    pictures._weighs.remove(1)!.completeError(StateError('not weighed'));
    await pumpEventQueue();
    expect(pictures.making, [0], reason: 'not made');
    pictures.weigh(2, 4);
    await pumpEventQueue();
    expect(room.asked.last, (bytes: 14, step: 2), reason: 'the next is');

    pictures.land(0);
    await pumpEventQueue();
    expect(
      pictures.weighing,
      contains(1),
      reason: 'the walk has come to it, and asks its weight itself',
    );
  });
}
