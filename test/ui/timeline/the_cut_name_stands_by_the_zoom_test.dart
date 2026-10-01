import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

/// I-57 (유저 2026-10-01): 「현재 컷의 이름을 표기하고싶음. 위치는
/// 타임라인/콘티패널 동일하게. 타임라인 줌의 마이너스버튼 왼쪽. 즉
/// 로컬/글로벌 인덱스를 왼쪽에 두고, 그 사이에 컷이름」.
void main() {
  Cut cut(String id, String name) => Cut(
    id: CutId(id),
    name: name,
    duration: 24,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [Layer(id: LayerId('$id-layer'), name: 'A', frames: const [])],
  );

  Project project() => Project(
    id: const ProjectId('cut-name'),
    name: 'Cut name',
    createdAt: DateTime.utc(2026, 10, 1),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'Video',
        cuts: [cut('cut-a', 'Opening'), cut('cut-b', 'Chase')],
      ),
    ],
  );

  const name = ValueKey<String>('timeline-cut-name');
  const counter = ValueKey<String>('timeline-current-frame-counter');
  const zoomOut = ValueKey<String>('timeline-zoom-out-button');

  for (final storyboard in [false, true]) {
    testWidgets('the ${storyboard ? 'storyboard' : 'timeline'} names the '
        'cut between its counter and its zoom', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: HomePage(initialProject: project()),
        ),
      );
      await tester.pumpAndSettle();
      if (storyboard) {
        await tester.tap(
          find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
        );
        await tester.pumpAndSettle();
      }
      final session = tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .session;
      String shown() => tester.widget<Text>(find.byKey(name)).data!;

      session.selectCut(const CutId('cut-a'));
      await tester.pumpAndSettle();
      expect(shown(), 'Opening');
      final nameRect = tester.getRect(find.byKey(name));
      expect(
        tester.getRect(find.byKey(counter)).right,
        lessThanOrEqualTo(nameRect.left),
        reason: 'the index on the left',
      );
      expect(
        nameRect.right,
        lessThanOrEqualTo(tester.getRect(find.byKey(zoomOut)).left),
        reason: 'the name left of the zoom\'s − button',
      );

      session.selectCut(const CutId('cut-b'));
      await tester.pumpAndSettle();
      expect(shown(), 'Chase', reason: 'the name follows the cut');
    });
  }
}
