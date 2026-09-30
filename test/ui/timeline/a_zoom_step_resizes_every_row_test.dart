import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_ruler.dart';

/// 🚨F-244: EVERY ROW IS AS LONG AS THE CUT IT SHOWS, AFTER A ZOOM STEP TOO.
///
/// A row sits on a tick layer of its own size (a drag step lays out alone),
/// and a zoom step keeps a row's memo entry while it moves the content
/// extent — so the box that sizes the row is laid fresh on every build,
/// outside the memo. Held inside it, a zoomed-in row kept the old width:
/// short of its own cells, which no longer took a press.
void main() {
  testWidgets('a zoom step reaches every row: each is as long as the ruler', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomePage(initialProject: createDefaultProject()),
      ),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    session.layerStack.addLayer();
    await tester.pumpAndSettle();

    // The rows body's own keys: 'timeline-row-<layer>-<cells|lane>' — not
    // the cells widget inside ('timeline-row-cells-<layer>').
    final rows = find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('timeline-row-') &&
          !key.value.startsWith('timeline-row-cells-');
    });
    List<double> widths() => [
      for (final row in rows.evaluate())
        (row.renderObject! as RenderBox).size.width,
    ];
    double ruler() => tester.getSize(find.byType(TimelineFrameRuler)).width;

    final before = widths();
    expect(before, isNotEmpty, reason: 'premise: rows are on screen');
    expect(before.toSet(), {ruler()}, reason: 'premise: they start alike');

    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-zoom-in-button')),
    );
    await tester.pumpAndSettle();

    expect(ruler(), greaterThan(before.first), reason: 'premise: it zoomed');
    expect(widths().toSet(), {ruler()});
  });
}
