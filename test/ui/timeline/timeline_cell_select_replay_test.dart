import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_block_visual.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cell.dart';

/// Selection must NEVER rewind: with onDoubleTap registered, an InkWell
/// onTap resolves ~300ms late, so tapping cell B right after cell A used to
/// replay A's deferred tap AFTER B's selection (the selection visibly jumped
/// B → A → B). The pick rides the raw pointer stream; the arena never
/// re-selects.
///
/// ㉟ (유저 2026-08-12, 「둘 다 선택하려면 탭. 즉 손 떼야 선택됨」): that raw
/// pick lands on the RELEASE for every device now, the way the rail row's tap
/// always has. The two tests at the bottom are the pair that pins it — one
/// fails if a device starts acting on the press again, the other if a drag
/// stops being exempt.
void main() {
  testWidgets('quick successive taps never re-select the previous cell', (
    tester,
  ) async {
    final selections = <int>[];
    final layer = Layer(
      id: const LayerId('layer'),
      name: 'L',
      frames: const [],
    );

    Widget cell(int frameIndex) => TimelineFrameCell(
      layer: layer,
      frameIndex: frameIndex,
      active: true,
      outsidePlaybackRange: false,
      exposureState: TimelineCellExposureState.uncovered,
      exposureBlockSegment: TimelineExposureBlockVisualSegment.none,
      onSelectLayer: (_) {},
      onSelectFrame: selections.add,
      // Double-tap registered = the arena defers plain taps (the bug's
      // precondition on every layer kind since the entrance unification).
      onActivateCell: (_, _) {},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Row(children: [cell(0), cell(1)])),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-cell-layer-0')),
    );
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-cell-layer-1')),
    );
    // Let every deferred recognizer deadline fire.
    await tester.pump(const Duration(milliseconds: 700));

    expect(selections.first, 0);
    expect(selections.last, 1);
    final lastZero = selections.lastIndexOf(0);
    final firstOne = selections.indexOf(1);
    expect(
      lastZero < firstOne,
      isTrue,
      reason:
          'no selection of cell 0 may replay after cell 1 was selected '
          '(got $selections)',
    );
  });

  testWidgets('double-tap still activates the cell editor', (tester) async {
    final activated = <int>[];
    final layer = Layer(
      id: const LayerId('layer'),
      name: 'L',
      frames: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelineFrameCell(
            layer: layer,
            frameIndex: 3,
            active: true,
            outsidePlaybackRange: false,
            exposureState: TimelineCellExposureState.uncovered,
            exposureBlockSegment: TimelineExposureBlockVisualSegment.none,
            onSelectLayer: (_) {},
            onSelectFrame: (_) {},
            onActivateCell: (_, frame) => activated.add(frame),
          ),
        ),
      ),
    );

    final cell = find.byKey(const ValueKey<String>('timeline-cell-layer-3'));
    await tester.tap(cell);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(cell);
    await tester.pumpAndSettle();

    expect(activated, [3]);
  });

  /// ㉟. The pen used to pick on the DOWN and only a finger waited; now every
  /// device waits, so a press is "I am about to do something here" and only
  /// the release is "pick this".
  for (final kind in const [
    PointerDeviceKind.stylus,
    PointerDeviceKind.mouse,
    PointerDeviceKind.touch,
  ]) {
    testWidgets('㉟ a ${kind.name} press picks nothing until it is released', (
      tester,
    ) async {
      final selections = <int>[];
      final layer = Layer(
        id: const LayerId('layer'),
        name: 'L',
        frames: const [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimelineFrameCell(
              layer: layer,
              frameIndex: 2,
              active: true,
              outsidePlaybackRange: false,
              exposureState: TimelineCellExposureState.uncovered,
              exposureBlockSegment: TimelineExposureBlockVisualSegment.none,
              onSelectLayer: (_) {},
              onSelectFrame: selections.add,
              onActivateCell: (_, _) {},
            ),
          ),
        ),
      );

      final cell = find.byKey(const ValueKey<String>('timeline-cell-layer-2'));
      final gesture = await tester.startGesture(
        tester.getCenter(cell),
        kind: kind,
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        selections,
        isEmpty,
        reason: 'the press alone must pick nothing — 「손 떼야 선택됨」',
      );

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(selections, [2], reason: 'the release is the pick');
    });
  }

  testWidgets('㉟ a press that TRAVELS is a drag — it picks nothing', (
    tester,
  ) async {
    final selections = <int>[];
    final layer = Layer(
      id: const LayerId('layer'),
      name: 'L',
      frames: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimelineFrameCell(
            layer: layer,
            frameIndex: 5,
            active: true,
            outsidePlaybackRange: false,
            exposureState: TimelineCellExposureState.uncovered,
            exposureBlockSegment: TimelineExposureBlockVisualSegment.none,
            onSelectLayer: (_) {},
            onSelectFrame: selections.add,
            onActivateCell: (_, _) {},
          ),
        ),
      ),
    );

    final cell = find.byKey(const ValueKey<String>('timeline-cell-layer-5'));
    final gesture = await tester.startGesture(
      tester.getCenter(cell),
      kind: PointerDeviceKind.stylus,
    );
    // Past the travel slop, in steps — one big jump is not how a drag
    // arrives, and the region reads the moves.
    for (var i = 0; i < 4; i += 1) {
      await gesture.moveBy(const Offset(12, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      selections,
      isEmpty,
      reason:
          'a drag must not leave a pick behind it — that is what makes the '
          'range/move drags safe to build on (유저: 「드래그도 만들기 편하고」)',
    );
  });
}
