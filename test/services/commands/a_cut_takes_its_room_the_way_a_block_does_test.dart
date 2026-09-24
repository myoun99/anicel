import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// F-97 · F-99 — a cut takes its room the way a frame block does, and a 겸용
/// cut is born the way a new cut is.
///
/// F-97 (유저 2026-09-12): 「링크컷 만들때는 뒤 컷이 떨어져 있어서 공간이
/// 있는데도 뒤 컷들 전부 밀어냄. 근데 새 컷 만들때는 빈공간있으면 뒤 컷
/// 안밀어냄. 새 컷 만드는거랑 똑같이 해서 법 하나로 통일. 근데 이런거 애초에
/// 프레임블록 로직이랑 똑같이 법 통일. 그리고 겸용컷 만든다고 해서 현재
/// 컷이랑 컷길이 똑같이 하지않음. 새 컷만드는거랑 똑같은 컷길이로.
/// 하드코딩하지말고.」
///
/// F-99 (유저 2026-09-12): 「겸용컷 생성시 컷1에 콘티레이어가 있을때 컷2에도
/// 컷레이어 존재는 하는데 프레임 블록이 비어있음. 콘티레이어 생성시 기본적으로
/// 프레임 생성되는데 그 법 그대로 재사용/통일」.
void main() {
  const followerA = CutId('follower-a');
  const followerB = CutId('follower-b');
  const sourceLength = 30;

  /// The default project's cut, [sourceLength] frames long, then cut A
  /// [gapA] frames after it and cut B [gapB] frames after A — standing on
  /// the first.
  EditorSessionManager scene({required int gapA, required int gapB}) {
    final base = createDefaultProject();
    final track = base.tracks.first;
    final source = track.cuts.first.copyWith(duration: sourceLength);
    final session = EditorSessionManager(
      initialProject: base.copyWith(
        tracks: [
          track.copyWith(
            cuts: [
              source,
              createDefaultCut(
                cutId: followerA,
                name: 'A',
                layerId: const LayerId('follower-a-cel'),
              ).copyWith(leadingGapFrames: gapA),
              createDefaultCut(
                cutId: followerB,
                name: 'B',
                layerId: const LayerId('follower-b-cel'),
              ).copyWith(leadingGapFrames: gapB),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    expect(session.requireActiveCut.id, source.id, reason: 'fixture');
    return session;
  }

  int startOf(EditorSessionManager session, CutId id) {
    var frame = 0;
    for (final cut in session.activeTrack.cuts) {
      frame += cut.leadingGapFrames;
      if (cut.id == id) {
        return frame;
      }
      frame += cut.duration;
    }
    throw StateError('no cut $id');
  }

  Layer conteOf(EditorSessionManager session, CutId cutId) => session
      .activeTrack
      .cuts
      .firstWhere((cut) => cut.id == cutId)
      .layers
      .firstWhere((layer) => layer.kind == LayerKind.storyboard);

  test('F-97: a 겸용 cut made in front of a cut with room leaves it where it '
      'stands', () {
    final session = scene(gapA: 100, gapB: 0);
    final a = startOf(session, followerA);
    final b = startOf(session, followerB);

    session.cutVerbs.createLinkedCutFromActiveCut();

    expect(startOf(session, followerA), a);
    expect(startOf(session, followerB), b);
  });

  test('F-97: a 겸용 cut is as long as a new cut, not as its source', () {
    final session = scene(gapA: 100, gapB: 0);
    expect(
      sourceLength,
      isNot(defaultCutDuration),
      reason: 'fixture: the source is not a new cut\'s length',
    );

    session.cutVerbs.createLinkedCutFromActiveCut();

    expect(session.requireActiveCut.duration, defaultCutDuration);
  });

  for (final (name, make) in <(String, void Function(EditorSessionManager))>[
    ('a new cut', (session) => session.cutVerbs.createCut()),
    (
      'a 겸용 cut',
      (session) => session.cutVerbs.createLinkedCutFromActiveCut(),
    ),
  ]) {
    test('F-97: $name that a gap cannot hold pushes only as far as the next '
        'gap lets the push travel — the frame blocks\' push', () {
      final session = scene(gapA: 5, gapB: 100);
      final b = startOf(session, followerB);

      make(session);

      final landed = session.requireActiveCut;
      expect(
        startOf(session, followerA),
        sourceLength + landed.duration,
        reason: 'A had five frames of room, so it moves to the new cut\'s end',
      );
      expect(
        startOf(session, followerB),
        b,
        reason: 'what A took is spent in the hundred frames in front of B',
      );
    });
  }

  test('F-99: a 겸용 cut\'s conte row is born covering it, with a fresh panel '
      'the shared bank holds', () {
    final session = scene(gapA: 100, gapB: 0);
    session.layerStack.addLayerOfKind(LayerKind.storyboard);
    final sourceId = session.requireActiveCut.id;
    final sourcePanels = {
      for (final exposure in conteOf(session, sourceId).timeline.values)
        exposure.frameId,
    };

    session.cutVerbs.createLinkedCutFromActiveCut();

    final linked = session.requireActiveCut;
    final conte = conteOf(session, linked.id);
    expect(conte.timeline.keys, [0]);
    expect(conte.timeline[0]!.length, linked.duration);
    expect(
      sourcePanels,
      isNot(contains(conte.timeline[0]!.frameId)),
      reason: 'a fresh panel, the way a new conte row is born with one',
    );
    expect(
      [for (final frame in conteOf(session, sourceId).frames) frame.id],
      [for (final frame in conte.frames) frame.id],
      reason: 'the bank is one: the source row holds the new panel too',
    );
  });

  test('one undo takes the 겸용 cut, the gaps it spent and the panel it added '
      'back', () {
    final session = scene(gapA: 5, gapB: 100);
    session.layerStack.addLayerOfKind(LayerKind.storyboard);
    final sourceId = session.requireActiveCut.id;
    final a = startOf(session, followerA);
    final b = startOf(session, followerB);
    final bank = [
      for (final frame in conteOf(session, sourceId).frames) frame.id,
    ];
    final cuts = session.activeTrack.cuts.length;

    session.cutVerbs.createLinkedCutFromActiveCut();
    session.undo();

    expect(session.activeTrack.cuts.length, cuts);
    expect(startOf(session, followerA), a);
    expect(startOf(session, followerB), b);
    expect([
      for (final frame in conteOf(session, sourceId).frames) frame.id,
    ], bank);
  });

  test('F-99: a conte row 겸용 변경 copies into a cut that has none is born '
      'covering that cut, with a fresh panel the shared bank holds', () {
    final session = scene(gapA: 100, gapB: 0);
    session.layerStack.addLayerOfKind(LayerKind.storyboard);
    final sourceId = session.requireActiveCut.id;
    final sourcePanels = {
      for (final exposure in conteOf(session, sourceId).timeline.values)
        exposure.frameId,
    };

    session.cutVerbs.convertActiveCutToLinked(followerA);

    final target = session.activeTrack.cuts.firstWhere(
      (cut) => cut.id == followerA,
    );
    final conte = conteOf(session, followerA);
    expect(conte.timeline.keys, [0]);
    expect(conte.timeline[0]!.length, target.duration);
    expect(sourcePanels, isNot(contains(conte.timeline[0]!.frameId)));
    expect(
      [for (final frame in conteOf(session, sourceId).frames) frame.id],
      [for (final frame in conte.frames) frame.id],
      reason: 'the bank is one: the origin row holds the new panel too',
    );
  });
}
