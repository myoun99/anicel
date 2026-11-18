import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/ruler_marker.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_body_cut_end_boundary.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_ruler.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_ruler_cursor_overlay.dart';

import '../../helpers/timeline_host.dart';

/// 🔬Card an-eye-toggle-holds-the-ui-thread (11-18, ㉢): the frame panels
/// are built again for every announcement but a stand, and the shell round
/// their rows — the ruler, the cut's stops over the cells — was built, laid
/// out and painted again for each: an eye toggled built the ruler's 19
/// widgets and its tick layers again. They keep themselves while what they
/// are drawn from stands, and hear what they draw.
void main() {
  TimelineFrameRuler ruler(WidgetTester tester) =>
      tester.widget(find.byType(TimelineFrameRuler));
  TimelineBodyCutEndBoundary stops(WidgetTester tester) =>
      tester.widget(find.byType(TimelineBodyCutEndBoundary));
  TimelineRulerCursorOverlay bar(WidgetTester tester) =>
      tester.widget(find.byType(TimelineRulerCursorOverlay));

  Future<void> rest(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  void toggleRowA(EditorSessionManager session) =>
      session.layerSwitches.toggleLayerVisibility(
        session.requireActiveCut.layers
            .firstWhere((row) => row.kind == LayerKind.animation)
            .id,
      );

  testWidgets('an eye toggled keeps the ruler and the cut\'s stops — and '
      'the ruler\'s bar hears that its answer may have moved', (tester) async {
    final session = await pumpTimelineHost(tester, createDefaultProject());
    final rulerBefore = ruler(tester);
    final stopsBefore = stops(tester);
    final barBefore = bar(tester).readyRunsIn;
    expect(barBefore, isNotNull, reason: '⛔premise: the bar reads the cut');

    toggleRowA(session);
    await tester.pump();

    expect(identical(ruler(tester), rulerBefore), isTrue);
    expect(identical(stops(tester), stopsBefore), isTrue);
    expect(
      identical(bar(tester).readyRunsIn, barBefore),
      isFalse,
      reason: 'a new answer is the news that the green bar may have moved',
    );
    await rest(tester);
  });

  testWidgets('what they draw builds them again', (tester) async {
    final session = await pumpTimelineHost(tester, createDefaultProject());
    var rulerBefore = ruler(tester);
    var stopsBefore = stops(tester);

    // As a trim commits it: the command, then the announcement.
    final cut = session.requireActiveCut;
    session.cutCommandCoordinator.commitCutDurationDrag(
      beforeDurations: {cut.id: cut.duration},
      afterDurations: {cut.id: cut.duration + 12},
    );
    session.notifyChanged();
    await tester.pump();
    expect(identical(ruler(tester), rulerBefore), isFalse, reason: 'frames');
    expect(identical(stops(tester), stopsBefore), isFalse, reason: 'its end');
    await rest(tester);

    rulerBefore = ruler(tester);
    stopsBefore = stops(tester);
    session.rulerMarkers.setMarkers(
      RulerMarkerHolder.cut(session.activeCutId!),
      RulerMarkers.settled(const [RulerMarker(start: 4, text: 'ab')]),
    );
    await tester.pump();
    expect(
      identical(ruler(tester), rulerBefore),
      isFalse,
      reason: 'a marker is the ruler\'s',
    );
    expect(
      identical(stops(tester), stopsBefore),
      isTrue,
      reason: 'and nothing of the stops\'',
    );
    await rest(tester);
  });

  // The X-sheet stands the same stops over its cells (one stack).
  testWidgets('the X-sheet\'s stops keep themselves for an eye too', (
    tester,
  ) async {
    final session = await pumpTimelineHost(
      tester,
      createDefaultProject(),
      orientation: TimelineOrientation.vertical,
    );
    final stopsBefore = stops(tester);

    toggleRowA(session);
    await tester.pump();

    expect(identical(stops(tester), stopsBefore), isTrue);
    await rest(tester);
  });
}
