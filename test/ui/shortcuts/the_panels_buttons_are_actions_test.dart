// 🗣️I-40 (유저 2026-09-18): 「버튼 전수감사해서 숏컷리스트에 등록 … 뭐든 모든
// 버튼」; asked how far (I-40-Q1, 10-08): the editing screen's command
// buttons and menu rows.
//
// A PANEL'S OWN BUTTONS ARE ACTIONS, AND A KEY PRESSES THE BUTTON — the
// callback it holds, on a panel a key reaches: the panels of the tool in
// hand (the guide list, the tool settings) and the panels of no tool (the
// media pool, the timesheet). A dead button is dead by key too.
//
// The tool settings' own buttons came into the button scan's sight when
// they became one kind of button (tool-settings-panel-tidy, 2026-10-10),
// and were owed until the round of 2026-10-11. Their 다각형 닫기 and 적용 are
// 확정's own halves: they name it, and wear its Enter.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/brush_stamp_image.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_shape_kind.dart';
import 'package:anicel/src/models/cut_piece.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/services/canvas_selection_region.dart';
import 'package:anicel/src/services/cut_piece_slot.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart'
    show defaultCutCanvasSize;
import 'package:anicel/src/services/persistence/folder_grant.dart'
    show FolderGrant, FolderPicker;
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/canvas_selection_commands.dart';
import 'package:anicel/src/ui/brush/guide_panels.dart';
import 'package:anicel/src/ui/brush/tool_settings_panel.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/panels/editor_panel_tabs.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart';
import 'package:anicel/src/ui/shortcuts/panel_keys.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/text/cel_text_layout.dart' show celTextBoxOf;
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/app_tooltip.dart';

import '../../helpers/app_icon_button_probe.dart';
import '../../helpers/cel_text_tool_harness.dart';
import '../../helpers/rail_group_button.dart';

const k = LogicalKeyboardKey.keyK;

const panelButtons = [
  EditorActionIds.guideAddSymmetry,
  EditorActionIds.guideAddPerspective,
  EditorActionIds.textDeleteText,
  EditorActionIds.mediaPoolImport,
  EditorActionIds.timesheetFormat,
  EditorActionIds.timesheetDataMode,
  EditorActionIds.conteFormat,
  EditorActionIds.envelopeFormat,
  EditorActionIds.paletteNew,
  ...toolSettingsButtons,
];

/// The tool settings' own buttons, by the tool whose settings hold them.
const toolSettingsButtons = [
  EditorActionIds.transformFlipHorizontal,
  EditorActionIds.transformFlipVertical,
  EditorActionIds.transformReset,
  EditorActionIds.cutStampPasteAtOrigin,
  EditorActionIds.cutStampReset,
  EditorActionIds.cutStampRegisterTip,
  EditorActionIds.guideAddVanishingPoint,
  EditorActionIds.guideRasterize,
  EditorActionIds.textCentreAcross,
  EditorActionIds.textCentreDown,
  EditorActionIds.textIntoDrawing,
];

EditorShortcutBindings bindings(WidgetTester tester) =>
    EditorShortcutScope.peek(tester.element(find.byType(EditorWorkspace)))!;

/// The action [pressKeyOf] last recorded [k] for.
String? _held;

/// Records [k] for [actionId] — alone — and presses it. ⚠️[settle] false
/// where the press leaves a marquee, whose ants never settle.
Future<void> pressKeyOf(
  WidgetTester tester,
  String actionId, {
  bool settle = true,
}) async {
  if (_held case final before? when before != actionId) {
    bindings(tester).resetAction(before);
  }
  _held = actionId;
  bindings(tester).setActivators(actionId, const [SingleActivator(k)]);
  await tester.pump();
  await tester.sendKeyEvent(k);
  await (settle ? tester.pumpAndSettle() : tester.pump());
}

Future<void> pumpHome(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1600, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(theme: buildAppTheme(), home: const HomePage()),
  );
  await tester.pumpAndSettle();
}

Future<void> takeUp(WidgetTester tester, String tool) async {
  await tester.tap(find.byKey(ValueKey<String>('tool-$tool-button')));
  await tester.pumpAndSettle();
}

/// Opens the rail group [slot] on that side — a panel that ships shut is
/// not mounted, and a key presses only a button a panel shows.
Future<void> openRailGroup(
  WidgetTester tester, {
  required bool right,
  required int slot,
}) async {
  await tester.tap(
    railGroupButton(EditorWorkspace.railGroupId(right: right, slot: slot)),
  );
  await tester.pumpAndSettle();
}

/// The tool settings for [tool] where a key reaches them — inside the
/// [PanelKeys] the shell presses — in a panel [height] tall, reading the
/// keys of [shortcuts] where given.
Future<PanelKeys> pumpToolSettings(
  WidgetTester tester, {
  required CanvasTool tool,
  // The shape in hand, where the tool traces one.
  CanvasShapeKind? shape,
  double height = 960,
  CanvasSelectionCommands? selectionCommands,
  CutPieceSlot? cutPieceSlot,
  VoidCallback? onCutPasteAtOrigin,
  VoidCallback? onRegisterCutPieceAsTip,
  CutGuides? guides,
  GuideId? selectedGuideId,
  ValueChanged<CutGuides>? onGuidesCommitted,
  ValueChanged<DrawingGuide>? onGuideRasterized,
  EditorShortcutBindings? shortcuts,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final keys = PanelKeys();
  final state = BrushToolState.defaults.copyWith(tool: tool);
  Widget panel = PanelKeysScope(
    keys: keys,
    child: ToolSettingsPanel(
      state: shape == null ? state : state.withShapeKind(shape, forTool: tool),
      onChanged: (_) {},
      fillOptions: const FloodFillOptions(),
      onFillOptionsChanged: (_) {},
      selectionCommands: selectionCommands,
      cutPieceSlot: cutPieceSlot,
      onCutPasteAtOrigin: onCutPasteAtOrigin,
      onRegisterCutPieceAsTip: onRegisterCutPieceAsTip,
      guides: guides,
      selectedGuideId: selectedGuideId,
      onGuidesCommitted: onGuidesCommitted,
      onGuidesPreview: (_) {},
      onGuideRasterized: onGuideRasterized,
    ),
  );
  if (shortcuts != null) {
    panel = EditorShortcutScope(bindings: shortcuts, child: panel);
  }
  await tester.pumpWidget(
    MaterialApp(
      home: Material(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 320, height: height, child: panel),
        ),
      ),
    ),
  );
  await tester.pump();
  return keys;
}

/// A channel with no box open, which takes [flipped] and [reset] presses
/// while [canEdit] says the layer may be edited.
CanvasSelectionCommands selectionChannel({
  void Function(bool horizontal)? flipped,
  VoidCallback? reset,
  bool Function()? canEdit,
}) {
  final commands = CanvasSelectionCommands();
  commands.bind(
    Object(),
    hasSelection: () => commands.region != null,
    deselect: () {},
    canEditTransform: canEdit ?? () => true,
    flipTransform: ({required horizontal}) => flipped?.call(horizontal),
    resetTransform: reset,
  );
  return commands;
}

/// The message of the tooltip the button [key] wears.
String tooltipOf(WidgetTester tester, String key) => tester
    .widget<AppTooltip>(
      find
          .ancestor(
            of: find.byKey(ValueKey<String>(key)),
            matching: find.byType(AppTooltip),
          )
          .first,
    )
    .message;

CutPiece stampPiece() => CutPiece(
  image: BrushStampImage(
    id: 'p',
    width: 40,
    height: 24,
    rgba: Uint8List(40 * 24 * 4),
  ),
  originLeft: 5,
  originTop: 6,
);

DrawingGuide perspectiveGuide(String id, {required int points}) =>
    DrawingGuide(
      id: GuideId(id),
      name: id,
      shape: PerspectiveShape(
        vanishingPoints: [
          for (var index = 0; index < points; index += 1)
            VanishingPointAt(CanvasPoint(x: index * 400.0 - 100, y: 50)),
        ],
        eyeLevel: GuideAxis(
          origin: CanvasPoint(x: 50, y: 50),
          angleDegrees: 0,
        ),
      ),
    );

DrawingGuide symmetryGuide() => DrawingGuide(
  id: const GuideId('s1'),
  name: 's1',
  shape: SymmetryShape(
    axis: GuideAxis(origin: CanvasPoint(x: 50, y: 50), angleDegrees: 90),
  ),
);

void main() {
  setUp(() => _held = null);

  group('PanelKeys', () {
    test('a panel of no tool answers whatever is in hand; a tool\'s panel '
        'answers only with its tool in hand', () {
      final keys = PanelKeys();
      final pressed = <String>[];
      keys.bind(Object(), (buttons: {'a': () => pressed.add('pool')}, menu: null));
      keys.bind(
        Object(),
        (buttons: {'b': () => pressed.add('guides')}, menu: null),
        tool: CanvasTool.guide,
      );

      keys.press('a', CanvasTool.brush);
      keys.press('b', CanvasTool.brush);
      expect(pressed, ['pool']);
      keys.press('b', CanvasTool.guide);
      expect(pressed, ['pool', 'guides']);
    });

    test('a dead button presses nothing — and an owner let go takes only '
        'its own presses', () {
      final keys = PanelKeys();
      final pressed = <String>[];
      final one = Object();
      final two = Object();
      keys.bind(one, (buttons: {'a': null}, menu: null));
      keys.bind(two, (buttons: {'b': () => pressed.add('two')}, menu: null));

      keys.press('a', CanvasTool.brush);
      expect(pressed, isEmpty);
      keys.unbind(one);
      keys.press('b', CanvasTool.brush);
      expect(pressed, ['two']);
    });
  });

  group('the registry', () {
    test('they are panel buttons, and none ships with a key — nobody named '
        'one', () {
      for (final id in panelButtons) {
        final definition = editorActionDefinitions.singleWhere(
          (definition) => definition.id == id,
        );
        expect(definition.panelButton, isTrue, reason: id);
        expect(definition.menuRow, isFalse, reason: id);
        expect(definition.defaultActivators, isEmpty, reason: id);
      }
    });

    test('…named in the program\'s language — the window\'s own word where '
        'the button opens one', () {
      addTearDown(() => AppText.settings.value = const AppLanguageSettings());
      AppText.settings.value = const AppLanguageSettings(
        programLanguage: AppLanguage.ko,
      );
      expect(
        editorActionLabel(EditorActionIds.guideAddSymmetry),
        '새 대칭 가이드',
      );
      expect(editorActionLabel(EditorActionIds.mediaPoolImport), '임포트');
      expect(editorActionLabel(EditorActionIds.timesheetFormat), '타임시트 서식');
      expect(editorActionLabel(EditorActionIds.conteFormat), '콘티 용지 서식');
      expect(editorActionLabel(EditorActionIds.envelopeFormat), '컷 봉투 서식');
      expect(
        editorActionLabel(EditorActionIds.timesheetDataMode),
        '표기 시트 / 데이터 시트',
      );
      expect(editorActionLabel(EditorActionIds.textDeleteText), '텍스트 삭제');
      expect(editorActionLabel(EditorActionIds.paletteNew), '새 팔레트');
      // The button's own words — or, where the button's alone would say
      // less in a list of every key (초기화 · 반전), its tool's name with
      // them.
      expect(
        [for (final id in toolSettingsButtons) editorActionLabel(id)],
        [
          '변형 좌우 반전',
          '변형 상하 반전',
          '변형 초기화',
          '원래 위치에 붙여넣기',
          '스탬프 초기화',
          '팁으로 등록',
          '새 소실점',
          '래스터라이즈',
          '가로 가운데',
          '세로 가운데',
          '래스터라이즈',
        ],
      );
    });
  });

  group('a key presses the panel\'s button', () {
    testWidgets('the guide list\'s ＋: with the guide tool in hand a symmetry '
        'guide is added — and with the brush in hand, the list kept off '
        'stage adds none', (tester) async {
      await pumpHome(tester);
      await takeUp(tester, 'guide');
      int symmetries() => tester
          .widget<GuideLibraryList>(
            find.byType(GuideLibraryList, skipOffstage: false),
          )
          .guides
          .symmetryGuides
          .length;
      final before = symmetries();

      await pressKeyOf(tester, EditorActionIds.guideAddSymmetry);
      expect(symmetries(), before + 1);

      await takeUp(tester, 'brush');
      await pressKeyOf(tester, EditorActionIds.guideAddSymmetry);
      expect(symmetries(), before + 1);
    });

    testWidgets('the timesheet\'s format window opens by key, and its '
        'notation ⇄ data switch flips — and back', (tester) async {
      await pumpHome(tester);
      final window = find.byKey(
        const ValueKey<String>('timesheet-format-window'),
      );
      expect(window, findsNothing, reason: '⛔premise');
      await pressKeyOf(tester, EditorActionIds.timesheetFormat);
      expect(window, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      bool dataSheet() => tester
          .appIconButton(
            find.byKey(
              const ValueKey<String>('timesheet-data-mode-toggle-button'),
            ),
          )
          .isSelected;
      final before = dataSheet();
      await pressKeyOf(tester, EditorActionIds.timesheetDataMode);
      expect(dataSheet(), !before);
      await tester.sendKeyEvent(k);
      await tester.pumpAndSettle();
      expect(dataSheet(), before);
    });

    testWidgets('the conte sheet\'s and the cut envelope\'s format windows '
        'open by key once their panel is up — a panel that is shut has no '
        'button to press', (tester) async {
      await pumpHome(tester);
      final conte = find.byKey(const ValueKey<String>('conte-format-window'));
      await pressKeyOf(tester, EditorActionIds.conteFormat);
      expect(conte, findsNothing, reason: 'the sheet ships shut');
      await tester.tap(
        find.byKey(const ValueKey<String>('timeline-mode-conte-button')),
      );
      await tester.pumpAndSettle();
      await pressKeyOf(tester, EditorActionIds.conteFormat);
      expect(conte, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      final envelope = find.byKey(
        const ValueKey<String>('envelope-format-window'),
      );
      tester
          .widgetList<EditorPanelTabs>(find.byType(EditorPanelTabs))
          .firstWhere(
            (host) => host.tabs.any(
              (tab) => tab.id == EditorWorkspace.envelopeTabId,
            ),
          )
          .onTabSelected(EditorWorkspace.envelopeTabId);
      await tester.pumpAndSettle();
      expect(envelope, findsNothing, reason: '⛔premise');
      await pressKeyOf(tester, EditorActionIds.envelopeFormat);
      expect(envelope, findsOneWidget);
    });

    testWidgets('the media pool\'s ＋ asks for files — whatever tool is in '
        'hand', (tester) async {
      var asked = 0;
      FolderPicker.debugFilePicker =
          ({required acceptedTypeGroups, required allowMultiple}) async {
            asked += 1;
            return const [FolderGrant.cancelled()];
          };
      await pumpHome(tester);
      await pressKeyOf(tester, EditorActionIds.mediaPoolImport);
      expect(asked, 0, reason: 'the pool ships shut: no ＋ to press');

      await openRailGroup(tester, right: true, slot: 3);
      await tester.sendKeyEvent(k);
      await tester.pumpAndSettle();
      expect(asked, 1);
      await takeUp(tester, 'select');
      await tester.sendKeyEvent(k);
      await tester.pumpAndSettle();
      expect(asked, 2);
    });

    testWidgets('the palette panel\'s ＋ makes a palette — whatever tool is '
        'in hand (I-131)', (tester) async {
      Finder named(int n) => find.byKey(ValueKey<String>('palette-p$n-name'));
      await pumpHome(tester);
      await pressKeyOf(tester, EditorActionIds.paletteNew);

      final colour = find.byKey(const ValueKey<String>('tool-color-button'));
      await tester.ensureVisible(colour);
      await tester.pumpAndSettle();
      await tester.tap(colour);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('panel-tab-color-palette')),
      );
      await tester.pumpAndSettle();
      expect(named(1), findsOneWidget, reason: '⛔premise: the panel shows');
      expect(named(2), findsNothing, reason: 'it was shut: no ＋ to press');

      await tester.sendKeyEvent(k);
      await tester.pumpAndSettle();
      expect(named(2), findsOneWidget);
      await takeUp(tester, 'select');
      await tester.sendKeyEvent(k);
      await tester.pumpAndSettle();
      expect(named(3), findsOneWidget);
    });

    testWidgets('the text tool\'s 🗑 takes the text in hand off its cel — '
        'and with no text in hand, the dead button presses nothing', (
      tester,
    ) async {
      await pumpTextToolApp(tester);
      // The tool's settings ship shut — their 🗑 is not on screen.
      await pressToolSettingsButton(tester);
      await tester.pumpAndSettle();
      await takeTextTool(tester);
      final c = canvasPixelInView(tester);
      await clickAt(tester, c.dx, c.dy);
      await typeText(tester, 'hi');
      // Esc lets go of the LETTERS — the keyboard is the shortcuts' again —
      // and the text stays in hand by its box.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);
      expect(textToolOf(tester).contentInHand, isNotNull, reason: '⛔premise');

      await pressKeyOf(tester, EditorActionIds.textDeleteText);
      expect(textToolOf(tester).contentInHand, isNull);
      expect(celOf(tester).texts, isEmpty);

      await tester.sendKeyEvent(k);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the text tool\'s 래스터라이즈 makes the text in hand its '
        'cel\'s drawing — not the 🗑\'s way: its pixels stay', (
      tester,
    ) async {
      await pumpTextToolApp(tester);
      await pressToolSettingsButton(tester);
      await tester.pumpAndSettle();
      await takeTextTool(tester);
      final c = canvasPixelInView(tester);
      await clickAt(tester, c.dx, c.dy);
      await typeText(tester, 'hi');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);
      expect(textToolOf(tester).contentInHand, isNotNull, reason: '⛔premise');
      expect(celOf(tester).tiles, isEmpty, reason: '⛔premise: bare paper');

      await pressKeyOf(tester, EditorActionIds.textIntoDrawing);
      expect(celOf(tester).texts, isEmpty);
      expect(celOf(tester).tiles, isNotEmpty);
      expect(textToolOf(tester).session, isNull);
    });

    testWidgets('the text tool\'s 가로 가운데 and 세로 가운데 stand the text in '
        'hand on the canvas\'s middle lines', (tester) async {
      await pumpTextToolApp(tester);
      await pressToolSettingsButton(tester);
      await tester.pumpAndSettle();
      await takeTextTool(tester);
      final c = canvasPixelInView(tester);
      await clickAt(tester, c.dx, c.dy);
      await typeText(tester, 'hi');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFrames(tester);
      Offset centre() =>
          celTextBoxOf(celOf(tester).texts.single.content).centre;
      final before = centre();
      final middle = Offset(
        defaultCutCanvasSize.width / 2,
        defaultCutCanvasSize.height / 2,
      );
      expect(before.dx, isNot(moreOrLessEquals(middle.dx)), reason: '⛔fixture');
      expect(before.dy, isNot(moreOrLessEquals(middle.dy)), reason: '⛔fixture');

      await pressKeyOf(tester, EditorActionIds.textCentreAcross);
      expect(centre(), offsetMoreOrLessEquals(Offset(middle.dx, before.dy)));

      await pressKeyOf(tester, EditorActionIds.textCentreDown);
      expect(centre(), offsetMoreOrLessEquals(middle));
    });
  });

  // The tool settings' own buttons. A key presses them as the settings of
  // the tool in hand — and only then: with another tool in hand they are
  // not the panel on screen.
  group('a key presses the tool settings\' button', () {
    // 🗣️The one that is not the tool's alone (유저 2026-10-11, I-40-Q8:
    // 「어느 도구에서나(선택 해제처럼)」): its button stays in the Select
    // tool's settings, and its key answers in the shell.
    testWidgets('🎯선택 반전\'s key inverts with the brush in hand as with '
        'the Select tool — and inverts back', (tester) async {
      await pumpHome(tester);
      final commands = tester
          .widget<EditorWorkspace>(find.byType(EditorWorkspace))
          .canvasSelectionCommands!;

      for (final tool in const ['brush', 'select']) {
        await takeUp(tester, tool);
        expect(commands.region, isNull, reason: '⛔premise, $tool');
        await pressKeyOf(
          tester,
          EditorActionIds.selectionInvert,
          settle: false,
        );
        expect(commands.region, isNotNull, reason: tool);
        await pressKeyOf(tester, EditorActionIds.selectionInvert);
        expect(commands.region, isNull, reason: tool);
      }
    });

    testWidgets('🎯its two walls are two keys: in the canvas, it stops at '
        'the canvas\'s edge (I-108)', (tester) async {
      await pumpHome(tester);
      final workspace = tester.widget<EditorWorkspace>(
        find.byType(EditorWorkspace),
      );
      final commands = workspace.canvasSelectionCommands!;
      final canvas = workspace.session.requireActiveCut.canvasSize;

      await pressKeyOf(
        tester,
        EditorActionIds.selectionInvertInCanvas,
        settle: false,
      );

      expect(
        commands.region,
        CanvasSelectionRegion.invertedWithin(null, canvas.canvasRect),
      );
    });

    testWidgets('🚨the transform\'s flips and 초기화 — at the foot of a list '
        'that has not built them: a key presses the SECTION\'s buttons, '
        'wherever the list stands — and dead while the layer may not be '
        'edited', (tester) async {
      final flips = <bool>[];
      var resets = 0;
      var canEdit = true;
      final commands = selectionChannel(
        flipped: flips.add,
        reset: () => resets += 1,
        canEdit: () => canEdit,
      );
      final keys = await pumpToolSettings(
        tester,
        tool: CanvasTool.move,
        height: 40,
        selectionCommands: commands,
      );
      expect(
        find.byKey(
          const ValueKey<String>('move-reset-button'),
          skipOffstage: false,
        ),
        findsNothing,
        reason: '⛔premise: the row is past what the list builds',
      );

      keys.press(EditorActionIds.transformFlipHorizontal, CanvasTool.move);
      keys.press(EditorActionIds.transformFlipVertical, CanvasTool.move);
      keys.press(EditorActionIds.transformReset, CanvasTool.move);
      expect(flips, [true, false]);
      expect(resets, 1);

      keys.press(EditorActionIds.transformReset, CanvasTool.select);
      expect(resets, 1, reason: 'another tool in hand');

      canEdit = false;
      commands.notifySessionChanged();
      await tester.pumpAndSettle();
      keys.press(EditorActionIds.transformFlipHorizontal, CanvasTool.move);
      keys.press(EditorActionIds.transformReset, CanvasTool.move);
      expect(flips, [true, false]);
      expect(resets, 1);
    });

    testWidgets('the stamp\'s three, while a piece is held — 초기화 dead '
        'until the piece is posed', (tester) async {
      final slot = CutPieceSlot()..hold(stampPiece());
      var pastes = 0;
      var tips = 0;
      final keys = await pumpToolSettings(
        tester,
        tool: CanvasTool.cutStamp,
        cutPieceSlot: slot,
        onCutPasteAtOrigin: () => pastes += 1,
        onRegisterCutPieceAsTip: () => tips += 1,
      );

      keys.press(EditorActionIds.cutStampPasteAtOrigin, CanvasTool.cutStamp);
      keys.press(EditorActionIds.cutStampRegisterTip, CanvasTool.cutStamp);
      expect((pastes, tips), (1, 1));
      keys.press(EditorActionIds.cutStampPasteAtOrigin, CanvasTool.cut);
      expect(pastes, 1, reason: 'the grab is another tool');

      keys.press(EditorActionIds.cutStampReset, CanvasTool.cutStamp);
      expect(slot.piece!.isPosed, isFalse, reason: '⛔premise');
      slot.updatePose(scalePercent: 50);
      await tester.pump();
      keys.press(EditorActionIds.cutStampReset, CanvasTool.cutStamp);
      expect(slot.piece!.scalePercent, 100);

      slot.clear();
      await tester.pump();
      keys.press(EditorActionIds.cutStampPasteAtOrigin, CanvasTool.cutStamp);
      keys.press(EditorActionIds.cutStampRegisterTip, CanvasTool.cutStamp);
      expect((pastes, tips), (1, 1), reason: 'nothing held: no buttons');
    });

    testWidgets('the perspective\'s ＋ adds a vanishing point — at three as '
        'at two, and none for a symmetry guide', (tester) async {
      CutGuides? committed;
      final perspective = perspectiveGuide('p1', points: 2);
      final keys = await pumpToolSettings(
        tester,
        tool: CanvasTool.guide,
        guides: CutGuides(guides: [perspective]),
        selectedGuideId: perspective.id,
        onGuidesCommitted: (next) => committed = next,
      );

      keys.press(EditorActionIds.guideAddVanishingPoint, CanvasTool.brush);
      expect(committed, isNull, reason: 'another tool in hand');
      keys.press(EditorActionIds.guideAddVanishingPoint, CanvasTool.guide);
      final points =
          (committed!.guideFor(perspective.id)!.shape as PerspectiveShape)
              .vanishingPoints;
      expect(points, hasLength(3));
      // On the eye level beside its handle at (50, 50) (Q7).
      expect(points.last, VanishingPointAt(CanvasPoint(x: 470, y: 50)));

      committed = null;
      final three = perspectiveGuide('p1', points: 3);
      final atThree = await pumpToolSettings(
        tester,
        tool: CanvasTool.guide,
        guides: CutGuides(guides: [three]),
        selectedGuideId: three.id,
        onGuidesCommitted: (next) => committed = next,
      );
      atThree.press(EditorActionIds.guideAddVanishingPoint, CanvasTool.guide);
      expect(
        (committed!.guideFor(three.id)!.shape as PerspectiveShape)
            .vanishingPoints,
        hasLength(4),
        reason: '↩️it stopped at three until 2026-10-16',
      );

      committed = null;
      final onSymmetry = await pumpToolSettings(
        tester,
        tool: CanvasTool.guide,
        guides: CutGuides(guides: [symmetryGuide()]),
        selectedGuideId: const GuideId('s1'),
        onGuidesCommitted: (next) => committed = next,
      );
      onSymmetry.press(
        EditorActionIds.guideAddVanishingPoint,
        CanvasTool.guide,
      );
      expect(committed, isNull);
    });

    testWidgets('the perspective\'s 래스터라이즈 hands the guide over — none '
        'for a symmetry guide, and none where nothing takes it', (
      tester,
    ) async {
      final handed = <DrawingGuide>[];
      final perspective = perspectiveGuide('p1', points: 2);
      final keys = await pumpToolSettings(
        tester,
        tool: CanvasTool.guide,
        guides: CutGuides(guides: [perspective]),
        selectedGuideId: perspective.id,
        onGuideRasterized: handed.add,
      );

      keys.press(EditorActionIds.guideRasterize, CanvasTool.brush);
      expect(handed, isEmpty, reason: 'another tool in hand');
      keys.press(EditorActionIds.guideRasterize, CanvasTool.guide);
      expect(handed, [perspective]);

      final onSymmetry = await pumpToolSettings(
        tester,
        tool: CanvasTool.guide,
        guides: CutGuides(guides: [symmetryGuide()]),
        selectedGuideId: const GuideId('s1'),
        onGuideRasterized: handed.add,
      );
      onSymmetry.press(EditorActionIds.guideRasterize, CanvasTool.guide);
      expect(handed, hasLength(1));

      final untaken = await pumpToolSettings(
        tester,
        tool: CanvasTool.guide,
        guides: CutGuides(guides: [perspective]),
        selectedGuideId: perspective.id,
      );
      untaken.press(EditorActionIds.guideRasterize, CanvasTool.guide);
      expect(handed, hasLength(1));
    });

    testWidgets('다각형 닫기 and 적용 are 확정\'s own halves: they wear its '
        'Enter — and a key recorded for a worded button joins its name', (
      tester,
    ) async {
      final shortcuts = EditorShortcutBindings();
      final commands = selectionChannel();
      await pumpToolSettings(
        tester,
        tool: CanvasTool.move,
        selectionCommands: commands,
        shortcuts: shortcuts,
      );
      expect(tooltipOf(tester, 'move-apply-button'), 'Apply (Enter)');
      expect(tooltipOf(tester, 'move-reset-button'), 'Reset');
      shortcuts.setActivators(EditorActionIds.transformReset, const [
        SingleActivator(k),
      ]);
      await tester.pump();
      expect(tooltipOf(tester, 'move-reset-button'), 'Reset (K)');

      // The close stands for the polygon alone (F-478-Q1).
      await pumpToolSettings(
        tester,
        tool: CanvasTool.select,
        shape: CanvasShapeKind.polygon,
        selectionCommands: commands,
        shortcuts: shortcuts,
      );
      expect(
        tooltipOf(tester, 'selection-close-polygon-button'),
        'Close shape (Enter)',
      );
    });

    testWidgets('🎯the two inverts are two buttons of two actions: a key '
        'recorded for the one in the canvas joins ITS name (I-108)', (
      tester,
    ) async {
      final shortcuts = EditorShortcutBindings();
      await pumpToolSettings(
        tester,
        tool: CanvasTool.select,
        selectionCommands: selectionChannel(),
        shortcuts: shortcuts,
      );
      shortcuts.setActivators(EditorActionIds.selectionInvertInCanvas, const [
        SingleActivator(k),
      ]);
      await tester.pump();

      expect(
        tooltipOf(tester, 'selection-invert-in-canvas-button'),
        'Invert Selection in Canvas (K)',
      );
      expect(
        tooltipOf(tester, 'selection-invert-button'),
        isNot(contains('(K)')),
      );
    });
  });
}
