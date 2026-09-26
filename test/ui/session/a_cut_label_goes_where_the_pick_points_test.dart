import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/services/editing/default_layer_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🗣️유저 2026-09-26: 「색라벨 정하는건 블록마다 다른거니까 컷버튼안에
/// 있다던가. 선택범위 한상태로 조작가능한거 물론이고」 — the cut button's
/// label goes to the cuts a storyboard range covers, or to the active cut
/// when no range is up, through ONE verb (절대명령 2: a selection does not
/// split the law).
void main() {
  const key = LayerMark(process: LayerProcess.key);
  const layout = LayerMark(process: LayerProcess.layout);

  EditorSessionManager session() {
    Cut cut(String id, int sequence) => createDefaultCut(
      cutId: CutId(id),
      name: id,
      layerId: defaultLayerIdForSequence(sequence),
    );
    final s = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('label-project'),
        name: 'Labels',
        createdAt: DateTime.utc(2026, 9, 26),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'V',
            cuts: [cut('cut-1', 1), cut('cut-2', 2), cut('cut-3', 3)],
          ),
        ],
      ),
    );
    addTearDown(s.dispose);
    return s;
  }

  LayerMark markOf(EditorSessionManager s, String id) =>
      s.cutById(CutId(id))!.metadata.mark;

  test('with no range up, the pick labels the ACTIVE cut', () {
    final s = session();
    final active = s.activeCutId!;
    expect(s.cutVerbs.addressedCutIds, [active]);

    s.cutVerbs.setAddressedCutMark(key);
    expect(s.cutById(active)!.metadata.mark, key);
    expect(s.cutVerbs.addressedCutMark, key, reason: 'what the button shows');
  });

  test('with a range up, the pick labels EVERY cut it covers — the active '
      'one left out when the range does not reach it — as one undo step', () {
    final s = session();
    s.cutVerbs.setAddressedCutMark(key);
    final active = s.activeCutId!;
    final axis = s.trackFrameAxis();
    final second = axis.entryFor(const CutId('cut-2'))!;
    final third = axis.entryFor(const CutId('cut-3'))!;
    s.updateStoryboardCutSelectionByFrame(
      anchorGlobalFrame: second.startFrame,
      headGlobalFrame: third.startFrame,
    );
    expect(s.cutVerbs.addressedCutIds, const [
      CutId('cut-2'),
      CutId('cut-3'),
    ]);

    s.cutVerbs.setAddressedCutMark(layout);
    expect(markOf(s, 'cut-2'), layout);
    expect(markOf(s, 'cut-3'), layout);
    expect(
      s.cutById(active)!.metadata.mark,
      key,
      reason: 'the active cut is outside the range',
    );

    s.undo();
    expect(markOf(s, 'cut-2'), LayerMark.none);
    expect(markOf(s, 'cut-3'), LayerMark.none);
  });
}
