import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import '../../helpers/library_source.dart';

/// 🚨F-16 — **레이어 영역의 선택범위는 어느 행에서도 시작할 수 있다.**
///
/// > 「제대로 전달이 안된거같은데, **설마 프레임영역으로 오해한건가**? 레이어
/// > 선택이 작동해야한다고. **레이어영역의 레이어 선택범위.** 지금 다른
/// > 레이어에서 선택범위 시작해서 카메라나 트랜지션레이어로 선택범위
/// > 작동가능한데 **카메라나 트랜지션레이어에서 선택범위 시작하려하면
/// > 작동안함**」
///
/// ⚠️이 카드는 한 번 「고칠 것 없다」로 닫혔었다. 그때의 테스트
/// (`camera_and_transition_rows_select_test`)는 드래그를 `timelineCellCenter`
/// 에서 시작한다 — **프레임 영역**이다. 유저가 짚은 그 오해가 실제로 일어나
/// 있었고, **이 파일은 이름 영역에서 시작한다.**
const _drawId = 'sel-draw';
const _cameraId = 'sel-camera';
const _transitionId = 'sel-transition';

Project _project() => Project(
  id: const ProjectId('sel-project'),
  name: 'Selection',
  createdAt: DateTime.utc(2026, 8, 28),
  tracks: [
    Track(
      id: const TrackId('sel-track'),
      name: 'V',
      cuts: [
        Cut(
          id: const CutId('sel-cut'),
          name: 'Cut',
          duration: 12,
          canvasSize: const CanvasSize(width: 640, height: 360),
          camera: CutCamera.empty(),
          layers: [
            Layer(
              id: const LayerId(_drawId),
              name: 'Drawing',
              frames: const [],
            ),
            Layer(
              id: const LayerId(_transitionId),
              name: 'Transition',
              kind: LayerKind.transition,
              frames: const [],
            ),
            Layer(
              id: const LayerId(_cameraId),
              name: 'Camera',
              kind: LayerKind.camera,
              frames: const [],
            ),
          ],
        ),
      ],
    ),
  ],
);

EditorSessionManager _sessionOf(WidgetTester tester) =>
    tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: _project())),
  );
  await tester.pumpAndSettle();
  await tester.drag(
    find.byKey(const ValueKey<String>('dock-resize-bottom')),
    const Offset(0, -520),
  );
  await tester.pumpAndSettle();
}

/// 🚨**이름 글자를 잡는다.** 행 rect 의 오른쪽 끝은 fx·눈·불투명도·블렌드가
/// 늘어선 컨트롤 띠라 [RowControlSurface] 가 거절한다 — 실제로 거기를 잡았다가
/// 세 테스트가 모두 빈 선택을 봤다. 이름 영역은 「버튼이 아닌 곳」이고, 유저가
/// 「레이어이름영역이나 그 외 버튼 요소가 아닌 부분만」이라고 정한 그 자리다.
Future<void> _dragNameArea(
  WidgetTester tester,
  String fromName,
  String toLayerId,
) async {
  final start = tester.getCenter(find.text(fromName).first);
  final to = tester.getRect(
    find.byKey(ValueKey<String>('timeline-layer-row-$toLayerId')),
  );
  final gesture = await tester.startGesture(start);
  await tester.pump(const Duration(milliseconds: 16));
  await gesture.moveTo(Offset(start.dx, to.center.dy));
  await tester.pump(const Duration(milliseconds: 16));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  _bothRailsSelectOnly();
  _unmovableRowNeverMoves();

  testWidgets('전제 — 그리는 레이어에서 시작하면 선택범위가 생긴다', (tester) async {
    await _pump(tester);
    final session = _sessionOf(tester);
    expect(session.rowSelection.value, isEmpty, reason: '시작 전에는 비어 있다');

    await _dragNameArea(tester, 'Drawing', _cameraId);

    expect(
      session.rowSelection.value,
      hasLength(greaterThanOrEqualTo(2)),
      reason: '⛔이게 안 되면 계측기가 틀린 것이다 — 이름 영역을 못 잡고 있다',
    );
  });

  for (final entry in {
    '카메라': (_cameraId, 'Camera'),
    '트랜지션': (_transitionId, 'Transition'),
  }.entries) {
    testWidgets('🚨${entry.key} 행에서 **시작**해도 선택범위가 생긴다', (tester) async {
      await _pump(tester);
      final session = _sessionOf(tester);

      await _dragNameArea(tester, entry.value.$2, _drawId);

      expect(
        session.rowSelection.value,
        hasLength(greaterThanOrEqualTo(2)),
        reason:
            '유저: 「${entry.key}레이어에서 선택범위 시작하려하면 작동안함」. '
            '막으라고 한 것은 **드래그 이동뿐**이다',
      );
    });
  }
}

/// ⛔**두 레일이 같은 법을 쓴다** (소스 스캔 래칫).
///
/// x시트는 가로 레일의 버그를 **모양째로 베껴서** 갖고 있었다 — 둘 다
/// `if (!layerKindReordersInCut(...)) return child;` 였고, 그 한 줄이
/// 「이동 불가」로 「선택 불가」까지 답했다. 행동 테스트는 지금 가로 레일만
/// 몰고 있으므로, **x시트가 다시 갈라지는 것은 소스가 막는다.**
void _bothRailsSelectOnly() {
  test('재배치 불가 행의 답은 한 곳이고, 두 레일이 그것을 부른다', () {
    // 법이 사는 곳 — 여기서만 kind 를 묻는다.
    final owner = File(
      'lib/src/ui/timeline/layer_row_drag.dart',
    ).readAsStringSync();
    expect(
      owner,
      contains('layerKindReordersInCut'),
      reason: '⛔법이 여기 없으면 스캔이 빈 것을 쟀다',
    );

    // 래퍼 — 두 레일이 각자 적던 행 드래그 포장을 한 함수로 합쳤다(2026-09-03
    // 사본 스캔). 재배치 불가 행의 답은 여기서 **한 번** 불린다.
    expect(owner, contains('Widget layerRowDragWrapper('));
    final wrapper = owner.substring(
      owner.indexOf('Widget layerRowDragWrapper('),
    );
    expect(
      wrapper,
      contains('unmovableRowSelectTarget('),
      reason: '⛔래퍼가 그 한 함수를 안 부르면 두 레일이 다시 각자 답한다(F-16)',
    );

    // 두 레일 — 각자 적지 말고 **부른다.**
    for (final path in const [
      'lib/src/ui/timeline/layer_timeline_grid.dart',
      'lib/src/ui/timeline/xsheet_timeline_grid.dart',
    ]) {
      // A grid is a LIBRARY — the file plus the collaborator parts the
      // audit's SRP cuts (2026-09-02) put beside it — so the call is found
      // where a cut put it.
      final source = librarySource(path);
      expect(
        source,
        contains('layerRowDragWrapper('),
        reason:
            '$path — 재배치 불가 행의 답을 **한 함수**가 낸다(F-16); '
            '레일은 그 래퍼를 부른다',
      );
      expect(
        source,
        isNot(contains('unmovableRowSelectTarget(')),
        reason: '$path — 레일이 직접 부르면 래퍼와 두 벌이다',
      );
      expect(
        source,
        isNot(contains('layerKindReordersInCut')),
        reason:
            '$path — 레일이 kind 를 **직접 물으면 사본이다.** x시트가 가로 '
            '레일의 그 한 줄을 베껴서 같은 버그를 갖고 있었다',
      );
    }
  });
}

/// 🚨**선택 안에 있어도 움직이지는 않는다.**
///
/// 행 드래그는 누르는 순간 이동/선택을 정하는데, 그 판단이
/// 「지금 선택 안에 있나?」 하나였다 — 선택 안에 있으면 **이동**이다.
/// 재배치가 금지된 행이 선택에 들어가 있으면 그 길로 **움직일 수 없는 행의
/// 이동이 시작된다.** 그래서 `canReorder` 가 그 앞에 선다.
///
/// ⚠️이 경우가 없으면 플래그를 지워도 테스트가 다 통과한다 — 실제로 그랬다.
void _unmovableRowNeverMoves() {
  testWidgets('선택에 들어 있는 카메라 행을 끌어도 이동이 시작되지 않는다', (tester) async {
    await _pump(tester);
    final session = _sessionOf(tester);

    // 카메라 행이 **선택 안에** 있게 만든다 — 여기가 이동 경로로 빠지던 입구다.
    session.rowSelection.value = const [
      LayerRowAddress(LayerId(_drawId)),
      LayerRowAddress(LayerId(_transitionId)),
      LayerRowAddress(LayerId(_cameraId)),
    ];
    await tester.pumpAndSettle();

    final start = tester.getCenter(find.text('Camera').first);
    final to = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-layer-row-$_drawId')),
    );
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveTo(Offset(start.dx, to.center.dy));
    await tester.pump(const Duration(milliseconds: 16));

    // 🚨드래그가 **살아 있는 동안** 본다 — 놓은 뒤에는 이동이든 선택이든
    // 상태가 지워져서 둘을 구분할 수 없다.
    expect(
      session.layerRowDrag.value,
      isNull,
      reason:
          '카메라 행은 움직일 수 없다(A5-4). 선택 안에 있다는 이유로 '
          '이동이 시작되면 놓을 자리가 없는 드래그가 뜬다',
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
