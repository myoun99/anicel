// 🗣️I-40 (유저 2026-09-18): 「버튼 전수감사해서 숏컷리스트에 등록. 타임라인
// 버튼같은거나. 설정의 패널 열기 닫기같은거든 뭐든 모든 버튼」.
//
// THE TIMELINE BAR'S MENU ROWS ARE ACTIONS, AND A KEY PRESSES THE ROW — on the
// panel being worked in: every row of the cut, layer and frame pills' menus
// that runs something names an action of the shortcut list, every such
// action has its row, and a key recorded for one does what the row does,
// only where the row can be pressed.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/main.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/pixel_clipboard_verb.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track_frame_range.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/services/cel_pixel_overwrite.dart' show CelPixelVerb;
import 'package:anicel/src/ui/cut_command_group.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerKindDisplayName;
import 'package:anicel/src/ui/timeline/timeline_bar_menus.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

const k = LogicalKeyboardKey.keyK;

/// The bar's menu rows, in the bar's order — 컷 · 레이어 · 프레임 · fx.
final barRows = [
  EditorActionIds.cutNew,
  EditorActionIds.cutDuplicate,
  EditorActionIds.cutCreateLinked,
  EditorActionIds.cutRename,
  EditorActionIds.cutEditNote,
  EditorActionIds.cutSettings,
  EditorActionIds.cutCanvasSize,
  EditorActionIds.cutConvertLinked,
  EditorActionIds.cutPinThumbnail,
  EditorActionIds.cutMoveLeft,
  EditorActionIds.cutMoveRight,
  EditorActionIds.cutCopyAeCamera,
  EditorActionIds.layerDuplicate,
  EditorActionIds.layerDetach,
  EditorActionIds.layerRasterize,
  EditorActionIds.layerStoryboard,
  for (final kind in addLayerKinds) addLayerKindActionId(kind),
  EditorActionIds.layerAttachFreeAbove,
  EditorActionIds.layerAttachFreeBelow,
  EditorActionIds.layerAttachSyncedAbove,
  EditorActionIds.layerAttachSyncedBelow,
  EditorActionIds.frameSelectRowSpan,
  for (final kind in EffectKind.values) addEffectActionId(kind),
];

/// The shared pill's colour edit list — actions since 2026-09-13 and I-55,
/// rows of the bar like the rest.
final colourEditRows = [
  for (final verb in CelPixelVerb.values) pixelVerbActionIdFor(verb),
  for (final verb in PixelClipboardVerb.values)
    pixelClipboardActionIdFor(verb),
];

Future<void> pumpApp(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1700, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const AnicelApp());
  await tester.pumpAndSettle();
}

EditorSessionManager sessionOf(WidgetTester tester) =>
    tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

BuildContext contextOf(WidgetTester tester) =>
    tester.element(find.byType(EditorWorkspace));

EditorShortcutBindings keys(WidgetTester tester) =>
    EditorShortcutScope.peek(contextOf(tester))!;

/// The bar's rows as the TIMELINE panel opens them.
List<PanelFlyoutItem> timelineRows(WidgetTester tester) => TimelineBarMenus(
  session: sessionOf(tester),
  panel: TimelineToolbarPanelContext(sessionOf(tester)),
).rows(contextOf(tester));

PanelFlyoutItem rowOf(List<PanelFlyoutItem> rows, String actionId) =>
    rows.firstWhere((row) => row.shortcuts.contains(actionId));

/// The action [pressKeyOf] last recorded [k] for.
String? _held;

/// Records [k] for [actionId] — ALONE: what this recorded it for before goes
/// back to no key, so one press is one action's — and presses it, once the
/// app has taken the recording in.
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

List<CutId> cutIdsOf(WidgetTester tester) => [
  for (final cut
      in sessionOf(tester).repository.requireProject().tracks.first.cuts)
    cut.id,
];

int cutsOf(WidgetTester tester) => cutIdsOf(tester).length;

int layersOf(WidgetTester tester) =>
    sessionOf(tester).activeCutOrNull!.layers.length;

void main() {
  group('the registry', () {
    test('holds the bar\'s menu rows under Timeline, in the bar\'s order, '
        'with the frame pill\'s switch between its row and the fx pill\'s '
        'rows', () {
      final timeline = [
        for (final definition in editorActionDefinitions)
          if (definition.category == 'Timeline') definition,
      ];
      expect(
        [
          for (final definition in timeline)
            if (definition.menuRow) definition.id,
        ],
        barRows,
      );
      final ids = [for (final definition in timeline) definition.id];
      final theSwitch = ids.indexOf(EditorActionIds.frameAutoCreate);
      expect(ids[theSwitch - 1], EditorActionIds.frameSelectRowSpan);
      expect(
        timeline[theSwitch].menuRow,
        isFalse,
        reason: 'a button of the pill, not a row of a menu',
      );
      expect(ids.sublist(theSwitch + 1), [
        for (final kind in EffectKind.values) addEffectActionId(kind),
      ]);
    });

    test('a kind of layer and a kind of effect are named by composing — '
        'the menu\'s name and the kind\'s, the fx row\'s own — in every '
        'language the two parts are said in', () {
      expect(
        editorActionLabel(addLayerKindActionId(LayerKind.animation)),
        'Add Layer: Animation',
      );
      expect(
        addLayerKindActionLabel(LayerKind.animation, AppLanguage.ko),
        '레이어 추가: 애니메이션',
      );
      expect(
        addLayerKindActionLabel(LayerKind.folder, AppLanguage.ja),
        'レイヤーを追加: フォルダー',
      );
      expect(
        editorActionLabel(addEffectActionId(EffectKind.blur)),
        'Add Blur',
      );
      expect(
        addEffectActionLabel(EffectKind.blur, AppLanguage.ko),
        '흐림 효과 추가',
      );
    });

    test('…and read in the program\'s language wherever a name is asked', () {
      addTearDown(() => AppText.settings.value = const AppLanguageSettings());
      AppText.settings.value = const AppLanguageSettings(
        programLanguage: AppLanguage.ko,
      );

      expect(
        editorActionLabel(addLayerKindActionId(LayerKind.animation)),
        '레이어 추가: 애니메이션',
      );
      expect(layerKindDisplayName(LayerKind.folder), '폴더');
      expect(
        editorActionLabel(addEffectActionId(EffectKind.blur)),
        '흐림 효과 추가',
      );
    });

    test('⛔a composed name\'s English is the registry\'s own wording — one '
        'composer says both', () {
      final composed = [
        for (final definition in editorActionDefinitions)
          if (definition.composedName != null) definition,
      ];
      expect(
        composed.map((definition) => definition.id),
        containsAll([
          addLayerKindActionId(LayerKind.se),
          addEffectActionId(EffectKind.keepColor),
          'tool-select-lasso',
        ]),
        reason: '⛔premise: the families are composed',
      );
      for (final definition in composed) {
        expect(
          definition.label,
          definition.composedName!(AppLanguage.en),
          reason: definition.id,
        );
      }
    });

    test('⛔the add menu\'s kinds are the list its actions are made of — the '
        'camera and the transition are in neither', () {
      expect(addLayerKinds, hasLength(7));
      expect(addLayerKinds, isNot(contains(LayerKind.camera)));
      expect(addLayerKinds, isNot(contains(LayerKind.transition)));
      expect(
        File('lib/src/ui/timeline/timeline_bar_menus.dart').readAsStringSync(),
        contains('for (final kind in addLayerKinds)'),
      );
    });

    test('the colour edit list\'s seven are menu rows too — the third list '
        'on the one rule', () {
      expect(colourEditRows, hasLength(7), reason: '⛔premise');
      for (final id in colourEditRows) {
        expect(
          editorActionDefinitions
              .singleWhere((definition) => definition.id == id)
              .menuRow,
          isTrue,
          reason: id,
        );
      }
    });

    test('⛔the shell keeps no road of its own to what a row runs', () {
      // 저장 had one (I-40 ②), and the colour edit list had two: the row's
      // gate and its verb written a second time in the shell's dispatch,
      // which is the copy that drifts. A key presses the ROW.
      final shell = File('lib/src/ui/home_page.dart').readAsStringSync();
      expect(shell, contains('pressFlyoutRow('), reason: '⛔LIVENESS');
      // The verbs the bar's rows run, by the names the rows call them by.
      for (final verb in const [
        'runPixelVerb(',
        'runPixelClipboardVerb(',
        'createCut',
        'duplicateActiveCut',
        'createLinkedCutFromActiveCut',
        'renameActiveCutWithDialog',
        'toggleActiveCutThumbnailFrame',
        'moveActiveCutLeft',
        'moveActiveCutRight',
        'copyCameraAeKeyframes',
        'duplicateActiveLayer',
        'detachActiveLayer',
        'rasterizeActiveRow',
        'toggleTargetLayerKind',
        'addAttachedLayer',
        'selectRowSpan',
        'addLayerOfKind',
        'addEffectToActiveLayer',
      ]) {
        expect(shell, isNot(contains(verb)), reason: verb);
      }
    });

    test('none ships with a key — nobody named one', () {
      for (final id in [...barRows, EditorActionIds.frameAutoCreate]) {
        expect(
          editorActionDefinitions
              .singleWhere((definition) => definition.id == id)
              .defaultActivators,
          isEmpty,
          reason: id,
        );
      }
    });
  });

  group('the bar\'s menus', () {
    testWidgets('🚨every one of those actions has its row, and every row '
        'that runs something names an action — but the colour labels', (
      tester,
    ) async {
      await pumpApp(tester);
      final rows = timelineRows(tester);
      final named = {for (final row in rows) ...row.shortcuts};

      expect({...barRows, ...colourEditRows}.difference(named), isEmpty);
      expect(named.difference({...barRows, ...colourEditRows}), isEmpty);

      final silent = [
        for (final row in rows)
          if (row.shortcuts.isEmpty &&
              row.onSelected != null &&
              row.submenuBuilder == null)
            row.keyValue,
      ];
      expect(silent, isNotEmpty, reason: '⛔premise: the labels are there');
      // ⚠️A colour label is a choice out of a list, not a command — the
      // one family of rows here that is no action. ↩️The kinds of layer and
      // of effect stood beside it until their names were composed (「레이어
      // 추가: 애니메이션」).
      expect(
        silent.where((key) => !key.startsWith('layer-mark-option-')),
        isEmpty,
      );
    });

    testWidgets('a row wears its action\'s name, and its key', (tester) async {
      await pumpApp(tester);
      keys(tester).setActivators(EditorActionIds.cutRename, const [
        SingleActivator(k, control: true),
      ]);
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('cut-menu-button')).first,
      );
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey<String>('rename-cut-button'));
      expect(
        find.descendant(of: row, matching: find.text('Rename cut…')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('Ctrl+K')),
        findsOneWidget,
      );
    });

    testWidgets('one verb reached from two lists is ONE action: both rows '
        'of 「컷 복제」 name it and read alike', (tester) async {
      await pumpApp(tester);
      final rows = timelineRows(tester)
          .where((row) => row.shortcuts.contains(EditorActionIds.cutDuplicate))
          .toList();
      expect(rows.map((row) => row.keyValue), [
        'duplicate-cut-button',
        'add-cut-duplicate',
      ]);
      expect(rows.map((row) => row.label).toSet(), {'Duplicate cut'});
    });

    testWidgets('the thumbnail switch says one name, and its check says '
        'which way it stands', (tester) async {
      await pumpApp(tester);
      final session = sessionOf(tester);
      PanelFlyoutItem row() =>
          rowOf(timelineRows(tester), EditorActionIds.cutPinThumbnail);
      final before = row();
      expect(before.label, 'Pin thumbnail frame');
      expect(before.checked, session.cutVerbs.isActiveCutThumbnailPinnedHere);

      before.onSelected!();
      await tester.pumpAndSettle();

      expect(row().label, 'Pin thumbnail frame');
      expect(row().checked, isNot(before.checked));
    });
  });

  group('a key', () {
    testWidgets('opens the window its row opens', (tester) async {
      await pumpApp(tester);
      final field = find.byKey(const ValueKey<String>('rename-cut-text-field'));
      expect(field, findsNothing);
      await pressKeyOf(tester, EditorActionIds.cutRename);
      expect(field, findsOneWidget);
    });

    testWidgets('makes what its row makes: a layer, and a cut', (tester) async {
      await pumpApp(tester);
      expect(
        rowOf(timelineRows(tester), EditorActionIds.layerDuplicate).enabled,
        isTrue,
        reason: '⛔premise: a layer is in hand',
      );
      final layers = layersOf(tester);
      await pressKeyOf(tester, EditorActionIds.layerDuplicate);
      expect(layersOf(tester), layers + 1);

      final cuts = cutsOf(tester);
      await pressKeyOf(tester, EditorActionIds.cutNew);
      expect(cutsOf(tester), cuts + 1);
    });

    testWidgets('adds a layer of ITS kind — not the one the pill\'s ＋ '
        'adds', (tester) async {
      await pumpApp(tester);
      final layers = layersOf(tester);

      await pressKeyOf(tester, addLayerKindActionId(LayerKind.folder));

      final after = sessionOf(tester).activeCutOrNull!.layers;
      expect(after, hasLength(layers + 1));
      expect(
        after.where((layer) => layer.kind == LayerKind.folder),
        hasLength(1),
      );
    });

    testWidgets('⛔adds no layer of a kind the panel being worked in cannot '
        'add: from the storyboard, the animation kind\'s key does '
        'nothing', (tester) async {
      await pumpApp(tester);
      final session = sessionOf(tester);
      final layers = layersOf(tester);
      session.claimStoryboardRow();
      await tester.pumpAndSettle();
      expect(
        rowOf(
          TimelineBarMenus(
            session: session,
            panel: StoryboardToolbarPanelContext(session),
          ).rows(contextOf(tester)),
          addLayerKindActionId(LayerKind.animation),
        ).enabled,
        isFalse,
        reason: '⛔premise: the storyboard shows that kind dim',
      );

      await pressKeyOf(tester, addLayerKindActionId(LayerKind.animation));

      expect(layersOf(tester), layers);
      expect(tester.takeException(), isNull);
    });

    testWidgets('adds its effect to the layer in hand', (tester) async {
      await pumpApp(tester);
      final session = sessionOf(tester);
      expect(
        rowOf(timelineRows(tester), addEffectActionId(EffectKind.blur)).enabled,
        isTrue,
        reason: '⛔premise: the layer in hand takes effects',
      );
      expect(session.activeLayer!.effects, isEmpty);

      await pressKeyOf(tester, addEffectActionId(EffectKind.blur));

      expect(
        [for (final effect in session.activeLayer!.effects) effect.kind],
        [EffectKind.blur],
      );
    });

    testWidgets('🚨presses the row of the panel being worked in: the layer '
        'menu is the timeline\'s, and from the storyboard its key does '
        'nothing', (tester) async {
      await pumpApp(tester);
      final session = sessionOf(tester);
      expect(session.workingPanel, WorkingPanel.timeline, reason: '⛔premise');
      final layers = layersOf(tester);

      session.claimStoryboardRow();
      await tester.pumpAndSettle();
      expect(session.workingPanel, WorkingPanel.storyboard);
      expect(
        rowOf(
          TimelineBarMenus(
            session: session,
            panel: StoryboardToolbarPanelContext(session),
          ).rows(contextOf(tester)),
          EditorActionIds.layerDuplicate,
        ).enabled,
        isFalse,
        reason: '⛔premise: the storyboard\'s layer menu shows the row dim',
      );
      await pressKeyOf(tester, EditorActionIds.layerDuplicate);
      expect(layersOf(tester), layers);
      expect(tester.takeException(), isNull);
    });

    testWidgets('⛔does nothing where its row is dim', (tester) async {
      await pumpApp(tester);
      // Two cuts, standing on the first: it has nowhere to step left — and a
      // key that pressed anyway would have a cut to move.
      sessionOf(tester).cutVerbs.createCut();
      await tester.pumpAndSettle();
      final order = cutIdsOf(tester);
      expect(order, hasLength(2), reason: '⛔premise');
      sessionOf(tester).selectCut(order.first);
      await tester.pumpAndSettle();
      expect(
        rowOf(timelineRows(tester), EditorActionIds.cutMoveLeft).enabled,
        isFalse,
        reason: '⛔premise: the first cut has nowhere to step left',
      );
      expect(
        rowOf(timelineRows(tester), EditorActionIds.cutMoveRight).enabled,
        isTrue,
        reason: '⛔premise: and the same key on the other row would move it',
      );

      await pressKeyOf(tester, EditorActionIds.cutMoveLeft);
      expect(cutIdsOf(tester), order);
      expect(tester.takeException(), isNull);

      await pressKeyOf(tester, EditorActionIds.cutMoveRight);
      expect(cutIdsOf(tester), order.reversed.toList(), reason: '⛔LIVENESS');
    });

    testWidgets('flips the frame pill\'s switch, as its button does', (
      tester,
    ) async {
      await pumpApp(tester);
      bool on() => AppInput.settings.value.autoCreateFrameOnDraw;
      final before = on();
      // The setting is app-wide; whatever happens below, the next test finds
      // it as this one did. (On the notifier: the app is gone by teardown.)
      addTearDown(
        () => AppInput.settings.value = AppInput.settings.value.copyWith(
          autoCreateFrameOnDraw: before,
        ),
      );

      await pressKeyOf(tester, EditorActionIds.frameAutoCreate);
      expect(on(), !before);

      final button = find
          .byKey(const ValueKey<String>('auto-frame-toggle-button'))
          .first;
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(on(), before, reason: 'the button and the key flip one switch');
    });
  });

  group('the pills\' buttons that are actions', () {
    testWidgets('wear the action\'s name and show a key recorded for it — '
        'the cut pill\'s ＋ and the frame pill\'s switch', (tester) async {
      await pumpApp(tester);
      String tooltip(String key) => tester
          .widget<AppIconButtonFace>(find.byKey(ValueKey<String>(key)).first)
          .tooltip;
      expect(tooltip('new-cut-button'), 'New cut');
      expect(
        tooltip('auto-frame-toggle-button'),
        'Make a frame where there is none',
      );

      keys(tester)
        ..setActivators(EditorActionIds.cutNew, const [
          SingleActivator(k, control: true),
        ])
        ..setActivators(EditorActionIds.frameAutoCreate, const [
          SingleActivator(k, alt: true),
        ]);
      await tester.pumpAndSettle();

      expect(tooltip('new-cut-button'), 'New cut (Ctrl+K)');
      expect(
        tooltip('auto-frame-toggle-button'),
        'Make a frame where there is none (Alt+K)',
      );
    });
  });

  group('the cut pill\'s ＋', () {
    testWidgets('and its band\'s first row are one action, lit together and '
        'dim together', (tester) async {
      await pumpApp(tester);
      final session = sessionOf(tester);
      PanelFlyoutItem newCut() => cutAddEntries(
        session,
      ).whereType<PanelFlyoutItem>().firstWhere(
        (row) => row.shortcuts.contains(EditorActionIds.cutNew),
      );
      expect(session.cutPlacement.canCreateCut, isTrue, reason: '⛔premise');
      expect(newCut().enabled, isTrue);

      // A range over the cut that is there is nowhere to make one.
      final track = session.repository.requireProject().tracks.first;
      session.trackFrameRangeSelection.value = TrackFrameRangeSelection(
        trackId: track.id,
        anchorRow: TrackRowAddress(track.id),
        startFrame: 0,
        endFrameExclusive: 2,
      );
      await tester.pumpAndSettle();
      expect(session.cutPlacement.canCreateCut, isFalse, reason: '⛔premise');
      expect(newCut().enabled, isFalse);

      final cuts = cutsOf(tester);
      await pressKeyOf(tester, EditorActionIds.cutNew);
      expect(cutsOf(tester), cuts, reason: 'and the key is the row\'s');
    });
  });
}
