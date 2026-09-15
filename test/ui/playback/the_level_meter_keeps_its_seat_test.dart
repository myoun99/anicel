import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';
import 'package:anicel/src/ui/playback/playback_transport_controls.dart';

/// F-111 — the level meter keeps its seat.
///
/// 유저 2026-09-12: 「그리고 재생시 음량있는부분 마이크 오른쪽부분 공간이
/// 넓어지는데 역시 이런 공간 바뀌는거 해결하고싶으니」.
///
/// The meter was MOUNTED with playback, so pressing play opened a gap to the
/// right of the mic — 없다가 생기는 UI, the same shape the clip light beside
/// it was fixed for (`the_clip_light_keeps_its_seat_test`). Measured the way
/// that test measures: the row's own geometry before and after, laid out
/// top-left so the row reports the width it wants.
void main() {
  Project project() => Project(
    id: const ProjectId('project'),
    name: 'Project',
    frameRate: const ProjectFrameRate.integer(10),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Track',
        cuts: [
          Cut(
            id: const CutId('cut'),
            name: 'Cut',
            layers: const [],
            duration: 40,
            canvasSize: const CanvasSize(width: 8, height: 8),
          ),
        ],
      ),
    ],
    createdAt: DateTime.utc(2026),
  );

  CanvasPlaybackController newController() {
    final controller = CanvasPlaybackController(
      resolveProject: project,
      resolveActiveCutId: () => const CutId('cut'),
      resolveActiveTrackId: () => const TrackId('track'),
      resolveFrameRate: () => const ProjectFrameRate.integer(10),
    );
    addTearDown(controller.dispose);
    return controller;
  }

  Future<void> pumpRows(
    WidgetTester tester,
    CanvasPlaybackController controller,
  ) async {
    Widget row(PlaybackScope scope) => Align(
      alignment: Alignment.topLeft,
      child: PlaybackTransportControls(
        key: ValueKey<String>('row-${scope.name}'),
        controller: controller,
        scope: scope,
        resolveMeterPeaks: () => (left: 0.5, right: 0.5),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              row(PlaybackScope.activeCut),
              row(PlaybackScope.allCuts),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder rowOf(PlaybackScope scope) =>
      find.byKey(ValueKey<String>('row-${scope.name}'));

  Finder meterIn(PlaybackScope scope) => find.descendant(
    of: rowOf(scope),
    matching: find.byKey(const ValueKey<String>('audio-level-meter')),
  );

  testWidgets('pressing play does not widen the transport row', (
    tester,
  ) async {
    final controller = newController();
    await pumpRows(tester, controller);
    final idleWidth = tester.getSize(rowOf(PlaybackScope.activeCut)).width;
    expect(idleWidth, greaterThan(0), reason: 'fixture: the row laid out');

    controller.attachTicker(tester);
    controller.play(scope: PlaybackScope.activeCut);
    await tester.pump();

    expect(
      tester.getSize(rowOf(PlaybackScope.activeCut)).width,
      idleWidth,
      reason: 'the meter keeps its seat whether or not this row plays — a '
          'row that grows on play is the reported 마이크 오른쪽 공간',
    );

    controller.stop();
    controller.detachTicker();
  });

  testWidgets('the seat is the same box, idle and playing', (tester) async {
    final controller = newController();
    await pumpRows(tester, controller);
    expect(
      meterIn(PlaybackScope.activeCut),
      findsOneWidget,
      reason: 'the seat is there before anything plays',
    );
    final idleSeat = tester.getRect(meterIn(PlaybackScope.activeCut));

    controller.attachTicker(tester);
    controller.play(scope: PlaybackScope.activeCut);
    await tester.pump();

    expect(tester.getRect(meterIn(PlaybackScope.activeCut)), idleSeat);

    controller.stop();
    controller.detachTicker();
  });

  testWidgets('a row whose scope is not playing keeps the seat and stays '
      'silent', (tester) async {
    final controller = newController();
    await pumpRows(tester, controller);
    controller.attachTicker(tester);
    controller.play(scope: PlaybackScope.activeCut);
    await tester.pump();

    expect(
      meterIn(PlaybackScope.allCuts),
      findsOneWidget,
      reason: 'the other scope keeps its seat too',
    );
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: meterIn(PlaybackScope.allCuts),
        matching: find.byType(CustomPaint),
      ),
    );
    controller.stop();
    controller.detachTicker();

    // ⚠️`toImage` needs the REAL event loop — inside testWidgets the fake
    // clock never delivers it (the meter's own test says the same).
    final pixels = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      paint.painter!.paint(Canvas(recorder), const Size(6, 24));
      final picture = recorder.endRecording();
      final image = await picture.toImage(6, 24);
      final data = await image.toByteData();
      image.dispose();
      picture.dispose();
      return data!.buffer.asUint32List();
    });
    expect(
      pixels!.every((pixel) => pixel == 0),
      isTrue,
      reason: 'another scope\'s playback must not light this row\'s bars',
    );
  });
}
