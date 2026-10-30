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
import 'package:anicel/src/ui/dialogs/convert_to_linked_cut_dialog.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart';
import 'package:anicel/src/ui/shortcuts/shortcut_shelf.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerKindDisplayName;
import 'package:anicel/src/ui/timeline/timeline_bar_menus.dart';
import 'package:anicel/src/ui/timeline/toolbar_panel_context.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/command_pill.dart' show StrapIconButton;
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

import '../../helpers/app_shortcuts.dart';

const k = LogicalKeyboardKey.keyK;

/// The bar's menu rows, in the bar's order — 컷 · 레이어 · 프레임 · fx.
final barRows = [
  EditorActionIds.cutEditNote,
  EditorActionIds.cutSettings,
  EditorActionIds.cutCanvasSize,
  EditorActionIds.cutCreateLinked,
  EditorActionIds.cutConvertLinked,
  EditorActionIds.layerDetach,
  EditorActionIds.layerRasterize,
  EditorActionIds.layerStoryboard,
  for (final kind in addLayerKinds) addLayerKindActionId(kind),
  EditorActionIds.layerAttachFreeAbove,
  EditorActionIds.layerAttachFreeBelow,
  EditorActionIds.layerAttachSyncedAbove,
  EditorActionIds.layerAttachSyncedBelow,
  EditorActionIds.frameSelectRowSpan,
  for (final kind in effectKindsAddedAlone) addEffectActionId(kind),
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
    test('holds the bar\'s menu rows on its pills, in the bar\'s order, '
        'with the frame pill\'s switch between its row and the fx pill\'s '
        'rows', () {
      const pills = {
        ShortcutShelf.cutPill,
        ShortcutShelf.layerPill,
        ShortcutShelf.framePill,
        ShortcutShelf.fxPill,
      };
      final timeline = [
        for (final definition in editorActionDefinitions)
          if (pills.contains(definition.shelf)) definition,
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
        for (final kind in effectKindsAddedAlone) addEffectActionId(kind),
      ]);
    });

    test('a kind of layer and a kind of effect are named by composing — '
        'the menu\'s name and the kind\'s, the fx row\'s own — in every '
        'language the two parts are said in', () {
      expect(
        editorActionLabel(addLayerKindActionId(LayerKind.animation)),
        'New Layer: Animation',
      );
      expect(
        addLayerKindActionLabel(LayerKind.animation, AppLanguage.ko),
        '새 레이어: 애니메이션',
      );
      expect(
        addLayerKindActionLabel(LayerKind.folder, AppLanguage.ja),
        '新規レイヤー: フォルダー',
      );
      expect(
        editorActionLabel(addEffectActionId(EffectKind.blur)),
        'Add Gaussian Blur',
      );
      expect(
        addEffectActionLabel(EffectKind.blur, AppLanguage.ko),
        '가우시안 흐림 추가',
      );
    });

    test('…and read in the program\'s language wherever a name is asked', () {
      addTearDown(() => AppText.settings.value = const AppLanguageSettings());
      AppText.settings.value = const AppLanguageSettings(
        programLanguage: AppLanguage.ko,
      );

      expect(
        editorActionLabel(addLayerKindActionId(LayerKind.animation)),
        '새 레이어: 애니메이션',
      );
      expect(layerKindDisplayName(LayerKind.folder), '폴더');
      expect(
        editorActionLabel(addEffectActionId(EffectKind.blur)),
        '가우시안 흐림 추가',
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
          addEffectActionId(EffectKind.colorKey),
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

    test('the colour edit list\'s nine are menu rows too — the third list '
        'on the one rule', () {
      expect(colourEditRows, hasLength(9), reason: '⛔premise');
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
        'createLinkedCutFromActiveCut',
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

    // 🗣️I-90 (유저 2026-10-10): 「픽셀 잘라내기 버튼 신설. 복사버튼 위」 ·
    // 「픽셀비우기 버튼 위치가 색관련 버튼이랑 같이있는게 신경쓰임. 아래
    // 픽셀쪽으로 이동. 위치는 해당항목 제일위」 — and I-13-Q1 (10-16): 2치화
    // 「픽셀 묶음에서 「픽셀 비우기」 바로 아래」.
    testWidgets('the colour edit list: the colour verbs, then — past the '
        'divider — 픽셀 비우기 heading the pixel rows with 2치화 under it, '
        '픽셀 잘라내기 over 픽셀 복사; and the shortcut list in the same '
        'order', (tester) async {
      await pumpApp(tester);
      final order = [
        for (final entry in TimelineBarMenus(
          session: sessionOf(tester),
          panel: TimelineToolbarPanelContext(sessionOf(tester)),
        ).colourEdit())
          switch (entry) {
            PanelFlyoutItem(:final shortcuts) => shortcuts.single,
            PanelFlyoutDivider() => '—',
            _ => null,
          },
      ].nonNulls.toList();

      expect(order, [
        EditorActionIds.editReplaceColour,
        EditorActionIds.editDeleteColour,
        EditorActionIds.editKeepColour,
        '—',
        EditorActionIds.editClearPixels,
        EditorActionIds.editBinarize,
        EditorActionIds.editCutPixels,
        EditorActionIds.editCopyPixels,
        EditorActionIds.editPastePixelsAbove,
        EditorActionIds.editPastePixelsBelow,
      ]);
      expect(
        [
          for (final definition in editorActionDefinitions)
            if (definition.shelf == ShortcutShelf.colourEdit) definition.id,
        ],
        [
          for (final id in order)
            if (id != '—') id,
        ],
        reason: 'the shortcut list shows the rows in the list\'s order',
      );
    });

    testWidgets('a row wears its action\'s name, and its key', (tester) async {
      await pumpApp(tester);
      keys(tester).setActivators(EditorActionIds.cutEditNote, const [
        SingleActivator(k, control: true),
      ]);
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('cut-menu-button')).first,
      );
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey<String>('edit-cut-note-button'));
      expect(
        find.descendant(of: row, matching: find.text('Edit cut note')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('Ctrl+K')),
        findsOneWidget,
      );
    });

    // 🗣️F-455 (유저 2026-10-23): 「공용알약에 복제 버튼 만들고 레이어랑
    // 컷버튼의 레이어복제/컷복제 삭제」. ↩️F-379 had left 「컷 복제」 the cut
    // button's row alone.
    testWidgets('⛔no row of the bar duplicates a cut or a layer — 복제 is '
        'the shared pill\'s button', (tester) async {
      await pumpApp(tester);
      final session = sessionOf(tester);
      final duplicates = [
        for (final row in timelineRows(tester))
          if (row.onSelected == session.cutVerbs.duplicateActiveCut ||
              row.onSelected == session.layerVerbs.duplicateActiveLayer)
            row.keyValue,
      ];
      expect(duplicates, isEmpty);
      expect(
        find.byKey(const ValueKey<String>('shared-duplicate-button')),
        findsWidgets,
        reason: '⛔LIVENESS: the one door is there',
      );
    });
  });

  group('a key', () {
    testWidgets('makes what its row makes: a cut', (tester) async {
      await pumpApp(tester);
      expect(
        rowOf(timelineRows(tester), EditorActionIds.cutCreateLinked).enabled,
        isTrue,
        reason: '⛔premise: a cut is in hand',
      );
      final cuts = cutsOf(tester);
      await pressKeyOf(tester, EditorActionIds.cutCreateLinked);
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
      List<LayerKind> kinds() => [
        for (final layer in session.activeCutOrNull!.layers) layer.kind,
      ];
      final before = kinds();
      expect(
        rowOf(timelineRows(tester), EditorActionIds.layerStoryboard).enabled,
        isTrue,
        reason: '⛔premise: on the timeline the row would turn the layer',
      );

      session.claimStoryboardRow();
      await tester.pumpAndSettle();
      expect(session.workingPanel, WorkingPanel.storyboard);
      expect(
        rowOf(
          TimelineBarMenus(
            session: session,
            panel: StoryboardToolbarPanelContext(session),
          ).rows(contextOf(tester)),
          EditorActionIds.layerStoryboard,
        ).enabled,
        isFalse,
        reason: '⛔premise: the storyboard\'s layer menu shows the row dim',
      );
      await pressKeyOf(tester, EditorActionIds.layerStoryboard);
      expect(kinds(), before);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opens the window its row opens — and ⛔nothing where its row '
        'is dim', (tester) async {
      await pumpApp(tester);
      final window = find.byType(ConvertToLinkedCutDialog);
      // One cut: nothing to borrow the pictures from.
      expect(cutIdsOf(tester), hasLength(1), reason: '⛔premise');
      expect(
        rowOf(timelineRows(tester), EditorActionIds.cutConvertLinked).enabled,
        isFalse,
        reason: '⛔premise: the row is dim',
      );

      await pressKeyOf(tester, EditorActionIds.cutConvertLinked);
      expect(window, findsNothing);
      expect(tester.takeException(), isNull);

      sessionOf(tester).cutVerbs.createCut();
      await tester.pumpAndSettle();
      expect(
        rowOf(timelineRows(tester), EditorActionIds.cutConvertLinked).enabled,
        isTrue,
        reason: '⛔premise: a second cut lights it',
      );
      await pressKeyOf(tester, EditorActionIds.cutConvertLinked);
      expect(window, findsOneWidget, reason: '⛔LIVENESS');
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
      expect(tooltip('auto-frame-toggle-button'), 'Auto-create Frames');

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
        'Auto-create Frames (Alt+K)',
      );
    });

    // 🗣️I-58 (유저 2026-10-18): 「컷 추가버튼은 새 컷이고 레이어는 레이어
    // 추가고 프레임은 추가임 … 통일(레이어 추가 이런식으로 ㅁㅁ 추가. ㅁㅁ
    // 삭제)하고, x버튼은 비우기 … 마크 점은 중간나누기 마크」 — then 「ㅁㅁ
    // 추가말고 새 ㅁㅁ로 하자」. ↩️The frame pill's ＋ × ● each wore a string
    // of their own.
    testWidgets('the frame pill\'s ＋ × ● and the n-koma ● wear their '
        'actions\' names too', (tester) async {
      await pumpApp(tester);
      // Shift+I is anicel's. Clip Studio's preset, which an install opens
      // on, takes New Frame from TVPaint's `I`, a key Clip Studio keeps for
      // its own, and so leaves it without one (F-417-Q2, bf542a298).
      await useAnicelKeys(tester);
      String tooltip(String key) => tester
          .widget<AppIconButtonFace>(find.byKey(ValueKey<String>(key)).first)
          .tooltip;
      expect(tooltip('new-frame-button'), 'New Frame (Shift+I)');
      expect(tooltip('blank-exposure-button'), 'Clear');
      expect(tooltip('toggle-mark-one-button'), 'In-between Mark 1');
      expect(tooltip('toggle-mark-button'), 'In-between Mark 2');
      expect(tooltip('mark-every-button'), 'Auto-add In-between Marks');
    });
  });

  // 🗣️F-455 (유저 2026-10-23): 「컷 종류버튼의 새 컷은 +버튼이랑 겹치니
  // 삭제」 — the ＋ wears no band; its key presses the ＋.
  group('the cut pill\'s ＋', () {
    testWidgets('and its key are one press, lit together and dim together', (
      tester,
    ) async {
      await pumpApp(tester);
      final session = sessionOf(tester);
      bool lit() =>
          tester
              .widget<StrapIconButton>(
                find
                    .byWidgetPredicate(
                      (widget) =>
                          widget is StrapIconButton &&
                          widget.buttonKey == 'new-cut-button',
                    )
                    .first,
              )
              .onPressed !=
          null;
      expect(session.cutPlacement.canCreateCut, isTrue, reason: '⛔premise');
      expect(lit(), isTrue);
      final made = cutsOf(tester);
      await pressKeyOf(tester, EditorActionIds.cutNew);
      // The ＋ asks the new cut's name and canvas first (I-100).
      await tester.tap(find.byKey(const ValueKey<String>('new-cut-ok-button')));
      await tester.pumpAndSettle();
      expect(cutsOf(tester), made + 1, reason: '⛔LIVENESS: the key makes one');
      session.undo();
      await tester.pumpAndSettle();

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
      expect(lit(), isFalse);

      final cuts = cutsOf(tester);
      await pressKeyOf(tester, EditorActionIds.cutNew);
      expect(
        find.byKey(const ValueKey<String>('new-cut-ok-button')),
        findsNothing,
        reason: 'and the key is the ＋\'s',
      );
      expect(cutsOf(tester), cuts);
    });
  });
}
