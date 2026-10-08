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
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';

/// **A scrub along the ruler rebuilds nothing of the V row's head.**
///
/// The panel's playhead lives on a CURSOR LAYER (W4): the notifier moves per
/// scrub move and only the ruler and the playhead overlay subscribe, because
/// the panel deliberately does not rebuild on a tick.
///
/// ↩️This file was F-19's (유저 2026-08-24: 「스토리보드패널의 버튼, **룰러
/// 스크럽시 현재 인덱스의 컷에 따라 버튼이 갱신 안되고** … **손 떼야 갱신**되서
/// 활성화되거나 하는데 어떻게 가능한가?」). The button was the V row's EYE,
/// which acted on the cut under the playhead and read it at BUILD time — so
/// during a drag it saw the frame the drag started on. It took the
/// subscription the overlay takes, the whole row first and then the eye
/// alone on a tick layer of its own (I-22 ③, 09-28: the row was rebuilt —
/// buttons, faces and tooltips — on every crossing, which at a far zoom is
/// nearly every move). Its first pin was that the eye named the cut the
/// scrub was over while the pointer was still down.
///
/// The eye left the head on 2026-10-08 (I-73, 유저: 「V행의 불투명도랑
/// 비지블 필요없어보여서 삭제하고싶은데 어때」), and nothing the row shows
/// follows the playhead now. What stays of the two is the cost: the row
/// stands through a scrub.
///
/// ⛔And what F-19 ruled out stands for whatever follows the playhead next:
/// not by making the ruler switch the active cut, which the report wondered
/// aloud about. The scrub PARKS on purpose, and the preview machinery around
/// it exists because the active cut does NOT follow a drag.
void main() {
  const frames = 24;

  Project project() => Project(
    id: const ProjectId('f19'),
    name: 'F19',
    createdAt: DateTime.utc(2026, 8, 25),
    tracks: [
      Track(
        id: const TrackId('t'),
        name: 'Video',
        cuts: [
          for (var i = 0; i < 4; i += 1)
            Cut(
              id: CutId('cut-$i'),
              name: 'cut-$i',
              duration: frames,
              canvasSize: const CanvasSize(width: 640, height: 360),
              layers: [
                Layer(id: LayerId('cut-$i-cel'), name: 'A', frames: const []),
              ],
            ),
        ],
      ),
    ],
  );

  final vRow = find.byType(StoryboardTrackLabelRow).first;

  testWidgets('a move inside the cut rebuilds nothing of the V row, and '
      'neither does a move into the next one', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();

    StoryboardTrackLabelRow row() => tester.widget<StoryboardTrackLabelRow>(
      vRow,
    );
    StoryboardPanel panel() =>
        tester.widget<StoryboardPanel>(find.byType(StoryboardPanel));
    final perFrame = panel().pixelsPerFrame;
    final ruler = tester.getRect(
      find.byKey(const ValueKey<String>('storyboard-ruler')),
    );
    final gesture = await tester.startGesture(
      Offset(ruler.left + 2 * perFrame + 2, ruler.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final atTwo = row();
    expect(panel().playheadFrame?.value, 2, reason: 'fixture premise');

    // Frame 2 → 12: still cut-0.
    await gesture.moveBy(Offset(10 * perFrame, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(panel().playheadFrame?.value, 12, reason: 'LIVENESS: it scrubbed');
    expect(identical(row(), atTwo), isTrue, reason: 'inside the cut');

    // Frame 12 → 32: cut-1.
    await gesture.moveBy(Offset(20 * perFrame, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      panel().playheadFrame?.value,
      32,
      reason: 'LIVENESS: the playhead crossed into the next cut',
    );
    expect(
      identical(row(), atTwo),
      isTrue,
      reason: '🚨the whole V row was rebuilt for a crossing — its buttons, '
          'tooltips and all — and it shows nothing of the playhead',
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
