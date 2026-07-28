import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/services/project_repository.dart';
import 'package:anicel/src/ui/home_page.dart';

/// UI-R22 #1: the SE row-change gesture SURVIVES the whole drag — the
/// preview's overlay churn on the source row must never remount the
/// gesture layer (whose dispose would commit the move under the still-
/// pressed pointer, the R12-③ slot-key rule), and wandering over an
/// incompatible section then back onto an SE row resumes the move.
///
/// UI-R23 #10: an incompatible hover no longer snaps back — it HOLDS the
/// last valid landing; either way nothing commits until release.
void main() {
  testWidgets('an SE row move commits ONLY on release — an incompatible '
      'hover holds the last valid landing and the gesture resumes on '
      'return', (tester) async {
    ProjectRepository? repository;
    await tester.pumpWidget(
      MaterialApp(home: HomePage(onRepositoryCreated: (r) => repository = r)),
    );
    await tester.pumpAndSettle();

    final s1 = repository!.requireProject().tracks.single.seLayers.first;
    repository!.replaceLayer(
      layer: s1.copyWith(
        frames: [
          Frame(id: const FrameId('se-cel'), duration: 1, strokes: const []),
        ],
        timeline: const {
          1: TimelineExposure.drawing(FrameId('se-cel'), length: 3),
        },
        audioClips: const [
          AudioClip(filePath: 'a.wav', frameId: FrameId('se-cel')),
        ],
      ),
    );
    await tester.pumpAndSettle();

    bool s2HasBlock() => repository!
        .requireProject()
        .tracks
        .single
        .seLayers
        .last
        .timeline
        .isNotEmpty;

    final gestureLayer = find.byKey(
      ValueKey<String>('timeline-range-gesture-${s1.id}'),
    );
    final origin = tester.getTopLeft(gestureLayer);

    // SELECT the block (drag on the cells), release.
    var g = await tester.startGesture(
      origin + const Offset(24 + 24, 14),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(48, 0));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();

    // MOVE: press inside the selection; wander DOWN onto the drawing row
    // (incompatible — S2 sits ABOVE S1 in the display), then back up
    // onto S2, all in one drag.
    g = await tester.startGesture(
      origin + const Offset(24 + 24, 14),
      kind: PointerDeviceKind.mouse,
    );
    await g.moveBy(const Offset(0, 28));
    await tester.pump();
    expect(
      s2HasBlock(),
      isFalse,
      reason: 'incompatible hover must not commit',
    );

    await g.moveBy(const Offset(0, -56));
    await tester.pump();
    await tester.pump();
    expect(
      s2HasBlock(),
      isFalse,
      reason: 'the planned landing must NOT commit while still pressed '
          '(the gesture layer must survive the preview rebuild)',
    );

    await g.up();
    await tester.pumpAndSettle();
    expect(s2HasBlock(), isTrue, reason: 'the release commits the move');
    expect(
      repository!
          .requireProject()
          .tracks
          .single
          .seLayers
          .first
          .timeline
          .isEmpty,
      isTrue,
    );
  });
}
