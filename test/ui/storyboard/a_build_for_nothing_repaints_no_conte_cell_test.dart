import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import '../../helpers/conte_track_fixture.dart';

/// 🚨I-57: A STORYBOARD BUILT AGAIN FOR NOTHING HANDS ITS CONTE ROW THE ROW
/// IT HAD.
///
/// Its host builds it again on every notify it hears — a cut crossed under
/// the playhead among them — and the conte row's painter knows the row by
/// identity. Laid out anew on each build, the row read as changed every
/// time: the whole film's conte cells were painted again and said again to
/// a screen reader, for a crossing that moved none of them (🔬the largest
/// cost of a crossing's frame on the AMMI OP, 10-14).
void main() {
  testWidgets('the conte row\'s painter has nothing to paint again and '
      'nothing to say again', (tester) async {
    final notify = ValueNotifier<int>(0);
    addTearDown(notify.dispose);
    final project = conteTrackProject();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: notify,
            builder: (_, _, _) => StoryboardPanel(
              project: project,
              activeCutId: const CutId('cut-1'),
            ),
          ),
        ),
      ),
    );
    TimelineRowCellsPainter conteCells() =>
        tester
                .widget<CustomPaint>(
                  find.byWidgetPredicate(
                    (widget) =>
                        widget is CustomPaint &&
                        widget.painter is TimelineRowCellsPainter,
                  ),
                )
                .painter!
            as TimelineRowCellsPainter;
    final before = conteCells();
    expect(before.layer.timeline, isNotEmpty, reason: 'premise: panels');

    notify.value += 1;
    await tester.pump();
    final after = conteCells();

    expect(after, isNot(same(before)), reason: 'premise: built again');
    expect(after.shouldRepaint(before), isFalse);
    expect(after.shouldRebuildSemantics(before), isFalse);
  });
}
