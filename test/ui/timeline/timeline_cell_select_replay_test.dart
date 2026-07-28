import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/timeline/timeline_cell_exposure_state.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_block_visual.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_cell.dart';

/// Selection must NEVER rewind: with onDoubleTap registered, an InkWell
/// onTap resolves ~300ms late, so tapping cell B right after cell A used to
/// replay A's deferred tap AFTER B's pointer-down selection (the selection
/// visibly jumped B → A → B). Pointer selection rides the raw pointer-down
/// only; the arena never re-selects.
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
}
