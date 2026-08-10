import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart'
    show TimelineLayerControlsRow;

/// The camera section's row order, top to bottom: CAMERA, TRANSITION,
/// DIRECTION (user 2026-08-10 — "카메라를 제일 위에 두고싶어서").
///
/// The order is measured off the real rail rather than off the model, because
/// the two disagree on purpose: the horizontal timeline REVERSES raw model
/// order, so "append it last" and "draw it on top" are the same sentence.
/// Appending the transition row is exactly what put it above the camera.
void main() {
  testWidgets('the camera section reads CAMERA, TRANSITION, DIRECTION from '
      'the top', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();

    final rows = tester
        .widgetList<TimelineLayerControlsRow>(
          find.byType(TimelineLayerControlsRow),
        )
        .toList();
    final kinds = [for (final row in rows) row.layer.kind];

    // Only the camera section's members — the SE and drawing rows below it are
    // another round's business.
    final cameraSection = [
      for (final kind in kinds)
        if (kind == LayerKind.camera ||
            kind == LayerKind.transition ||
            kind == LayerKind.instruction)
          kind,
    ];
    expect(cameraSection, [
      LayerKind.camera,
      LayerKind.transition,
      LayerKind.instruction,
    ]);

    // And the section really is at the top of the stack: nothing from another
    // section sits above the camera row.
    expect(kinds.first, LayerKind.camera);
  });

  testWidgets('the rows are laid out in that order on screen, not merely '
      'listed in it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();

    double topOf(LayerKind kind) {
      final finder = find.byWidgetPredicate(
        (widget) =>
            widget is TimelineLayerControlsRow && widget.layer.kind == kind,
      );
      expect(finder, findsOneWidget, reason: '$kind row');
      return tester.getTopLeft(finder).dy;
    }

    expect(topOf(LayerKind.camera), lessThan(topOf(LayerKind.transition)));
    expect(
      topOf(LayerKind.transition),
      lessThan(topOf(LayerKind.instruction)),
    );
  });
}
