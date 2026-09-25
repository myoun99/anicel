import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/session_legend_callbacks.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_header.dart';
import 'package:anicel/src/ui/timeline/timeline_row_filter.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

/// 🚨A SOLO THE FILTER HOLDS CAN ALWAYS BE UNDONE
/// (mark-filter-held-after-its-mark-is-gone, 유저 2026-09-25: 「초기상태에서
/// 레이아웃만 켜고, 다시 돌리려고 마크 모두 지우기 눌렀는데도 초기화안됨」).
///
/// The legend's solo lists were built from what the ROWS carry. 「마크 모두
/// 지우기」 wipes every row's label, so the LO the filter held left the list
/// — every row but the standing one stayed hidden, the legend icon stayed
/// lit, and there was nothing to uncheck. The kind solo had the same shape
/// for a kind whose last row went away.
void main() {
  const layout = LayerMark(process: LayerProcess.layout);

  Future<_Heard> pump(
    WidgetTester tester, {
    required TimelineRowFilter filter,
    Set<LayerMark> marksInUse = const {},
    Set<LayerKind> kindsInUse = const {},
  }) async {
    final marks = <LayerMark>[];
    final kinds = <LayerKind>[];
    final cleared = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            child: TimelineLayerControlsHeader(
              metrics: TimelineGridMetrics.defaults,
              legend: LayerLegendCallbacks(
                onShowAllLayers: () {},
                onHideAllLayers: () {},
                onToggleVisibilitySolo: () {},
                onSheetAllOn: () {},
                onSheetAllOff: () {},
                onClearMarkFilter: () => cleared.add('marks'),
                onClearAllFillReferences: () {},
                onMuteAllSe: () {},
                onUnmuteAllSe: () {},
                onBypassAllFx: () {},
                onEnableAllFx: () {},
                onToggleMarkFilter: marks.add,
                onToggleKindFilter: kinds.add,
                onToggleSheetOnlyFilter: () {},
                onToggleFxOnlyFilter: () {},
                onToggleFillReferenceOnlyFilter: () {},
                onPreviewLayersOpacity: (_, _) {},
                onCommitLayersOpacity: (_, _) {},
              ),
              showRowSolos: true,
              rowFilter: filter,
              marksInUse: marksInUse,
              kindsInUse: kindsInUse,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (marks: marks, kinds: kinds, cleared: cleared);
  }

  PanelFlyoutItem entry(WidgetTester tester, String key) => tester
      .widget<PopupMenuItem<PanelFlyoutItem>>(find.byKey(ValueKey<String>(key)))
      .value!;

  testWidgets('a mark no row carries any more is still listed, checked, and '
      'unchecking it lets it go', (tester) async {
    final heard = await pump(
      tester,
      filter: TimelineRowFilter(markColors: {layout}),
      marksInUse: {LayerMark.none},
    );
    await tester.tap(find.byKey(const ValueKey<String>('legend-mark')));
    await tester.pumpAndSettle();

    const key = 'legend-filter-mark-layout';
    expect(find.byKey(const ValueKey<String>(key)), findsOneWidget);
    expect(entry(tester, key).checked, isTrue);

    await tester.tap(find.byKey(const ValueKey<String>(key)));
    await tester.pumpAndSettle();
    expect(heard.marks, [layout]);
  });

  testWidgets('a kind whose last row went away is still listed, checked, and '
      'unchecking it lets it go', (tester) async {
    final heard = await pump(
      tester,
      filter: const TimelineRowFilter(kinds: {LayerKind.se}),
      kindsInUse: {LayerKind.animation},
    );
    await tester.tap(find.byKey(const ValueKey<String>('legend-kind')));
    await tester.pumpAndSettle();

    const key = 'legend-filter-kind-se';
    expect(find.byKey(const ValueKey<String>(key)), findsOneWidget);
    expect(entry(tester, key).checked, isTrue);

    await tester.tap(find.byKey(const ValueKey<String>(key)));
    await tester.pumpAndSettle();
    expect(heard.kinds, [LayerKind.se]);
  });

  testWidgets('the mark menu offers the filter\'s own way back — lit while a '
      'colour is held, and it is what the press asks for '
      '(clear-all-marks-meaning-Q1)', (tester) async {
    var heard = await pump(tester, filter: TimelineRowFilter.none);
    await tester.tap(find.byKey(const ValueKey<String>('legend-mark')));
    await tester.pumpAndSettle();
    const key = 'legend-mark-filter-clear';
    expect(
      entry(tester, key).enabled,
      isFalse,
      reason: 'nothing held, nothing to let go of',
    );
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    heard = await pump(
      tester,
      filter: TimelineRowFilter(markColors: {layout}),
      marksInUse: {layout},
    );
    await tester.tap(find.byKey(const ValueKey<String>('legend-mark')));
    await tester.pumpAndSettle();
    expect(entry(tester, key).enabled, isTrue);
    await tester.tap(find.byKey(const ValueKey<String>(key)));
    await tester.pumpAndSettle();
    expect(heard.cleared, ['marks']);
    expect(heard.marks, isEmpty, reason: 'not a toggle of one colour');
  });

  test('and the session\'s wiring lets go of the colours alone — the other '
      'facets stay as they were', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    TimelineRowFilter? set;
    sessionLegendCallbacks(
      session,
      rowFilter: TimelineRowFilter(
        markColors: {layout},
        kinds: const {LayerKind.se},
        fxOnly: true,
      ),
      onSetRowFilter: (filter) => set = filter,
    ).onClearMarkFilter();
    expect(set?.markColors, isEmpty);
    expect(set?.kinds, {LayerKind.se});
    expect(set?.fxOnly, isTrue);
  });

  testWidgets('nothing marked and nothing held: no colour list at all', (
    tester,
  ) async {
    await pump(
      tester,
      filter: TimelineRowFilter.none,
      marksInUse: {LayerMark.none},
    );
    await tester.tap(find.byKey(const ValueKey<String>('legend-mark')));
    await tester.pumpAndSettle();
    expect(
      find.byType(PopupMenuDivider),
      findsNothing,
      reason: 'an unlabelled stack has no colour to solo, so no header either',
    );
  });
}

/// What the legend asked of its host while a test pressed it.
typedef _Heard = ({
  List<LayerMark> marks,
  List<LayerKind> kinds,
  List<String> cleared,
});
