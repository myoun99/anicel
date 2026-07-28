import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/timeline/timeline_body_cut_end_boundary.dart';
import 'package:anicel/src/ui/timeline/timeline_ruler_cut_end_boundary.dart';

void main() {
  const rulerBoundaryKey = ValueKey<String>('timeline-cut-end-boundary-ruler');
  const bodyBoundaryKey = ValueKey<String>('timeline-cut-end-boundary');

  testWidgets('ruler cut-end boundary stable key exists exactly once', (
    tester,
  ) async {
    await _pumpBoundaryStack(tester, const [
      TimelineRulerCutEndBoundary(left: 48),
    ]);

    expect(find.byKey(rulerBoundaryKey), findsOneWidget);
  });

  testWidgets('body cut-end boundary stable key exists exactly once', (
    tester,
  ) async {
    await _pumpBoundaryStack(tester, const [
      TimelineBodyCutEndBoundary(left: 48),
    ]);

    expect(find.byKey(bodyBoundaryKey), findsOneWidget);
  });

  testWidgets('ruler and body boundary keys are not confused', (tester) async {
    await _pumpBoundaryStack(tester, const [
      TimelineRulerCutEndBoundary(left: 48),
      TimelineBodyCutEndBoundary(left: 96),
    ]);

    expect(find.byKey(rulerBoundaryKey), findsOneWidget);
    expect(find.byKey(bodyBoundaryKey), findsOneWidget);
  });

  testWidgets('ruler boundary width remains 2 and left is passed through', (
    tester,
  ) async {
    await _pumpBoundaryStack(tester, const [
      TimelineRulerCutEndBoundary(left: 48),
    ]);

    final positioned = _positionedUnderBoundary(rulerBoundaryKey, tester);
    expect(positioned.width, 2);
    expect(positioned.left, 48);
  });

  testWidgets('body boundary width remains 2 and left is passed through', (
    tester,
  ) async {
    await _pumpBoundaryStack(tester, const [
      TimelineBodyCutEndBoundary(left: 48),
    ]);

    final positioned = _positionedUnderBoundary(bodyBoundaryKey, tester);
    expect(positioned.width, 2);
    expect(positioned.left, 48);
  });

  testWidgets('ruler boundary marker keeps IgnorePointer', (tester) async {
    await _pumpBoundaryStack(tester, const [
      TimelineRulerCutEndBoundary(left: 48),
    ]);

    expect(_ignorePointerUnderBoundary(rulerBoundaryKey), findsOneWidget);
  });

  testWidgets('body boundary marker keeps IgnorePointer', (tester) async {
    await _pumpBoundaryStack(tester, const [
      TimelineBodyCutEndBoundary(left: 48),
    ]);

    expect(_ignorePointerUnderBoundary(bodyBoundaryKey), findsOneWidget);
  });
}

Future<void> _pumpBoundaryStack(
  WidgetTester tester,
  List<Widget> children,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Material(
        child: SizedBox(
          width: 300,
          height: 120,
          child: Stack(children: children),
        ),
      ),
    ),
  );
}

Positioned _positionedUnderBoundary(Key boundaryKey, WidgetTester tester) {
  return tester.widget<Positioned>(
    find.descendant(
      of: find.byKey(boundaryKey),
      matching: find.byType(Positioned),
    ),
  );
}

Finder _ignorePointerUnderBoundary(Key boundaryKey) {
  return find.descendant(
    of: find.byKey(boundaryKey),
    matching: find.byType(IgnorePointer),
  );
}
