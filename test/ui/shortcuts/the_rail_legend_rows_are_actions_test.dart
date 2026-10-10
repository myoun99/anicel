// 🗣️I-40 (유저 2026-09-18): 「버튼 전수감사해서 숏컷리스트에 등록 … 뭐든 모든
// 버튼」; asked how far (I-40-Q1, 10-08): the editing screen's command
// buttons and menu rows.
//
// THE RAIL LEGEND'S ROWS ARE ACTIONS, AND A KEY PRESSES THE ROW — the row the
// header of the panel being worked in opens, counted on that panel's own
// rows: every row the legend's columns can show names an action, every such
// action has its row, and a key recorded for one does what the row does,
// only where the row is shown.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_shelf.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/timeline_grid_metrics.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_header.dart';
import 'package:anicel/src/ui/timeline/timeline_legend_menus.dart';

const k = LogicalKeyboardKey.keyK;

/// Every verb a legend can be handed, none doing anything.
LayerLegendCallbacks everyVerb() => LayerLegendCallbacks(
  onShowAllLayers: () {},
  onHideAllLayers: () {},
  onToggleVisibilitySolo: () {},
  onSheetAllOn: () {},
  onSheetAllOff: () {},
  onClearMarkFilter: () {},
  onClearAllFillReferences: () {},
  onMuteAllSe: () {},
  onUnmuteAllSe: () {},
  onBypassAllFx: () {},
  onEnableAllFx: () {},
  onToggleMarkFilter: (_) {},
  onToggleKindFilter: (_) {},
  onToggleSheetOnlyFilter: () {},
  onToggleFxOnlyFilter: () {},
  onToggleFillReferenceOnlyFilter: () {},
  onPreviewLayersOpacity: (_, _) {},
  onCommitLayersOpacity: (_, _) {},
  onToggleOnionSkinForDisplayed: () {},
  onRevealOnionSkinPanel: () {},
  onSetBlendModeForDisplayed: (_, _) {},
);

/// The legend at its fullest: every column wired, every label and every kind
/// on the rows.
TimelineLegendMenus fullest() => TimelineLegendMenus(
  legend: everyVerb(),
  onToggleSection: (_) {},
  marksInUse: everyLayerMark().toSet(),
  kindsInUse: LayerKind.values.toSet(),
  displayedLayerIds: () => const {},
);

Future<void> pumpApp(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1700, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const AnicelApp());
  await tester.pumpAndSettle();
}

EditorSessionManager sessionOf(WidgetTester tester) =>
    tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

EditorShortcutBindings keys(WidgetTester tester) => EditorShortcutScope.peek(
  tester.element(find.byType(EditorWorkspace)),
)!;

/// The action [pressKeyOf] last recorded [k] for.
String? _held;

/// Records [k] for [actionId] — alone — and presses it.
Future<void> pressKeyOf(WidgetTester tester, String actionId) async {
  if (_held case final before? when before != actionId) {
    keys(tester).resetAction(before);
  }
  _held = actionId;
  keys(tester).setActivators(actionId, const [SingleActivator(k)]);
  await tester.pump();
  await tester.sendKeyEvent(k);
  await tester.pumpAndSettle();
}

Future<void> workIn(WidgetTester tester, WorkingPanel panel) async {
  await tester.tap(
    find.byKey(
      ValueKey<String>(switch (panel) {
        WorkingPanel.timeline => 'timeline-mode-timeline-button',
        WorkingPanel.storyboard => 'timeline-mode-storyboard-button',
      }),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => _held = null);

  group('the registry', () {
    test('🚨every row the legend can open names one action of the registry, '
        'and every action of the legend has its row', () {
      final registry = {
        for (final definition in editorActionDefinitions) definition.id,
      };
      final rows = fullest().rows();
      expect(rows, hasLength(greaterThan(40)), reason: '⛔premise: the rows');
      for (final row in rows) {
        expect(row.shortcuts, hasLength(1), reason: row.keyValue);
        expect(registry, contains(row.shortcuts.single), reason: row.keyValue);
      }
      expect(
        {
          for (final definition in editorActionDefinitions)
            if (definition.shelf == ShortcutShelf.layerHeader) definition.id,
        },
        {
          for (final row in rows)
            if (row.shortcuts.single != EditorActionIds.layerVisibilitySolo)
              row.shortcuts.single,
        },
      );
    });

    test('they stand on the layer header\'s own shelf, as menu rows, '
        'and none ships with a key — nobody named one', () {
      final header = [
        for (final definition in editorActionDefinitions)
          if (definition.shelf == ShortcutShelf.layerHeader) definition,
      ];
      expect(header, isNotEmpty);
      for (final definition in header) {
        expect(definition.menuRow, isTrue, reason: definition.id);
        expect(definition.defaultActivators, isEmpty, reason: definition.id);
      }
      expect(
        AppStrings.of(AppLanguage.ko).shortcutShelfName('layerHeader', ''),
        '레이어 머리',
      );
    });

    test('a row is named by its own words where they say what it does, and '
        'with its column first where they need one', () {
      expect(
        editorActionLabel(RailLegendActionIds.sheetAllOff),
        'All off timesheet',
      );
      expect(
        editorActionLabel(RailLegendActionIds.eyeHideAll),
        'Visibility column: Hide all',
      );
      expect(
        editorActionLabel(
          railSoloMarkActionId(const LayerMark(process: LayerProcess.layout)),
        ),
        'Solo color: Layout',
      );
      expect(
        editorActionLabel(railSoloKindActionId(LayerKind.animation)),
        'Solo kind: Animation',
      );
      expect(
        editorActionLabel(railBlendActionId(LayerBlendMode.multiply)),
        'All displayed layers: Multiply',
      );
    });

    test('…in the program\'s language', () {
      addTearDown(() => AppText.settings.value = const AppLanguageSettings());
      AppText.settings.value = const AppLanguageSettings(
        programLanguage: AppLanguage.ko,
      );
      expect(
        editorActionLabel(RailLegendActionIds.eyeHideAll),
        '표시 열: 모두 숨기기',
      );
      expect(
        editorActionLabel(RailLegendActionIds.onionOnDisplayed),
        '표시 중인 레이어의 어니언 스킨 켜기/끄기',
      );
    });
  });

  group('a key presses the row the working panel\'s header shows', () {
    testWidgets('on the timeline: the eye column hides every layer, and '
        'shows them again', (tester) async {
      await pumpApp(tester);
      final session = sessionOf(tester);
      List<bool> eyes() => [
        for (final layer in session.activeCutOrNull!.layers)
          if (layer.kind != LayerKind.camera) layer.isVisible,
      ];
      expect(eyes(), everyElement(isTrue), reason: '⛔premise');

      await pressKeyOf(tester, RailLegendActionIds.eyeHideAll);
      expect(eyes(), everyElement(isFalse));

      await pressKeyOf(tester, RailLegendActionIds.eyeShowAll);
      expect(eyes(), everyElement(isTrue));
    });

    testWidgets('a kind on the rows is soloed and let go by its key; a kind '
        'on no row is no row, and its key does nothing', (tester) async {
      await pumpApp(tester);
      final session = sessionOf(tester);
      Set<LayerKind> soloed() => session.railView.rowFilter.value.kinds;

      await pressKeyOf(tester, railSoloKindActionId(LayerKind.animation));
      expect(soloed(), {LayerKind.animation});
      await pressKeyOf(tester, railSoloKindActionId(LayerKind.animation));
      expect(soloed(), isEmpty);

      final onTheRows = {
        for (final layer in session.activeCutOrNull!.layers) layer.kind,
      };
      final absent = [
        LayerKind.folder,
        LayerKind.adjustment,
        LayerKind.image,
      ].firstWhere((kind) => !onTheRows.contains(kind));
      await pressKeyOf(tester, railSoloKindActionId(absent));
      expect(
        soloed(),
        isEmpty,
        reason: 'the kind column lists the kinds on the rows — there is no '
            '${absent.name} row for the key to press',
      );
    });

    testWidgets('on the storyboard its own header answers — the onion, a '
        'column that rail does not have, answers nothing there', (
      tester,
    ) async {
      await pumpApp(tester);
      final session = sessionOf(tester);
      expect(session.onionSkin.displayedLayersOnionSkinEnabled, isFalse);

      await workIn(tester, WorkingPanel.storyboard);
      expect(session.workingPanel, WorkingPanel.storyboard);
      await pressKeyOf(tester, RailLegendActionIds.onionOnDisplayed);
      expect(session.onionSkin.displayedLayersOnionSkinEnabled, isFalse);

      // …while a column it has answers its key there.
      await pressKeyOf(tester, RailLegendActionIds.eyeHideAll);
      expect(
        [
          for (final layer in session.activeCutOrNull!.layers)
            if (layer.kind != LayerKind.camera) layer.isVisible,
        ],
        everyElement(isFalse),
      );
      await pressKeyOf(tester, RailLegendActionIds.eyeShowAll);

      await workIn(tester, WorkingPanel.timeline);
      await pressKeyOf(tester, RailLegendActionIds.onionOnDisplayed);
      expect(
        session.onionSkin.displayedLayersOnionSkinEnabled,
        isTrue,
        reason: '⛔premise: on the timeline the same key does press the row',
      );
    });

    testWidgets('a header that goes takes its rows with it — stood up as the '
        'x-sheet, whose corner opens no menu, the timeline has none for a '
        'key, and laid down again it has them back', (tester) async {
      await pumpApp(tester);
      final session = sessionOf(tester);
      final turn = find.byKey(
        const ValueKey<String>('timeline-orientation-toggle-button'),
      );
      expect(
        session.railLegends.rowsOf(WorkingPanel.timeline),
        isNotEmpty,
        reason: '⛔premise: the timeline\'s header told its rows',
      );

      await tester.tap(turn);
      await tester.pumpAndSettle();
      expect(session.railLegends.rowsOf(WorkingPanel.timeline), isEmpty);
      final hidden = [
        for (final layer in session.activeCutOrNull!.layers) layer.isVisible,
      ];
      await pressKeyOf(tester, RailLegendActionIds.eyeHideAll);
      expect(
        [for (final layer in session.activeCutOrNull!.layers) layer.isVisible],
        hidden,
        reason: 'no row is shown, so the key presses none',
      );

      await tester.tap(turn);
      await tester.pumpAndSettle();
      expect(session.railLegends.rowsOf(WorkingPanel.timeline), isNotEmpty);
    });
  });

  // Found reading the header for this round (10-09): the lane toggle's and
  // the SE mute's tooltips, and the onion row, were English in every
  // language.
  testWidgets('the header\'s two direct buttons and its onion row speak the '
      'program language', (tester) async {
    addTearDown(() => AppText.settings.value = const AppLanguageSettings());
    AppText.settings.value = const AppLanguageSettings(
      programLanguage: AppLanguage.ko,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            child: TimelineLayerControlsHeader(
              metrics: TimelineGridMetrics.defaults,
              optionalColumns: (onion: true, blend: false),
              legend: everyVerb(),
              onExpandAllLanes: () {},
              onCollapseAllLanes: () {},
            ),
          ),
        ),
      ),
    );
    String? tooltipOver(String key) => tester
        .widget<Tooltip>(
          find
              .ancestor(
                of: find.byKey(ValueKey<String>(key)),
                // AppTooltip IS a Tooltip — a subclass, which `byType` would
                // not match.
                matching: find.byWidgetPredicate((widget) => widget is Tooltip),
              )
              .first,
        )
        .message;
    expect(tooltipOver('legend-lanes-toggle'), '모든 레이어 펼치기');
    expect(tooltipOver('legend-mute'), 'SE 모두 음소거');
    expect(
      [
        for (final row in tester
            .widget<TimelineLayerControlsHeader>(
              find.byType(TimelineLayerControlsHeader),
            )
            .menus
            .rows())
          if (row.keyValue == 'legend-onion-toggle-displayed') row.label,
      ],
      ['표시 중인 레이어에 어니언 스킨 적용'],
    );
  });
}
