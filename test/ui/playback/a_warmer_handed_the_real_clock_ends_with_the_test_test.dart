import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/draw_on_current_frame.dart';

/// A session widget test that lends the real clock — to read a screen's
/// pixels, to wait out a file — ends with playback's warmer between two
/// pictures as often as not: the engine made a picture in the clock it lent,
/// and the walk goes on when the fake clock's microtasks next run — in the
/// pump after the body, which runs no time. The yield it takes there is
/// the fake clock's, and the binding found it pending once the tree was
/// gone: 「A Timer is still pending even after the widget tree was
/// disposed」, the busier the machine the likelier (card
/// a-test-lending-the-real-clock-leaves-the-warmer-running).
///
/// So the walk steps aside by a microtask under widget tests
/// (`playback_rig.dart`), and the gate a hold shuts waits for the hold to
/// close, not on a heartbeat: no test stops the warmer by hand — one that
/// lends the clock last, one whose last word starts a walk over frames
/// with nothing to make, one that holds the warmer to its end.
void main() {
  /// A session whose warmer has asked the engine for a cut's pictures, and
  /// the real clock lent long enough for the engine to make one.
  Future<EditorSessionManager> aPictureMadeInTheLentClock(
    WidgetTester tester,
  ) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    for (var frame = 0; frame < 4; frame += 1) {
      s.selectFrameIndex(frame);
      drawOnCurrentFrame(s);
    }
    s.selectFrameIndex(0);
    s.warmActiveCut();
    for (var step = 0; step < 4; step += 1) {
      await tester.pump();
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    return s;
  }

  testWidgets('⛔premise: the engine makes a picture in the lent clock, and '
      'the walk lands it when the fake clock next runs', (tester) async {
    final before = <int>[];
    final s = await aPictureMadeInTheLentClock(tester);
    final warmer = s.playbackRig.prerenderScheduler;
    void heard() => before.add(0);
    warmer.landings.addListener(heard);
    addTearDown(() => warmer.landings.removeListener(heard));

    await tester.pump();

    expect(before, isNotEmpty);
    warmer.cancel();
  });

  testWidgets('🚨a test whose last word lends the real clock ends with no '
      'timer of the warmer\'s pending', (tester) async {
    await aPictureMadeInTheLentClock(tester);
    // ⛔No pump and no stop: the body ends on the lent clock, as the tests
    // that read a screen last do — the binding's own check is the pin.
  });

  testWidgets('🚨a walk that passes over more frames than one stride with '
      'nothing to make, started by a test\'s last word, ends with the test', (
    tester,
  ) async {
    // Eighty frames and no row: every frame is there already, so the walk
    // steps aside after a stride of them with no picture made and no clock
    // lent — in the pump after the body.
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'Project',
        frameRate: const ProjectFrameRate.integer(24),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Track',
            cuts: [
              Cut(
                id: const CutId('cut'),
                name: 'Cut',
                layers: const [],
                duration: 80,
                canvasSize: const CanvasSize(width: 8, height: 8),
              ),
            ],
          ),
        ],
        createdAt: DateTime.utc(2026),
      ),
    );
    addTearDown(s.dispose);
    s.warmActiveCut();
    expect(
      s.playbackRig.demand!.length,
      80,
      reason: '⛔premise: more frames than the walk passes over at a stride',
    );
  });

  testWidgets('🚨a warmer held to the test\'s end — so what is made is the '
      'test\'s own asking — ends with the test', (tester) async {
    final s = await aPictureMadeInTheLentClock(tester);
    final warmer = s.playbackRig.prerenderScheduler..beginInputHold();
    s.selectFrameIndex(2);
    warmer.notifyEditActivity();
    for (var step = 0; step < 4; step += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      warmer.isResting,
      isFalse,
      reason: '⛔premise: the walk stands at the gate, the hold open',
    );
  });

  // A step whose landing a test cannot end on at will — a picture asked
  // ahead coming in, a making given up — steps aside as every other does:
  // through the one door the rig sets, or it takes the zero timer back.
  test('🚨every step of the walk steps aside through the one door the rig '
      'sets', () {
    final source = File(
      'lib/src/ui/playback/playback_prerender_scheduler.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(
      RegExp(r'_wait\(Duration\.zero\)').allMatches(source).length,
      1,
      reason: 'no step takes a zero timer of its own',
    );
    expect(
      source,
      contains('yieldsToTheEventLoop\n      ? _wait(Duration.zero)'),
      reason: 'the one there is is the door\'s',
    );
  });
}
