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

/// **F-19 — the V row's buttons act on the cut under the playhead, and the
/// playhead moves while you are still holding it.**
///
/// 유저 2026-08-24: 「스토리보드패널의 버튼, **룰러 스크럽시 현재 인덱스의 컷에
/// 따라 버튼이 갱신 안되고** … **손 떼야 갱신**되서 활성화되거나 하는데 어떻게
/// 가능한가?」
///
/// 🚨It was working as built. The panel's playhead lives on a CURSOR LAYER
/// (W4): the notifier moves per scrub move and only the ruler and the
/// playhead overlay subscribe, because the panel deliberately does not
/// rebuild on a tick. The V row read that value at BUILD time, so during a
/// drag it saw the frame the drag started on.
///
/// ⛔The fix is not to make the ruler switch the active cut, which the
/// report wondered aloud about: the scrub PARKS on purpose, and the preview
/// machinery around it exists because the active cut does NOT follow a drag.
/// The row subscribes instead — one row per track, the cost the ruler beside
/// it already pays.
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

  testWidgets('the V row\'s subject follows the ruler mid-drag', (
    tester,
  ) async {
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

    String? subject() => tester
        .widget<StoryboardTrackLabelRow>(
          find.byType(StoryboardTrackLabelRow).first,
        )
        .subjectCut
        ?.id
        .value;

    final perFrame = tester
        .widget<StoryboardPanel>(find.byType(StoryboardPanel))
        .pixelsPerFrame;
    final ruler = tester.getRect(
      find.byKey(const ValueKey<String>('storyboard-ruler')),
    );
    expect(subject(), 'cut-0', reason: 'fixture premise');

    // Press inside cut-0 and drag right, one cut's worth of frames at a
    // time, WITHOUT releasing.
    final gesture = await tester.startGesture(
      Offset(ruler.left + 2 * perFrame + 2, ruler.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 16));

    final seen = <String?>[];
    for (var step = 1; step <= 6; step += 1) {
      await gesture.moveBy(Offset(10 * perFrame, 0));
      await tester.pump(const Duration(milliseconds: 16));
      seen.add(subject());
    }

    expect(
      seen,
      ['cut-0', 'cut-0', 'cut-1', 'cut-1', 'cut-2', 'cut-2'],
      reason: 'frame 2 + 10 per move over 24-frame cuts: 12, 22, 32, 42, '
          '52, 62 — and the row named the cut each one lands in while the '
          'pointer was still down',
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      subject(),
      'cut-2',
      reason: 'the release changes nothing that the drag had not already '
          'shown — which is the whole complaint, inverted',
    );
  });
}
