import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

/// F-4 — the rows keep a drag past their start, like the frames beside them.
///
/// 유저 2026-08-31: 「왼쪽 최대치 넘어서 드래그하면 타임라인이 오른쪽으로 쭉
/// 밀려서 왼쪽이랑 갭 발생하는 애니메이션이 존재해. 거기서 손 떼면 원래위치로
/// 돌아가고, 이거 마음에 드는데 레이어쪽 드래그 스크롤은 그렇지 않단거야」.
///
/// Where the platform bounces (iOS), a finger dragging the FRAME axis past
/// its start pulls a gap open and the release brings it home. The ROW axis
/// did the same for a row's height and then snapped back to the edge while
/// the finger was still down — every row it passed. So both axes are driven
/// by one real drag each and sampled on every frame of it.
///
/// ⚠️Product input, not the test corpus's: the corpus draws with one finger,
/// and a finger that draws makes a range on the timeline instead of
/// scrolling it (결정 10), which is a drag that never reaches either axis.
void main() {
  testWidgets(
    'the rows keep a drag past their start, like the frames beside them',
    (tester) async {
      AppInput.settings.value = const AppInputSettings();
      addTearDown(
        () => AppInput.settings.value = AppInputSettings.testCorpusBaseline,
      );
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();
      final session = tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .session;
      // Rows enough to scroll: the drag is past the START, so the far end
      // only has to exist.
      for (var i = 0; i < 30; i += 1) {
        session.layerStack.addLayerOfKind(LayerKind.animation);
      }
      await tester.pumpAndSettle();

      ScrollPosition positionOf(String key) => tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(ValueKey<String>(key)),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      final start =
          tester.getTopLeft(
            find.byKey(const ValueKey<String>('timeline-frame-grid-area')),
          ) +
          const Offset(40, 40);

      /// Every sample of one finger dragging [key]'s axis by [step] per frame
      /// from its start, then where it rests.
      Future<({List<double> drag, double rest})> dragPastStart(
        String key,
        Offset step,
      ) async {
        positionOf(key).jumpTo(0);
        await tester.pumpAndSettle();
        final finger = await tester.startGesture(
          start,
          kind: PointerDeviceKind.touch,
        );
        final drag = <double>[];
        for (var i = 0; i < 20; i += 1) {
          await finger.moveBy(step);
          await tester.pump(const Duration(milliseconds: 16));
          drag.add(positionOf(key).pixels);
        }
        await finger.up();
        await tester.pumpAndSettle();
        return (drag: drag, rest: positionOf(key).pixels);
      }

      /// Whether the axis, once past its start, stayed past it for the rest
      /// of the drag — the gap the finger pulled open stays open.
      bool heldPastStart(List<double> drag) {
        final first = drag.indexWhere((pixels) => pixels < 0);
        return first >= 0 && drag.skip(first).every((pixels) => pixels < 0);
      }

      final frames = await dragPastStart(
        'timeline-frame-scroll-viewport',
        const Offset(12, 0),
      );
      expect(
        heldPastStart(frames.drag),
        isTrue,
        reason: 'fixture: the frame axis bounces here — ${frames.drag}',
      );
      expect(frames.rest, 0, reason: 'fixture: and comes home');

      final rows = await dragPastStart(
        'timeline-vertical-scroll-viewport',
        const Offset(0, 12),
      );
      expect(
        heldPastStart(rows.drag),
        isTrue,
        reason:
            'the rows snapped back to their edge under the finger: '
            '${rows.drag}',
      );
      expect(rows.rest, 0, reason: 'the release brings the rows home');

      session.playbackRig.prerenderScheduler.cancel();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
