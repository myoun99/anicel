import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/services/playback/frame_demand.dart';
import 'package:anicel/src/ui/playback/playback_pictures.dart';
import 'package:anicel/src/ui/playback/playback_prerender_scheduler.dart';
import 'package:anicel/src/ui/quiet_turns.dart';

/// Pictures that land only when the test lands them, each making
/// remembering what it was told of being due.
final class _HeldPictures implements PlaybackPictures {
  final Set<int> made = {};
  final Map<int, Completer<bool>> _landings = {};
  final Map<int, bool Function()> dueOf = {};

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
  bool failed(DemandedPicture picture) => false;

  @override
  void noteFailure(DemandedPicture picture) {}

  @override
  int bytesToMake(DemandedPicture picture) => 0;

  @override
  Future<void> readIn(DemandedPicture picture) async {}

  @override
  int weighNew(DemandedPicture picture, Set<Object> seen) => 0;

  @override
  Future<bool> make(
    DemandedPicture picture, {
    required bool Function() shouldAbort,
    bool Function() due = notDue,
  }) {
    dueOf[picture.frameIndex] = due;
    return (_landings[picture.frameIndex] = Completer<bool>()).future;
  }
}

/// 🚨What a run shows next is not background work: while the frame under
/// the playhead or the one after it has no picture, what the walk makes
/// does not wait for a quiet between the run's held frames — the next held
/// frame shows it, and the quiet that frame leaves comes after it.
void main() {
  test('🚨the walk\'s making is due while the run\'s next frames lack a '
      'picture, and takes the quiets once it is ahead of them', () async {
    final cut = Cut(
      id: const CutId('c'),
      name: 'c',
      duration: 8,
      canvasSize: const CanvasSize(width: 4, height: 4),
      layers: const [],
    );
    final pictures = _HeldPictures();
    var playhead = 0;
    final scheduler = PlaybackPrerenderScheduler(
      pictures: pictures,
      resolveCut: (_) => cut,
    );
    addTearDown(scheduler.dispose);

    scheduler.follow(
      PlayingDemand(
        totalFrames: 8,
        loops: () => true,
        playhead: () => playhead,
        picturesOf: (frame) => [(cut: cut, frameIndex: frame, paintPaper: true)],
        playlistFrameOf: (_, frame) => frame,
      ),
    );
    await pumpEventQueue();
    expect(pictures.dueOf.keys, containsAll([0, 1, 2]), reason: '⛔premise');
    expect(
      pictures.dueOf[0]!(),
      isTrue,
      reason: 'the frame under the playhead has none',
    );

    pictures.land(0);
    await pumpEventQueue();
    expect(pictures.dueOf[2]!(), isTrue, reason: 'the frame after it has none');

    pictures.land(1);
    await pumpEventQueue();
    expect(
      pictures.dueOf[2]!(),
      isFalse,
      reason: 'the run\'s next two frames are there: it waits for a quiet',
    );

    playhead = 1;
    expect(pictures.dueOf[2]!(), isTrue, reason: 'the run shows it next');
  });
}
