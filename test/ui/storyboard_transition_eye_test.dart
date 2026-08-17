import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/camera_instruction.dart'
    show InstructionEvent;
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_section_defaults.dart'
    show createTrackTransitionLayer;
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

/// 🚨C4 (2026-08-17): the transition row's EYE is TRANSITION APPLY/BYPASS —
/// eye ON, the spans fade the composite; eye OFF, playback and export see
/// no spans at all ([EditorSessionManager.transitionSpansOfTrack] is the
/// one reading every consumer funnels through). The button exists on BOTH
/// device-visible hosts — the storyboard rail label and the cut timeline's
/// clone row — and either drives the same track-owned flag.
const _trackId = TrackId('teye-track');

Cut _cut(String id, int duration) => Cut(
  id: CutId(id),
  name: id,
  duration: duration,
  canvasSize: const CanvasSize(width: 640, height: 360),
  layers: [
    Layer(
      id: LayerId('$id-cel'),
      name: 'A',
      frames: const [],
      timeline: const {},
    ),
  ],
);

/// An O.L span straddling the cut-1 → cut-2 boundary (global 8..13 over a
/// 10-frame first cut): while it fires, BOTH cuts contribute to the frame.
Project _project() => Project(
  id: const ProjectId('teye-project'),
  name: 'Transition Eye',
  createdAt: DateTime.utc(2026, 8, 17),
  tracks: [
    Track(
      id: _trackId,
      name: 'Video',
      cuts: [_cut('cut-1', 10), _cut('cut-2', 6)],
      transitionLayer: createTrackTransitionLayer(_trackId).copyWith(
        instructions: {
          8: const InstructionEvent(instructionId: 'ol', length: 5),
        },
      ),
    ),
  ],
);

Future<EditorSessionManager> _open(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: _project())),
  );
  await tester.pumpAndSettle();
  return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
}

void main() {
  testWidgets('eye ON = the spans APPLY in the playback composite; a REAL '
      'tap on the STORYBOARD eye bypasses them — and a REAL tap on the '
      'TIMELINE clone row\'s eye brings them back', (tester) async {
    final session = await _open(tester);
    final transitionId = session.activeTrack.transitionLayer.id;

    // ON: inside the O.L both cuts contribute (the fade is applying).
    expect(session.transitionSpansOfTrack(_trackId), hasLength(1));
    expect(session.trackStackContributionsAt(10), hasLength(2));

    // The TIMELINE host (the default tab) carries the eye on the clone row
    // — the cut timeline is a device-visible host too.
    final timelineEye = find.byKey(
      ValueKey<String>('timeline-layer-visibility-$transitionId'),
    );
    expect(
      timelineEye,
      findsOneWidget,
      reason: 'the cut timeline\'s transition row wears the eye',
    );

    // OFF, via the STORYBOARD's eye.
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
    final storyboardEye = find.byKey(
      ValueKey<String>('storyboard-layer-visibility-$transitionId'),
    );
    expect(storyboardEye, findsOneWidget);
    await tester.tap(storyboardEye);
    await tester.pumpAndSettle();

    expect(
      session.transitionSpansOfTrack(_trackId),
      isEmpty,
      reason: 'eye OFF: playback and export see no spans',
    );
    expect(
      session.trackStackContributionsAt(10),
      hasLength(1),
      reason: 'the O.L stopped fading — one cut owns the frame again',
    );
    expect(
      session.activeTrack.transitionLayer.instructions,
      isNotEmpty,
      reason: 'the eye hides the contribution, never the data',
    );

    // Back ON, via the TIMELINE clone row's eye — same flag, either door.
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-timeline-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey<String>('timeline-layer-visibility-$transitionId')),
    );
    await tester.pumpAndSettle();

    expect(session.transitionSpansOfTrack(_trackId), hasLength(1));
    expect(session.trackStackContributionsAt(10), hasLength(2));
  });
}
