import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/cut_verbs.dart';

/// A CUT STEPS ALONG ITS TRACK — and the two directions are ONE law with
/// the sign flipped.
///
/// ⛔The pair used to be written out twice, guard and command and refresh
/// each, and the guards had already drifted: `cutIndex > 0` on the left,
/// `cutIndex < cutCount - 1` on the right — the same sentence said two
/// ways, only one of which mentioned the count it depends on. Nothing in
/// the suite named [CutVerbs.moveActiveCutLeft] or its gate, so the whole
/// verb (and the sign that is all there is to it) was unpinned.
///
/// 🚨Held through [CutVerbs] by name: `tool/mutation_run.dart` picks the
/// tests that witness a mutation by asking which tests IMPORT the file,
/// and round 8's collaborators were reached only through the session.
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  Cut cut(String id) => Cut(
    id: CutId(id),
    name: id,
    duration: 4,
    canvasSize: canvasSize,
    layers: [
      Layer(
        id: LayerId('$id-layer'),
        name: 'A',
        frames: [
          Frame(id: FrameId('$id-frame'), duration: 1, strokes: const []),
        ],
        timeline: {
          0: TimelineExposure.drawing(FrameId('$id-frame'), length: 2),
        },
      ),
    ],
  );

  /// Three cuts in a row on one track; the session opens standing on the
  /// first.
  EditorSessionManager session() {
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('project'),
        name: 'P',
        createdAt: DateTime.utc(2026),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'T',
            cuts: [cut('a'), cut('b'), cut('c')],
          ),
        ],
      ),
    );
    addTearDown(s.dispose);
    return s;
  }

  List<String> order(EditorSessionManager s) => [
    for (final c in s.repository.requireProject().tracks.single.cuts) c.name,
  ];

  CutVerbs verbsOf(EditorSessionManager s) => s.cutVerbs;

  test('the first cut has nowhere to go left and somewhere to go right', () {
    final s = session();
    expect(
      s.activeCutOrNull!.name,
      'a',
      reason: 'fixture: standing on the first cut',
    );
    expect(verbsOf(s).canMoveActiveCutLeft, isFalse);
    expect(verbsOf(s).canMoveActiveCutRight, isTrue);
  });

  test('a step RIGHT swaps the cut with its follower, and the gates follow '
      'the cut to its new index', () {
    final s = session();

    verbsOf(s).moveActiveCutRight();
    expect(order(s), ['b', 'a', 'c'], reason: 'one step, not to the end');
    expect(
      verbsOf(s).canMoveActiveCutLeft,
      isTrue,
      reason:
          'it is index 1 now — the gate reads the CURRENT position, not the '
          'opening one',
    );

    verbsOf(s).moveActiveCutRight();
    expect(order(s), ['b', 'c', 'a']);
    expect(
      verbsOf(s).canMoveActiveCutRight,
      isFalse,
      reason:
          'last of three — the right gate is the one that has to '
          'mention the count',
    );
  });

  test('a step LEFT is the same move with the sign flipped', () {
    final s = session();

    verbsOf(s).moveActiveCutRight();
    verbsOf(s).moveActiveCutRight();
    expect(order(s), ['b', 'c', 'a']);

    verbsOf(s).moveActiveCutLeft();
    expect(order(s), ['b', 'a', 'c'], reason: 'the same single step back');
    verbsOf(s).moveActiveCutLeft();
    expect(order(s), ['a', 'b', 'c']);
  });

  test('a refused step is a no-op, not a wrap', () {
    final s = session();

    verbsOf(s).moveActiveCutLeft();
    expect(
      order(s),
      ['a', 'b', 'c'],
      reason:
          'the first cut stays first — a refused move must not fall '
          'through to the other end',
    );
  });

  test('the cut the user is standing on is the one that moved', () {
    final s = session();
    final moving = s.activeCutOrNull!.id;

    verbsOf(s).moveActiveCutRight();

    expect(
      s.repository.requireProject().tracks.single.cuts[1].id,
      moving,
      reason:
          'the verb reorders the ACTIVE cut; a mover picked off the '
          'track instead would be a different cut every time',
    );
  });
}
