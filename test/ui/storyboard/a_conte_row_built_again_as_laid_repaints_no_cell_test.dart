import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/frame_ruler_view.dart';
import 'package:anicel/src/ui/timeline/timeline_row_cells_painter.dart';

import '../../helpers/conte_track_fixture.dart';

/// 🚨I-57: A CONTE ROW BUILT AGAIN WHILE ITS CUTS LIE ALIKE HANDS ITS CELLS
/// THE ROW THEY HAD.
///
/// The conte row's painter knows the row by identity. Laid out anew on each
/// build, the row read as changed every time: the whole film's conte cells
/// were painted again and said again to a screen reader, for a crossing
/// that moved none of them (🔬the largest cost of a crossing's frame on the
/// AMMI OP, 10-14). A build for nothing no longer reaches the row at all
/// (a_build_for_nothing_hands_back_the_track_rows_test.dart); a build for
/// what the cells do not show — the seconds its run labels print — does.
void main() {
  testWidgets('built again for its seconds, the conte row\'s cells have '
      'nothing to paint again and nothing to say again', (tester) async {
    final rulerView = ValueNotifier(FrameRulerView.frames);
    addTearDown(rulerView.dispose);
    // F-357: with the unworked-block tint on, as the storyboard tab gives it.
    final revision = ValueNotifier<int>(0);
    addTearDown(revision.dispose);
    final ConteCelContent content = (
      holdsAPicture: (cut, row, cel) => false,
      cannotBeRead: (cut, row, cel) => false,
      revision: revision,
    );
    final project = conteTrackProject();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<FrameRulerView>(
            valueListenable: rulerView,
            builder: (_, view, _) => StoryboardPanel(
              project: project,
              activeCutId: const CutId('cut-1'),
              rulerView: view,
              conteCelContent: content,
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
    expect(before.celContent, isNotNull, reason: 'premise: the tint');

    rulerView.value = FrameRulerView.secondsPlusFrames;
    await tester.pump();
    final after = conteCells();

    expect(after, isNot(same(before)), reason: 'premise: built again');
    expect(after.shouldRepaint(before), isFalse);
    expect(after.shouldRebuildSemantics(before), isFalse);
  });
}
