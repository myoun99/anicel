import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_section_defaults.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_frame_range.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_command_actions.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// #17 잔여 — THE CREATE BUTTON READS ONE SENTENCE (T25).
///
/// The toolbar kept its own kind switch, and it disagreed with the
/// dispatch in both directions: `_ => true` lit the button on rows whose
/// dispatch is a documented no-op (folder, adjustment, the in-cut
/// transition), and it knew nothing of the selection rungs — the S-row
/// range #16 taught the verb left the button dark-or-lucky. Enabled and
/// dispatch must be the same sentence, or they lie in one direction or
/// the other (#18's law, one pill over).
void main() {
  const trackId = TrackId('track');
  final seLayerId = seLayerIdForTrack(trackId, 1);

  EditorSessionManager session({Layer? seedSe}) => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('project'),
      name: 'P',
      createdAt: DateTime.utc(2026),
      tracks: [
        Track(
          id: trackId,
          name: 'T',
          cuts: [
            Cut(
              id: const CutId('cut'),
              name: '1',
              duration: 4,
              canvasSize: const CanvasSize(width: 8, height: 8),
              layers: [
                // The ACTIVE row is a folder: its dispatch arm is a
                // documented no-op, so the current-frame rung must say
                // false — which is what lets the selection rungs above
                // it show their own answer.
                Layer(
                  id: const LayerId('folder'),
                  name: 'F',
                  frames: const [],
                  timeline: const {},
                  kind: LayerKind.folder,
                ),
              ],
            ),
          ],
          seLayers: [seedSe ?? createTrackSeLayer(trackId: trackId, slot: 1)],
        ),
      ],
    ),
  );

  TrackFrameRangeSelection range() => TrackFrameRangeSelection(
    trackId: trackId,
    anchorRow: LayerRowAddress(seLayerId),
    startFrame: 10,
    endFrameExclusive: 14,
  );

  test('a no-op row does not light the button — and the press really is '
      'a no-op (the sentence and the dispatch agree)', () {
    final s = session();
    addTearDown(s.dispose);

    expect(
      s.canCreateInstance,
      isFalse,
      reason: 'the old toolbar switch said true here (`_ => true`) while '
          'the dispatch no-opped — lit and useless',
    );
    final before = s.repository.requireProject();
    createActiveInstance(s);
    expect(
      identical(s.repository.requireProject(), before),
      isTrue,
      reason: 'nothing was authored — false was the truth',
    );
  });

  test('the S-row range lights the button through the SAME rung the verb '
      'runs, and the press creates', () {
    final s = session();
    addTearDown(s.dispose);
    s.trackFrameRangeSelection.value = range();

    expect(s.canCreateInstance, isTrue);
    createActiveInstance(s);
    expect(
      s.repository
          .requireProject()
          .tracks
          .single
          .seLayers
          .single
          .timeline[10],
      isNotNull,
      reason: 'true was the truth — the pair holds in both directions',
    );
  });

  test('a fully covered range declines: the rung reads the PLAN, not the '
      'mere presence of a selection', () {
    final seeded = createTrackSeLayer(trackId: trackId, slot: 1).copyWith(
      frames: [
        Frame(id: const FrameId('kept'), duration: 1, strokes: const []),
      ],
      timeline: {
        10: const TimelineExposure.drawing(FrameId('kept'), length: 4),
      },
    );
    final s = session(seedSe: seeded);
    addTearDown(s.dispose);
    s.trackFrameRangeSelection.value = range();

    expect(
      s.canCreateInstance,
      isFalse,
      reason: 'nothing to author in [10,14) — a lit button here would be '
          'the same lie with a selection on',
    );
  });
}
