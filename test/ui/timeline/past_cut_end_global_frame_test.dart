import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🚨★★★ T12 — 「컷길이 넘어서도 **공간은 항상 존재하고 항상 보인다고.**
/// 스토리보드에서만 그걸 컷길이로 클램핑해서 보여줄 뿐인거고.」
///
/// `editingGlobalFrame` used to fold an over-end position onto the cut's
/// last frame, so standing on frame 31 of a 24-frame cut answered 23. ⛔The
/// fold is gone. Clamping is a DISPLAY decision and it stayed where the
/// display is — `storyboard_playhead_mapping` still clamps, because that
/// surface really does draw the cut's territory.
///
/// ⛔The banned word: the old code called those frames a RUNWAY. Naming them
/// makes them a different KIND of place and the special rules follow the
/// word. They are frames.
void main() {
  test('standing past the end line reports where you are standing', () {
    final session = _session(duration: 24);
    addTearDown(session.dispose);

    session.selectFrameIndex(31);

    expect(
      session.editingGlobalFrame,
      31,
      reason: 'the fold used to answer 23 — the cut duration minus one',
    );
  });

  /// 🚨This is the half the unclamp nearly broke, and the reason the sweep
  /// the old doc comment demanded was not optional.
  ///
  /// `editingPlayheadInGap` also asked `axis.isGap(editingGlobalFrame)`. That
  /// term was DEAD under clamping — a clamped frame is inside its own cut by
  /// construction — so unclamping woke it up, and it immediately answered
  /// TRUE past the end line. The canvas dropped its paper and its layers,
  /// which is the exact negation of 「컷길이 넘어서도 공간은 항상 존재하고
  /// 항상 보인다」. A gap PARKING is the only way to be in a gap.
  test('past the end line is not a gap — a cut is active, so you are in it', () {
    final session = _session(duration: 24);
    addTearDown(session.dispose);

    session.selectFrameIndex(31);

    expect(session.activeCutId, isNotNull);
    expect(session.editingPlayheadInGap, isFalse);
  });

  test('the second cut is still reached by ITS own start, not by the '
      'first cut spilling into it', () {
    // Two 10-frame cuts: cut-b owns globals 10..19. Standing at local 15 of
    // cut-a is global 15, which is a frame that exists — the point of the
    // law — and the axis does not pretend the playhead moved to cut-b.
    final session = _session(duration: 10, second: 10);
    addTearDown(session.dispose);

    session.selectFrameIndex(15);

    expect(session.editingGlobalFrame, 15);
    expect(
      session.activeCutId,
      const CutId('cut-a'),
      reason: 'a global frame past your cut does not re-home the playhead',
    );
  });

  test('inside the cut, nothing changed', () {
    final session = _session(duration: 24);
    addTearDown(session.dispose);

    session.selectFrameIndex(7);

    expect(session.editingGlobalFrame, 7);
  });
}

EditorSessionManager _session({required int duration, int? second}) {
  return EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('p'),
      name: 'P',
      createdAt: DateTime.utc(2026, 8, 14),
      tracks: [
        Track(
          id: const TrackId('default-track'),
          name: 'Track',
          cuts: [
            Cut(
              id: const CutId('cut-a'),
              name: 'A',
              duration: duration,
              canvasSize: const CanvasSize(width: 64, height: 64),
              layers: const [],
            ),
            if (second != null)
              Cut(
                id: const CutId('cut-b'),
                name: 'B',
                duration: second,
                canvasSize: const CanvasSize(width: 64, height: 64),
                layers: const [],
              ),
          ],
        ),
      ],
    ),
  );
}
