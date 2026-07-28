import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/ui/timeline/selected_exposure_display_range_policy.dart';
import 'package:anicel/src/ui/timeline/timeline_exposure_range_resolver.dart';
import 'package:anicel/src/ui/timeline/timeline_selected_exposure_outline.dart';

void main() {
  const outlineKey = ValueKey<String>(
    'timeline-selected-exposure-range-outline-layer-1',
  );

  testWidgets('does not render outline when there is no visible intersection', (
    tester,
  ) async {
    const displayRange = SelectedExposureDisplayRange(
      resolvedRange: TimelineExposureRange(
        kind: TimelineExposureRangeKind.drawing,
        startFrameIndex: 10,
        endFrameIndexExclusive: 13,
        selectedFrameIndex: 10,
      ),
      visibleStartFrameIndex: 13,
      visibleEndFrameIndexExclusive: 13,
    );

    await tester.pumpWidget(_TestStack(displayRange: displayRange));

    expect(find.byKey(outlineKey), findsNothing);
  });

  testWidgets(
    'renders outline with stable key when visible intersection exists',
    (tester) async {
      const displayRange = SelectedExposureDisplayRange(
        resolvedRange: TimelineExposureRange(
          kind: TimelineExposureRangeKind.drawing,
          startFrameIndex: 10,
          endFrameIndexExclusive: 13,
          selectedFrameIndex: 10,
        ),
        visibleStartFrameIndex: 10,
        visibleEndFrameIndexExclusive: 13,
      );

      await tester.pumpWidget(_TestStack(displayRange: displayRange));

      final outlineFinder = find.byKey(outlineKey);
      expect(outlineFinder, findsOneWidget);
      expect(
        find.descendant(
          of: outlineFinder,
          matching: find.byType(IgnorePointer),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('computes outline left and width with coordinate policy', (
    tester,
  ) async {
    const displayRange = SelectedExposureDisplayRange(
      resolvedRange: TimelineExposureRange(
        kind: TimelineExposureRangeKind.drawing,
        startFrameIndex: 10,
        endFrameIndexExclusive: 13,
        selectedFrameIndex: 10,
      ),
      visibleStartFrameIndex: 10,
      visibleEndFrameIndexExclusive: 13,
    );

    await tester.pumpWidget(_TestStack(displayRange: displayRange));

    final outlineFinder = find.byKey(outlineKey);
    expect(tester.getTopLeft(outlineFinder), const Offset(192, 0));
    expect(tester.getSize(outlineFinder), const Size(144, 24));
  });
}

class _TestStack extends StatelessWidget {
  const _TestStack({required this.displayRange});

  final SelectedExposureDisplayRange displayRange;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          TimelineSelectedExposureOutline(
            layerId: const LayerId('layer-1'),
            displayRange: displayRange,
            frameStartIndex: 8,
            leadingFrameSpacerWidth: 96,
            frameCellWidth: 48,
            rowHeight: 24,
            borderColor: Colors.red,
            borderRadius: const BorderRadius.all(Radius.circular(6)),
          ),
        ],
      ),
    );
  }
}
