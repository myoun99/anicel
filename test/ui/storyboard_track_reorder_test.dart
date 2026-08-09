import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timeline/layer_row_drag.dart'
    show TrackRowSubject;

/// R5 #9 — the storyboard's V row re-orders the project's TRACKS.
///
/// The user's decision (2026-08-09): the track list IS the composite order,
/// so dragging a V row up moves that track's picture up the stack that
/// `CanvasTrackStackView` paints. That makes this a picture change, and it
/// belongs on the undo stack like one.
void main() {
  Track track(String id, String name) => Track(
    id: TrackId(id),
    name: name,
    cuts: [
      Cut(
        id: CutId('$id-cut'),
        name: '$name cut',
        duration: 12,
        canvasSize: const CanvasSize(width: 640, height: 360),
        layers: [
          Layer(
            id: LayerId('$id-cel'),
            name: 'A',
            frames: const [],
            timeline: const {},
          ),
        ],
      ),
    ],
  );

  EditorSessionManager threeTracks() => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('reorder-project'),
      name: 'Reorder',
      createdAt: DateTime.utc(2026, 8, 9),
      tracks: [track('t1', 'One'), track('t2', 'Two'), track('t3', 'Three')],
    ),
  );

  List<String> namesOf(EditorSessionManager session) => [
    for (final t in session.repository.requireProject().tracks) t.name,
  ];

  group('the session verb', () {
    test('a drag DOWN lands the track after the one it passed — the slot is '
        'a gap, the model wants an index, and lifting yourself out costs '
        'one position', () {
      final session = threeTracks();
      addTearDown(session.dispose);

      session.beginLayerRowDrag(const TrackRowSubject(TrackId('t1')));
      // Caret past 'Two': slot 2 of the row list.
      session.updateTrackRowDrag(2);
      session.endLayerRowDrag();

      expect(namesOf(session), ['Two', 'One', 'Three']);
    });

    test('a drag UP needs no adjustment — nothing below the caret moved',
        () {
      final session = threeTracks();
      addTearDown(session.dispose);

      session.beginLayerRowDrag(const TrackRowSubject(TrackId('t3')));
      session.updateTrackRowDrag(0);
      session.endLayerRowDrag();

      expect(namesOf(session), ['Three', 'One', 'Two']);
    });

    test('landing where you already are commits nothing — a no-op must not '
        'reach the undo stack', () {
      final session = threeTracks();
      addTearDown(session.dispose);
      final before = session.canUndo;

      session.beginLayerRowDrag(const TrackRowSubject(TrackId('t2')));
      session.updateTrackRowDrag(1); // the gap above itself
      session.endLayerRowDrag();

      expect(namesOf(session), ['One', 'Two', 'Three']);
      expect(session.canUndo, before);
    });

    test('the move undoes as ONE step', () {
      final session = threeTracks();
      addTearDown(session.dispose);

      session.beginLayerRowDrag(const TrackRowSubject(TrackId('t1')));
      session.updateTrackRowDrag(3);
      session.endLayerRowDrag();
      expect(namesOf(session), ['Two', 'Three', 'One']);

      session.undo();
      expect(namesOf(session), ['One', 'Two', 'Three']);
    });

    test('a LAYER drag is untouched by the track arm', () {
      final session = threeTracks();
      addTearDown(session.dispose);
      session.beginLayerRowDrag(const TrackRowSubject(TrackId('t1')));
      // A track caret must not be accepted while a layer subject is held.
      session.beginLayerRowDrag(const TrackRowSubject(TrackId('t2')));
      session.updateTrackRowDrag(0);
      session.endLayerRowDrag();
      expect(namesOf(session), ['Two', 'One', 'Three']);
    });
  });

  testWidgets('dragging the V row on the real rail re-orders the tracks',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final session = threeTracks();
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => StoryboardTabHost(
              session: session,
              pixelsPerFrame: 12,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnailFor: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final v1 = find.byKey(
      const ValueKey<String>('storyboard-track-label-row-t1'),
    );
    expect(v1, findsOneWidget);

    // ONE track group, measured off the rail rather than assumed: the gap
    // between two V rows is the whole group between them (S rows and any
    // open lanes), which is exactly the pitch the drag counts in. Asserting
    // against a constant here would pass while the pitch was wrong.
    final v2 = find.byKey(
      const ValueKey<String>('storyboard-track-label-row-t2'),
    );
    final pitch = tester.getTopLeft(v2).dy - tester.getTopLeft(v1).dy;
    expect(pitch, greaterThan(20), reason: 'the drag must clear the slop');
    await tester.drag(v1, Offset(0, pitch));
    await tester.pumpAndSettle();

    expect(namesOf(session), ['Two', 'One', 'Three']);
  });
}
