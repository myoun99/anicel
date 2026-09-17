import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/library_source.dart';

/// 🚨★★★F-148 — **한 프레임 걷기도 컷 끝을 넘는다.**
///
/// > 「분명 컨트롤 누른채로 화살표 누르는데, **처음엔 제대로 1프레임씩
/// > 이동하는거같더니** … **1프레임이동 로직이 안먹힘**. 다시 해보니 그냥
/// > 관계없이 컨트롤+화살표로 1프레임 이동이 **안먹힐때가 있는듯**. 로직 싹
/// > 점검하고 **법 통일할거 통일해서 근본/구조적해결**」 (2026-09-16)
///
/// 🧪재현(2026-09-17): 6프레임짜리 컷의 **마지막 프레임(5)에 서서** Ctrl+→ —
/// 세 행 전부 `step->5`(제자리), 같은 자리의 플립은 `flip->6`. 갭에 파킹한
/// 채로도 걷기는 제자리, 플립은 나간다. 「처음엔 제대로 이동하다가 안 먹는다」가
/// 정확히 이것이다 — 컷 끝까지는 걷고, 거기서 죽는다.
///
/// ↩️[F-44] 가 같은 결함을 **플립에서** 고쳤다(레인 행이 `selectNextFrame` 을
/// 불러 `cut.duration - 1` 에 갇혀 있던 자리). 그때 「[selectNextFrame] 은 컷
/// 안에 갇힌 한 프레임 이동이고 그건 그것대로 옳다」고 적었는데, **그 「호출자」가
/// 바로 유저의 Ctrl+화살표와 `,`·`.` 였다.** 걷기는 프레임 축 위의 한 걸음이고,
/// 그 축은 플립이 말하는 그 축이다 — 끝이 없고, 바닥은 프레임 0 이다.
const _layerId = LayerId('step-layer');
const _trackId = TrackId('step-track');
const _cutDuration = 6;

EditorSessionManager _session() {
  final manager = EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('step'),
      name: 'Step',
      createdAt: DateTime.utc(2026, 9, 16),
      tracks: [
        Track(
          id: _trackId,
          name: 'V',
          cuts: [
            Cut(
              id: const CutId('step-cut'),
              name: '1',
              duration: _cutDuration,
              canvasSize: const CanvasSize(width: 32, height: 32),
              layers: [
                Layer(id: _layerId, name: 'A', frames: const [], timeline: {}),
              ],
            ),
          ],
        ),
      ],
    ),
  );
  addTearDown(manager.dispose);
  return manager;
}

/// 걷기가 서는 모든 행. ⛔한 행만 재면 F-44 를 그대로 반복한다 — 그때 통과하던
/// 레이어 행이 통과하는 동안 레인 행이 갇혀 있었다.
const _everyRow = <TimelineRowAddress>[
  LayerRowAddress(_layerId),
  LaneRowAddress(_layerId, 'transform'),
  TrackRowAddress(_trackId),
];

void main() {
  test('전제 — 같은 자리에서 플립은 컷 끝을 넘는다', () {
    final s = _session();
    s.standOnRow(const LayerRowAddress(_layerId), frameIndex: _cutDuration - 1);
    s.frameVerbs.flipRow(forward: true);
    expect(
      s.currentFrameIndex,
      greaterThan(_cutDuration - 1),
      reason: '⛔이게 안 되면 계측기가 틀렸다 — 프레임 축은 원래 끝이 없다',
    );
  });

  test('🚨한 프레임 걷기가 컷의 마지막 프레임에서 멈추지 않는다 — 어느 행에 서 있든', () {
    for (final row in _everyRow) {
      final s = _session();
      s.standOnRow(row, frameIndex: _cutDuration - 1);
      expect(s.currentFrameIndex, _cutDuration - 1, reason: '$row — 전제');

      s.frameVerbs.selectNextFrame();

      expect(
        s.currentFrameIndex,
        _cutDuration,
        reason:
            '$row — 유저: 「처음엔 제대로 1프레임씩 이동하는거같더니 … '
            '1프레임이동 로직이 안먹힘」. 컷 끝은 벽이 아니다',
      );
    }
  });

  test('🚨갭에 서 있어도 한 프레임 걷는다', () {
    for (final forward in const [true, false]) {
      final s = _session();
      s.standOnRow(const LayerRowAddress(_layerId), frameIndex: 0);
      s.parkGlobalFrame(_cutDuration + 2);
      expect(s.activeCutId, isNull, reason: '전제 — 컷 없는 자리에 서 있다');
      final parked = s.editingGlobalFrame;

      if (forward) {
        s.frameVerbs.selectNextFrame();
      } else {
        s.frameVerbs.selectPreviousFrame();
      }

      expect(
        s.editingGlobalFrame,
        parked + (forward ? 1 : -1),
        reason:
            'forward=$forward — 컷이 없다는 것은 걸을 곳이 없다는 뜻이 아니다. '
            '플립은 여기서 나간다(`_flipCuts`)',
      );
    }
  });

  test('뒤로는 프레임 0 이 바닥이다 — 어느 행에 서 있든', () {
    for (final row in _everyRow) {
      final s = _session();
      s.standOnRow(row, frameIndex: 0);
      s.frameVerbs.selectPreviousFrame();
      expect(s.currentFrameIndex, 0, reason: '$row — 0 밑으로는 안 간다');
    }
  });

  /// ⛔**걷기의 착지 규칙을 각자 적지 않는다** (소스 스캔 래칫).
  ///
  /// 행동 테스트는 「지금은 일치하는 사본 둘」을 통과시킨다 — F-44 가 남긴
  /// 래칫이 그래서 있고, 이건 그 나머지 반이다: 한 프레임을 걷는 **호출자
  /// 전부**가 한 함수를 통한다.
  test('한 프레임 걷기는 한 곳이다', () {
    final source = librarySource('lib/src/ui/session/frame_verbs.dart');
    expect(
      RegExp(r'_stepOneFrame\(').allMatches(source).length,
      greaterThanOrEqualTo(4),
      reason: '정의 1 + 레인 행 플립 + selectNextFrame + selectPreviousFrame',
    );
    expect(
      RegExp(r'_flipToFrame\(').allMatches(source).length,
      3,
      reason:
          '⛔착지는 정의 1 + [_stepOneFrame](한 프레임) + `_flipBlocks`(한 블록) '
          '셋뿐이다 — 프레임 축 위의 걸음은 그 둘밖에 없다. 네 번째가 생겼다면 '
          '누군가 자기 규칙으로 프레임을 내리고 있고, F-44 가 지운 「행마다 '
          '자기 규칙」이 그렇게 돌아온다',
    );
  });
}
