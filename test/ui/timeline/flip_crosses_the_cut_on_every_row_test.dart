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

/// 🚨F-44 — **플립은 어느 행에 서 있든 컷 끝을 넘는다.**
///
/// > 「타임라인패널에서 **fx 헤더, 멤버 행에 서있을때** 화살표 플립으로
/// > **컷 길이 넘어가는게 불가능**. 터치 플립도 안될것으로 예상. … 이거 딱보니까
/// > 또 몇번째인지 모를 지긋지긋한 **통일미스**같은데」
///
/// 맞았다. 레이어 행은 「프레임 축은 **끝이 없다**」는 자기 법으로 컷 밖까지
/// 걸어가는데(`_flipBlocks` 의 주석이 그렇게 적고 있다), 레인 행만
/// `selectNextFrame` 을 불렀고 그건 `cut.duration - 1` 에서 멈춘다.
const _layerId = LayerId('flip-layer');
const _cutDuration = 6;

EditorSessionManager _session() {
  final manager = EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('flip'),
      name: 'Flip',
      createdAt: DateTime.utc(2026, 8, 28),
      tracks: [
        Track(
          id: const TrackId('flip-track'),
          name: 'V',
          cuts: [
            Cut(
              id: const CutId('flip-cut'),
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

int _frameOf(EditorSessionManager s) => s.currentFrameIndex;

void main() {
  test('전제 — 레이어 행에 서면 컷의 마지막 프레임을 넘어간다', () {
    final s = _session();
    s.standOnRow(const LayerRowAddress(_layerId), frameIndex: _cutDuration - 1);
    expect(_frameOf(s), _cutDuration - 1);

    s.selectNextDrawing();

    expect(
      _frameOf(s),
      greaterThan(_cutDuration - 1),
      reason: '⛔이게 안 되면 계측기가 틀렸다 — 축이 원래 끝이 없다',
    );
  });

  test('🚨fx(레인) 행에 서 있어도 컷 끝을 넘는다', () {
    final s = _session();
    s.standOnRow(
      const LaneRowAddress(_layerId, 'transform'),
      frameIndex: _cutDuration - 1,
    );
    expect(_frameOf(s), _cutDuration - 1);

    s.selectNextDrawing();

    expect(
      _frameOf(s),
      greaterThan(_cutDuration - 1),
      reason:
          '유저: 「fx 헤더, 멤버 행에 서있을때 화살표 플립으로 컷 길이 '
          '넘어가는게 불가능」 — 레이어 행은 넘는다',
    );
  });

  test('뒤로는 두 행 다 프레임 0 이 바닥이다', () {
    for (final row in const <TimelineRowAddress>[
      LayerRowAddress(_layerId),
      LaneRowAddress(_layerId, 'transform'),
    ]) {
      final s = _session();
      s.standOnRow(row, frameIndex: 0);
      s.selectPreviousDrawing();
      expect(_frameOf(s), 0, reason: '$row — 0 밑으로는 안 간다');
    }
  });

  /// ⛔끝없는 축의 규칙을 **각자 적지 않는다** (소스 스캔 래칫).
  test('플립의 착지 규칙은 한 곳이다', () {
    // The library — host plus the parts it lists — because the flip moved
    // into the frame verbs collaborator on 2026-09-03 and a scan of the
    // host alone would have gone quietly empty.
    final source = librarySource('lib/src/ui/editor_session_manager.dart');
    expect(
      source,
      contains('_flipToFrame('),
      reason: '⛔착지(0 바닥 · 천장 없음)를 한 함수가 낸다',
    );
    expect(
      RegExp(r'_flipToFrame\(').allMatches(source).length,
      greaterThanOrEqualTo(3),
      reason: '정의 1 + 레이어 행 + 레인 행 — 셋이 안 되면 한쪽이 자기 규칙을 쓴다',
    );
  });
}
