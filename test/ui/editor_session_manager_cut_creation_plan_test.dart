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
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_frame_range.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// #18 — CUT CREATION ASKS WHAT IS SELECTED, LIKE EVERY OTHER VERB.
///
/// 유저: 「인덱스를 갭에 둔 상태로 컷생성도안되고 선택범위하고 컷생성도안됨.
/// (…) 갭에서 컷생성누르면 스토리보드엔 컷 안생기는데 버튼쪽(…)은 활성화됨.」
///
/// The old `createCut()` asked nothing: a gap press appended at the
/// track's end — the cut appeared SOMEWHERE ELSE, and the button never
/// dimmed because its tear-off could not go null. One expression
/// ([EditorSessionManager.cutCreationPlan]) now answers the button and
/// the verb (T25: 버튼 근거와 디스패치 근거는 같은 문장 하나).
void main() {
  const canvasSize = CanvasSize(width: 8, height: 8);

  Cut cut(String id, {int leadingGap = 0, int duration = 4}) => Cut(
    id: CutId(id),
    name: id,
    duration: duration,
    leadingGapFrames: leadingGap,
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

  // Axis: cut-a [0,4) · gap [4, 4+gap) · cut-b.
  EditorSessionManager session({int gap = 3}) => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('project'),
      name: 'P',
      createdAt: DateTime.utc(2026),
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'T',
          cuts: [cut('a'), cut('b', leadingGap: gap)],
        ),
      ],
    ),
  );

  List<Cut> cutsOf(EditorSessionManager s) =>
      s.repository.requireProject().tracks.single.cuts;

  test('a gap parking creates the cut RIGHT THERE, and a roomy gap means '
      'nothing behind it moves at all', () {
    // Gap 30: roomier than the new cut's whole footprint, so cut-b must
    // hold its ground — and the follower's remaining gap discriminates
    // the footprint arithmetic (leadingGap + duration, not duration
    // alone: the walk-in frame is spent gap too).
    final s = session(gap: 30);
    addTearDown(s.dispose);
    final bStartBefore = s.trackFrameAxis().entryFor(const CutId('b'))!
        .startFrame;

    s.selectGlobalFrame(5); // the gap between a and b
    expect(s.gapParkedGlobalFrame, 5, reason: 'fixture: really parked');
    expect(s.canCreateCut, isTrue);

    s.createCut();

    final cuts = cutsOf(s);
    expect(cuts, hasLength(3));
    expect(
      cuts[1].leadingGapFrames,
      1,
      reason: 'the walk-in distance from the gap start (5 − 4) is the new '
          'cut\'s own leading gap — it lands AT the parked frame, not at '
          'the track\'s end',
    );
    expect(
      s.trackFrameAxis().entryFor(cuts[1].id)!.startFrame,
      5,
      reason: 'the cut appears where the playhead stood — the whole '
          'complaint was that it appeared somewhere else',
    );
    expect(
      cuts[2].leadingGapFrames,
      30 - 1 - cuts[1].duration,
      reason: 'the follower\'s gap absorbs the WHOLE footprint — the '
          'walk-in frame plus the new duration (#19\'s arithmetic)',
    );
    expect(
      s.trackFrameAxis().entryFor(const CutId('b'))!.startFrame,
      bStartBefore,
      reason: 'room to spare means nothing behind the gap moves',
    );

    s.undo();
    final restored = cutsOf(s);
    expect(restored, hasLength(2));
    expect(
      restored[1].leadingGapFrames,
      30,
      reason: 'undo restores the RECORDED gap',
    );
  });

  test('an empty-space range creates a cut of exactly that range — and '
      'the cuts behind it do not move at all', () {
    final s = session();
    addTearDown(s.dispose);

    s.trackFrameRangeSelection.value = const TrackFrameRangeSelection(
      trackId: TrackId('track'),
      anchorRow: TrackRowAddress(TrackId('track')),
      startFrame: 4,
      endFrameExclusive: 7,
    );
    expect(s.canCreateCut, isTrue);

    s.createCut();

    final cuts = cutsOf(s);
    expect(cuts, hasLength(3));
    expect(cuts[1].duration, 3, reason: 'the range names the length');
    expect(cuts[1].leadingGapFrames, 0, reason: 'the range starts at the '
        'gap\'s own start');
    expect(
      s.trackFrameAxis().entryFor(cuts[2].id)!.startFrame,
      7,
      reason: 'the new cut fits the gap exactly, so nothing behind it '
          'moves — the same law #19 settled for the push',
    );
  });

  test('a range over existing cuts is nowhere to create — the button and '
      'the verb read the same null', () {
    final s = session();
    addTearDown(s.dispose);

    s.trackFrameRangeSelection.value = const TrackFrameRangeSelection(
      trackId: TrackId('track'),
      anchorRow: TrackRowAddress(TrackId('track')),
      startFrame: 2,
      endFrameExclusive: 9,
    );

    expect(s.canCreateCut, isFalse);
    s.createCut();
    expect(cutsOf(s), hasLength(2), reason: 'the verb is guarded by the '
        'same sentence that dims the button');
  });

  test('the active-cut posture is unchanged: the new cut lands to the '
      'right of the active one', () {
    final s = session();
    addTearDown(s.dispose);

    expect(s.activeCutOrNull!.id, const CutId('a'));
    s.createCut();

    final cuts = cutsOf(s);
    expect(cuts, hasLength(3));
    expect(cuts[1].id, isNot(const CutId('b')));
    expect(cuts[2].id, const CutId('b'));
  });
}
