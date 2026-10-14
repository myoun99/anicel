import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/text_cel_style.dart';
import '../../services/cel_text_box_edits.dart' show celTextMinFontSize;
import '../canvas/text/cel_text_tool.dart';
import '../dialogs/app_confirm_dialog.dart' show showAppNotice;
import '../shortcuts/editor_action_registry.dart' show EditorActionIds;
import '../shortcuts/panel_keys.dart';
import '../sliced_value_listenable_builder.dart' show SlicedListenableBuilder;
import '../text/app_strings.dart';
import '../text/canvas_letter_faces.dart';
import '../text/imported_fonts.dart';
import '../text/readout_text.dart' show columnValueText;
import '../theme/app_theme.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/color_swatch_button.dart';
import '../widgets/drag_value_label.dart';
import '../widgets/field_slider.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/settings_rows.dart';
import 'brush_tool_state.dart' show CanvasTool;
import 'cel_text_commands.dart';
import 'text_tool_options.dart';
import 'text_tool_settings_values.dart';
import 'tool_setting_rows.dart';
import 'tool_settings_section.dart';

/// The TEXT tool's settings (R9-rest) — mounted by the tool settings panel
/// like every other tool's (유저: 툴 설정은 툴 설정 패널에).
///
/// The layout is the one 유저 took on 2026-10-06, top to bottom: the text in
/// hand and its delete · **글자** — face, size, tracking, bold, colour,
/// outline, outline width, and the smoothing of their edges (유저: 「2차에서
/// 스위치로 넣음」) · **상자** — the way it is written (가로 · 세로,
/// 유저: 「세로쓰기 … 그거 통합하면서 진행」), alignment, box width, line spacing,
/// background · and at the foot 「래스터라이즈」.
///
/// What every row reads and writes is ONE law, and it is not in this file
/// ([TextToolSettingsValues]): the text in hand by the letters a setting
/// speaks for, or the next text's values — and a change made on both. Here
/// are the rows.
class TextToolSettings extends StatelessWidget {
  const TextToolSettings({
    super.key,
    required this.options,
    required this.commands,
    this.currentColorOf,
    this.fonts,
  });

  /// The fonts this device was brought, which the face is picked from
  /// beside the app's own. Null in a host that keeps none: the list is the
  /// app's faces, and nothing is brought from it.
  final ImportedFonts? fonts;

  /// The next text's values. Null in a host that does not own them: the
  /// section shows the defaults and changes nothing.
  final ValueNotifier<TextToolOptions>? options;

  /// The channel to the text the canvas holds. Null where there is no
  /// canvas to hold one.
  final CelTextCommands? commands;

  /// The brush's colour — what 「현재 색 반영」 copies into a colour here, and
  /// the next text's while the tool has none of its own
  /// ([TextToolOptions.takesTheBrushColour]). Null where there is no brush
  /// to read.
  final int Function()? currentColorOf;

  @override
  Widget build(BuildContext context) {
    final reading = _Reading(
      options: options,
      commands: commands,
      currentColorOf: currentColorOf,
    );
    final strings = AppText.strings;
    final section = ToolSettingsSection(
      tool: 'text',
      title: strings.toolText,
      children: [
        _TextInHandRow(reading: reading),
        ToolSettingsGroupHeader(strings.textToolLetters),
        _LetterRows(
          reading: reading,
          currentColorOf: currentColorOf,
          fonts: fonts,
        ),
        ToolSettingsGroupHeader(strings.textToolBox),
        _BoxRows(reading: reading, currentColorOf: currentColorOf),
        _IntoDrawingButton(reading: reading),
      ],
    );
    // A key presses the 🗑, the two centrings and 래스터라이즈 as the text
    // tool's settings (I-40) — bound again when any of them comes to have
    // something to press, and the section handed on as it was.
    return reading.follow(
      (values) => (
        delete: _TextInHandRow.deleteOf(commands) != null,
        centre: values.boxCentre != null,
        turn: _IntoDrawingButton.turnOf(commands) != null,
      ),
      (_) => PanelKeysBinding(
        tool: CanvasTool.text,
        buttons: {
          EditorActionIds.textDeleteText: _TextInHandRow.deleteOf(commands),
          EditorActionIds.textCentreAcross: _BoxRows.centreOf(
            reading,
            across: true,
          ),
          EditorActionIds.textCentreDown: _BoxRows.centreOf(
            reading,
            across: false,
          ),
          EditorActionIds.textIntoDrawing: _IntoDrawingButton.turnOf(
            commands,
          ),
        },
        child: section,
      ),
    );
  }
}

/// What the section's controls read, and the news that can change it.
///
/// 🚨★★★EACH CONTROL HEARS ONLY WHAT IT SHOWS ([follow]). The hand tells of
/// every sample of a drag — a text carried, sized or turned on the canvas,
/// letters swept over, a bar scrubbed — and the section was ONE builder on
/// it: every row was built again for every sample
/// (`text-settings-redrawn-per-drag-sample`, 2026-10-14). 유저's law of the
/// transform tool's numbers is the one kept here — F-164 (2026-09-18):
/// 「변형중에 툴도구의 X,Y값같은거 실시간으로 바뀌게 해주고. 무겁지 않을
/// 구조로 패널리빌드하지말고 글자만 바꾸게」 — by the rule the tool settings'
/// host keeps for the session's news (I-57 ㉢): news that moves none of what
/// a control shows stops before it. A text carried across the canvas
/// builds its X again, and nothing else here.
class _Reading {
  _Reading({
    required this.options,
    required this.commands,
    required this.currentColorOf,
  }) : news = Listenable.merge([?options, ?commands]);

  final ValueNotifier<TextToolOptions>? options;
  final CelTextCommands? commands;
  final int Function()? currentColorOf;

  /// What can change what the section shows: the next text's values and
  /// the hand. ⚠️Not the fonts: the list of faces is made when it OPENS,
  /// and nothing on the row itself is read from them.
  final Listenable news;

  /// The values as they stand NOW — what a control's slice is read from,
  /// and what its presses write through. ⛔Never a copy a build was handed:
  /// what changed without reaching that build would be written back as it
  /// was (`SlicedValueListenableBuilder`'s callback discipline).
  TextToolSettingsValues get now => TextToolSettingsValues(
    options: options,
    tool: commands?.tool,
    brushColour: currentColorOf?.call(),
  );

  /// A control built from [shows] — what it shows of the values — and
  /// built again when, and only when, that changes. [shows] answers what
  /// compares by value: a record, a number, a string.
  Widget follow<S>(
    S Function(TextToolSettingsValues values) shows,
    Widget Function(S shown) build,
  ) => SlicedListenableBuilder<S>(
    listenable: news,
    slice: () => shows(now),
    builder: (context, shown) => build(shown),
  );
}

/// What a value several letters do not agree on reads as (유저 2026-10-06).
const String _mixed = '—';

/// The text in hand, by its own letters — and the list of the cel's texts
/// it is picked from. 유저 2026-10-06: 「도구설정에 선택된 텍스트라는 항목이
/// 있었으면 좋겠음. 거기서 다른 텍스트 선택할수있게 리스트 고르는. 팝오버로
/// 리스트 고를수있게하고. 텍스트의 이름은 그냥 텍스트 글자대로. 그리고 옆에
/// 삭제버튼 있고」 — a delete beside the field, and one on every row of the
/// list (the drawing taken with it: 「1 ok」).
class _TextInHandRow extends StatelessWidget {
  const _TextInHandRow({required this.reading});

  final _Reading reading;

  /// A text's name is its own letters on ONE line: its breaks are not its
  /// name's.
  static String _nameOf(String text) => text.replaceAll('\n', ' ');

  /// What the 🗑 presses: the text in hand off its cel — nothing while
  /// none is in hand.
  static VoidCallback? deleteOf(CelTextCommands? commands) =>
      commands?.tool?.contentInHand == null ? null : commands?.deleteText;

  @override
  Widget build(BuildContext context) {
    final commands = reading.commands;
    // Named in the grid's name column like every row under it
    // (tool-settings-panel-tidy, 유저 2026-10-10: 「정돈된 행/열」).
    return ToolSettingRow(
      label: AppText.strings.textToolSelectedText,
      child: reading.follow(
        (values) => (
          name: values.tool?.contentInHand?.text,
          // With no text on the cel there is none to pick.
          listed: values.tool?.list.texts.isNotEmpty ?? false,
        ),
        (shown) => Row(
          children: [
            Expanded(
              child: PanelFlyoutButton(
                key: const ValueKey<String>('text-tool-selected-text'),
                label: _nameOf(shown.name ?? ''),
                expand: true,
                enabled: shown.listed,
                entriesBuilder: () => _listOf(commands?.tool),
              ),
            ),
            const SizedBox(width: ToolSettingColumns.gap),
            AppIconButton(
              keyValue: 'text-tool-delete-text',
              tooltip: AppText.strings.textToolDeleteText,
              shortcuts: const [EditorActionIds.textDeleteText],
              icon: Icon(
                Icons.delete_outline,
                color: AppColors.deleteGlyph(enabled: shown.name != null),
              ),
              onPressed: deleteOf(commands),
            ),
          ],
        ),
      ),
    );
  }

  /// The cel's texts from the top of the stack down, as they are when the
  /// list OPENS — the one in hand marked, each with its own delete.
  static List<PanelFlyoutEntry> _listOf(CelTextTool? tool) => [
    for (final (index, text)
        in (tool?.list.texts ?? const <CelTextListed>[]).indexed)
      PanelFlyoutItem(
        // By its place from the top: two texts can say the same.
        keyValue: 'text-tool-text-$index',
        label: _nameOf(text.text),
        selected: text.inHand,
        onSelected: () => tool?.list.take(text.id),
        action: PanelFlyoutRowAction(
          keyValue: 'text-tool-text-$index-delete',
          icon: Icons.delete_outline,
          tooltip: AppText.strings.textToolDeleteText,
          does: PanelFlyoutActionDoes.deletes,
          onPressed: () => tool?.list.delete(text.id),
        ),
      ),
  ];
}

/// 「래스터라이즈」: the text in hand becomes its cel's drawing
/// ([CelTextTool.turnIntoDrawing]). ↩️It read 「그림으로 굳히기」 while the
/// import's read 「굽기」 and the layer's 「래스터라이즈」 — 🗣️유저 2026-10-10:
/// 「굽기버튼도 마찬가지야. 뭐는 굽기 뭐는 래스터라이즈. 래스터라이즈로 통일」.
///
/// 🗣️유저 2026-10-06: 「나중에 도구설정에 등장시키기로. 동작은 **텍스트
/// 선택하면 해당 버튼 활성화색**」 — at the foot of the settings, where the
/// drawing taken that day has it: ALWAYS THERE (⛔없다가 생기는 UI 금지), and
/// lit only while a text is in hand. The filled button the transform tool's
/// 적용 is, grey the same way when it has nothing to do.
///
/// The tool's one ACTION ([ToolSettingActions] — the line every tool ends
/// with, tool-settings-panel-tidy 유저 2026-10-10 「다 추천대로」), whose
/// press is the button's own: a press that wobbles on it turns the text all
/// the same, and never scrolls the settings.
class _IntoDrawingButton extends StatelessWidget {
  const _IntoDrawingButton({required this.reading});

  final _Reading reading;

  /// What it presses: the text in hand turned — nothing while none is in
  /// hand.
  static VoidCallback? turnOf(CelTextCommands? commands) =>
      commands != null && commands.holdsText ? commands.turnIntoDrawing : null;

  @override
  Widget build(BuildContext context) => reading.follow(
    (_) => turnOf(reading.commands) != null,
    (_) => ToolSettingActions(
      lines: [
        [
          ToolSettingAction(
            keyValue: 'text-tool-into-drawing',
            label: AppText.strings.textToolIntoDrawing,
            decides: true,
            shortcuts: const [EditorActionIds.textIntoDrawing],
            onPressed: turnOf(reading.commands),
          ),
        ],
      ],
    ),
  );
}

/// A number of the letters that a bar sets.
enum _LetterNumber { size, tracking, outlineWidth }

/// One of those as its bar: what it is called, how it is read off a style
/// and written into one, and what the bar runs over.
typedef _LetterBar = ({
  String name,
  String label,
  double Function(TextLetterStyle style) read,
  TextLetterStyle Function(TextLetterStyle style, double value) write,
  double min,
  double max,
  FieldSliderScale scale,
  int? divisions,
  String unit,
});

/// The rows of the 글자 group — every one a setting of LETTERS, which
/// reaches the selected ones or, with none selected, the whole text.
class _LetterRows extends StatelessWidget {
  const _LetterRows({
    required this.reading,
    required this.currentColorOf,
    required this.fonts,
  });

  final _Reading reading;
  final int Function()? currentColorOf;
  final ImportedFonts? fonts;

  /// The largest a letter is set at from here, in canvas pixels. (The
  /// smallest is the law's own, [celTextMinFontSize].)
  static const double _largest = 2000;

  /// How far letters are set apart from here, or drawn together.
  static const double _widestTracking = 100;

  /// The widest outline set from here.
  static const double _widestOutline = 64;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      ToolSettingRow(
        label: AppText.strings.textToolFont,
        child: _FaceRow(reading: reading, fonts: fonts),
      ),
      _bar(_LetterNumber.size),
      _bar(_LetterNumber.tracking),
      reading.follow(
        (values) => (
          bold: values.letter((style) => style.bold),
          writable: values.writable,
        ),
        (shown) => SettingsSwitchRow(
          tileKey: const ValueKey<String>('text-tool-bold'),
          label: AppText.strings.textToolBold,
          value: !shown.bold.mixed && shown.bold.value,
          mixed: shown.bold.mixed,
          onChanged: shown.writable
              ? (on) => reading.now.setLetters(
                  (style) => style.copyWith(bold: on),
                )
              : null,
        ),
      ),
      _colour(),
      _outline(),
      // A width with no colour is no outline: until the letters have one
      // there is nothing for it to be the width of.
      _bar(_LetterNumber.outlineWidth, live: _outlined),
      _smoothing(),
    ],
  );

  /// Whether the letters have an outline — some of them, at least.
  static bool _outlined(TextToolSettingsValues values) {
    final outlined = values.letter((style) => style.outlineColor != null);
    return outlined.mixed || outlined.value;
  }

  /// Whether the letters' edges are smoothed — the switch the shape fill
  /// and the selection carry, under their word for it.
  ///
  /// 🗣️유저 2026-10-06 (asked whether letters need it): 「권장대로. 2차에서
  /// 스위치로 넣음」 — in this group, so it is a setting of LETTERS: it
  /// reaches the selected ones or, with none selected, the whole text.
  Widget _smoothing() => reading.follow(
    (values) => (
      smooth: values.letter((style) => style.antialias),
      writable: values.writable,
    ),
    (shown) => SettingsSwitchRow(
      tileKey: const ValueKey<String>('text-tool-antialias'),
      label: AppText.strings.brAntiAlias,
      value: !shown.smooth.mixed && shown.smooth.value,
      mixed: shown.smooth.mixed,
      onChanged: shown.writable
          ? (on) => reading.now.setLetters(
              (style) => style.copyWith(antialias: on),
            )
          : null,
    ),
  );

  /// One number of the letters as a bar: dragged it shows, and where the
  /// hand lets go it lands. [live] says whether it takes a change at all.
  Widget _bar(
    _LetterNumber number, {
    bool Function(TextToolSettingsValues values)? live,
  }) {
    final bar = _barOf(number);
    void set(double value, {required bool settled}) =>
        reading.now.setLetters(
          (style) => bar.write(style, value),
          settled: settled,
        );
    return ToolSettingRow.bar(
      label: bar.label,
      bar: reading.follow(
        (values) => (
          number: values.letter(bar.read),
          takes: values.writable && (live?.call(values) ?? true),
        ),
        (shown) => FieldSlider.cell(
          key: ValueKey<String>('text-tool-${bar.name}'),
          label: bar.label,
          min: bar.min,
          max: bar.max,
          scale: bar.scale,
          divisions: bar.divisions,
          unit: bar.unit,
          value: shown.number.value.clamp(bar.min, bar.max),
          valueTextBuilder: shown.number.mixed ? (_, _) => _mixed : null,
          onChanged: shown.takes
              ? (value) => set(value, settled: false)
              : null,
          onChangeEnd: (value) => set(value, settled: true),
        ),
      ),
    );
  }

  static _LetterBar _barOf(_LetterNumber number) => switch (number) {
    // Sizes multiply — the small ones are where a step matters.
    _LetterNumber.size => (
      name: 'size',
      label: AppText.strings.textToolSize,
      read: (style) => style.fontSize,
      write: (style, size) => style.copyWith(fontSize: size),
      min: celTextMinFontSize,
      max: _largest,
      scale: FieldSliderScale.exponential,
      divisions: null,
      unit: ' px',
    ),
    _LetterNumber.tracking => (
      name: 'tracking',
      label: AppText.strings.textToolTracking,
      read: (style) => style.letterSpacing,
      write: (style, tracking) => style.copyWith(letterSpacing: tracking),
      min: -_widestTracking,
      max: _widestTracking,
      scale: FieldSliderScale.linear,
      divisions: (_widestTracking * 2).toInt(),
      unit: '',
    ),
    _LetterNumber.outlineWidth => (
      name: 'outline-width',
      label: AppText.strings.textToolOutlineWidth,
      read: (style) => style.outlineWidth,
      write: (style, width) => style.copyWith(outlineWidth: width),
      min: 0,
      max: _widestOutline,
      scale: FieldSliderScale.linear,
      divisions: _widestOutline.toInt(),
      unit: ' px',
    ),
  };

  Widget _colour() => ToolSettingRow.atEnd(
    label: AppText.strings.textToolColor,
    child: reading.follow(
      (values) => values.letter((style) => style.color),
      (colour) => ColorSwatchButton(
        keyValue: 'text-tool-color',
        color: colour.value,
        mixed: colour.mixed,
        currentColorOf: currentColorOf,
        onChanged: (argb) => reading.now.setColour(argb, settled: false),
        onSettled: () => reading.now.settle(),
      ),
    ),
  );

  Widget _outline() {
    void set(int? argb) => reading.now.setLetters(
      (style) => style.copyWith(outlineColor: argb),
      settled: false,
    );
    return ToolSettingRow.atEnd(
      label: AppText.strings.textToolOutline,
      child: reading.follow(
        (values) => values.letter((style) => style.outlineColor),
        (outline) => ColorSwatchButton(
          keyValue: 'text-tool-outline',
          color: outline.value,
          mixed: outline.mixed,
          currentColorOf: currentColorOf,
          onChanged: set,
          onNone: () => set(null),
          onSettled: () => reading.now.settle(),
        ),
      ),
    );
  }
}

/// THE FACE: the app's own two, in the order it reads them, and under them
/// the ones this device was brought — picked, brought and taken away from
/// one list (유저 2026-10-06, the drawing taken: 「글꼴 ＋」 over the faces,
/// a delete on each one brought).
///
/// 🗣️유저 2026-10-06: 「유저가 알아서 자기가 가지고있는 글꼴 넣는게
/// 아니야?」 — the ＋ picks a FILE.
class _FaceRow extends StatelessWidget {
  const _FaceRow({required this.reading, required this.fonts});

  final _Reading reading;
  final ImportedFonts? fonts;

  static const List<String?> _appFaces = [
    null,
    ...AppTypography.bundledFallback,
  ];

  static String _nameOf(String? family) =>
      family ?? AppTypography.bundledFamily;

  static ShownLetterSetting<String?> _faceOf(TextToolSettingsValues values) =>
      values.letter((style) => style.fontFamily);

  @override
  Widget build(BuildContext context) => reading.follow(
    (values) => (face: _faceOf(values), writable: values.writable),
    (shown) => PanelFlyoutButton(
      key: const ValueKey<String>('text-tool-font'),
      label: shown.face.mixed ? _mixed : _nameOf(shown.face.value),
      expand: true,
      enabled: shown.writable,
      entriesBuilder: () => _faces(context, inUse: _faceOf(reading.now)),
    ),
  );

  /// The list, as it is when it OPENS.
  List<PanelFlyoutEntry> _faces(
    BuildContext context, {
    required ({String? value, bool mixed}) inUse,
  }) {
    final strings = AppText.strings;
    final fonts = this.fonts;
    final brought = fonts?.families ?? const <ImportedFontFamily>[];
    final carried = fonts?.carriedFamilies ?? const <String>[];
    bool isInUse(String? family) => !inUse.mixed && family == inUse.value;
    return [
      PanelFlyoutHeader(
        strings.textToolFont,
        action: fonts == null
            ? null
            : PanelFlyoutRowAction(
                keyValue: 'text-tool-font-import',
                icon: Icons.add,
                tooltip: strings.textToolFontImport,
                does: PanelFlyoutActionDoes.adds,
                onPressed: () => unawaited(_bring(context, fonts)),
              ),
      ),
      for (final family in _appFaces)
        PanelFlyoutItem(
          keyValue: 'text-tool-font-${_nameOf(family)}',
          label: _nameOf(family),
          selected: isInUse(family),
          onSelected: () => _pick(family),
        ),
      // The face in use is nobody's — not this device's, not the project's:
      // it is named, as the one in use, and says what that means. There is
      // nothing of it to pick.
      if (!inUse.mixed &&
          !CanvasLetterFaces.isAppFace(inUse.value) &&
          !carried.contains(inUse.value) &&
          !brought.any((family) => family.name == inUse.value))
        PanelFlyoutItem(
          keyValue: 'text-tool-font-${inUse.value}',
          label: inUse.value!,
          selected: true,
          warning: strings.textToolFontNotOnThisDevice,
        ),
      if (fonts != null) ...[
        ..._ofTheProject(fonts, carried, isInUse),
        ..._ofTheDevice(fonts, brought, isInUse),
      ],
    ];
  }

  /// The fonts registered with THE PROJECT ON SCREEN, under their own
  /// heading — none of either, for a project that carries none.
  ///
  /// 🗣️유저 2026-10-06: 「뺄때까지 두는게 맞지않나 싶은데. 글꼴을 사실상
  /// 등록하는거잖아」 — so they are listed as the project's own, and each
  /// row has the taking of it out.
  List<PanelFlyoutEntry> _ofTheProject(
    ImportedFonts fonts,
    List<String> carried,
    bool Function(String? family) isInUse,
  ) => _group(AppText.strings.textToolFontsOfProject, [
    for (final family in carried)
      PanelFlyoutItem(
        keyValue: 'text-tool-project-font-$family',
        label: family,
        selected: isInUse(family),
        // Registered, and its bytes are nowhere this device can read: it is
        // the project's all the same, and says why its letters show in
        // another face.
        warning: CanvasLetterFaces.current.holds(family)
            ? null
            : AppText.strings.textToolFontNotOnThisDevice,
        onSelected: () => _pick(family),
        action: PanelFlyoutRowAction(
          keyValue: 'text-tool-project-font-$family-take-out',
          icon: Icons.remove,
          tooltip: AppText.strings.textToolFontTakeOut,
          does: PanelFlyoutActionDoes.deletes,
          onPressed: () => fonts.takeOutOfProject(family),
        ),
      ),
  ]);

  /// The fonts THIS DEVICE was brought, under their own heading — none of
  /// either, on a device that was brought none.
  List<PanelFlyoutEntry> _ofTheDevice(
    ImportedFonts fonts,
    List<ImportedFontFamily> brought,
    bool Function(String? family) isInUse,
  ) => _group(AppText.strings.textToolFontsOfDevice, [
    for (final family in brought)
      PanelFlyoutItem(
        keyValue: 'text-tool-font-${family.name}',
        label: family.name,
        selected: isInUse(family.name),
        warning: family.ridesInEditedDocuments
            ? null
            : AppText.strings.textToolFontStaysOnThisDevice,
        onSelected: () => _pick(family.name),
        action: PanelFlyoutRowAction(
          keyValue: 'text-tool-font-${family.name}-delete',
          icon: Icons.delete_outline,
          tooltip: AppText.strings.textToolFontDelete,
          does: PanelFlyoutActionDoes.deletes,
          onPressed: () => unawaited(fonts.delete(family.name)),
        ),
      ),
  ]);

  /// A GROUP of the list: [rows] under their own [heading], a rule above
  /// it — and nothing at all, heading and rule included, where there are
  /// no rows to stand under them.
  static List<PanelFlyoutEntry> _group(
    String heading,
    List<PanelFlyoutItem> rows,
  ) => [
    if (rows.isNotEmpty) ...[
      const PanelFlyoutDivider(),
      PanelFlyoutHeader(heading),
    ],
    ...rows,
  ];

  /// Sets the letters in [family] — and has it READ now, where it is one
  /// this device holds and the engine has not been handed
  /// ([CanvasLetterFaces.sendFor]).
  ///
  /// A face is read when letters are first asked for in it, and with no
  /// text in hand nothing asks until a press begins one: the press would
  /// find its caret measured in another face, and its first letters
  /// waiting. Picked is when it is known to be wanted.
  void _pick(String? family) {
    CanvasLetterFaces.current.sendFor(family);
    reading.now.setLetters((style) => style.copyWith(fontFamily: family));
  }

  /// The ＋: picks a file and brings it as a font — and the face brought is
  /// the face picked, for the ＋ stands in the list a face is picked from.
  ///
  /// What it says is what every door a font comes in through says
  /// ([ImportedFonts.noticeOf]) — and its row in the list says it from then
  /// on.
  Future<void> _bring(BuildContext context, ImportedFonts fonts) async {
    final outcome = await fonts.importFromFile();
    final family = outcome.family;
    if (family != null) {
      _pick(family);
    }
    final notice = fonts.noticeOf(outcome);
    if (notice != null && context.mounted) {
      await showAppNotice(
        context,
        title: AppText.strings.commonNotice,
        message: notice,
      );
    }
  }
}

/// The rows of the 상자 group — every one a setting of the WHOLE text.
class _BoxRows extends StatelessWidget {
  const _BoxRows({required this.reading, required this.currentColorOf});

  final _Reading reading;
  final int Function()? currentColorOf;

  /// The line pitches set from here, as multiples of the letters' size, and
  /// the step between two of them.
  static const double _tightest = 0.5;
  static const double _loosest = 3;
  static const double _pitchStep = 0.05;

  /// What a centring presses, button or key: the text in hand stood on the
  /// canvas's middle line [across] (or down), through the values as they
  /// stand at the press — nothing while none is in hand.
  static VoidCallback? centreOf(_Reading reading, {required bool across}) =>
      reading.now.boxCentre == null
      ? null
      : () => reading.now.centreBox(across: across);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      ..._place(),
      _writing(),
      _alignment(),
      _boxWidth(),
      _linePitch(),
      _background(),
    ],
  );

  /// Where the middle of the text in hand's box stands (I-95,
  /// [TextToolSettingsValues.boxCentre]) — in the transform tool's own
  /// boxes and rows: X on the name's line, Y under it. A scrub or a step
  /// carries the text as a hand does, one step back a scrub; a number
  /// typed stands it there exactly. Under them, the two that stand it on
  /// the canvas's middle lines. With none in hand all keep their places,
  /// dimmed.
  List<Widget> _place() {
    final strings = AppText.strings;
    return [
      ToolSettingRow.bar(
        label: strings.trPosition,
        bar: _valueBox(keyValue: 'text-tool-x', name: 'X', across: true),
      ),
      ToolSettingRow.bar(
        label: '',
        bar: _valueBox(keyValue: 'text-tool-y', name: 'Y', across: false),
      ),
      reading.follow(
        (values) => values.boxCentre != null,
        (_) => ToolSettingRow.pair(
          label: '',
          first: ToolSettingAction.glyph(
            keyValue: 'text-tool-centre-across',
            label: strings.textToolCentreAcross,
            glyph: const Icon(Icons.align_horizontal_center),
            shortcuts: const [EditorActionIds.textCentreAcross],
            onPressed: centreOf(reading, across: true),
          ),
          second: ToolSettingAction.glyph(
            keyValue: 'text-tool-centre-down',
            label: strings.textToolCentreDown,
            glyph: const Icon(Icons.align_vertical_center),
            shortcuts: const [EditorActionIds.textCentreDown],
            onPressed: centreOf(reading, across: false),
          ),
        ),
      ),
    ];
  }

  /// One of the place's numbers, X [across] or Y, as it reads — none with
  /// nothing in hand. A box of its own, as each of the transform tool's is
  /// (`_valueBox` there).
  Widget _valueBox({
    required String keyValue,
    required String name,
    required bool across,
  }) => reading.follow(
    (values) {
      final centre = values.boxCentre;
      return centre == null
          ? null
          : columnValueText(across ? centre.dx : centre.dy);
    },
    (number) => DragValueLabel.box(
      keyValue: keyValue,
      name: name,
      text: number ?? '',
      enabled: number != null,
      onDragDelta: (units) => across
          ? reading.now.carryBy(dx: units.round())
          : reading.now.carryBy(dy: units.round()),
      onOperationEnd: () => reading.now.settle(),
      onEditSubmit: (raw) {
        final typed = double.tryParse(raw.trim());
        if (typed == null) {
          return;
        }
        if (across) {
          reading.now.setBoxCentre(x: typed);
        } else {
          reading.now.setBoxCentre(y: typed);
        }
      },
    ),
  );

  /// Lines, or columns (縦書き) — of the text in hand, which is then
  /// written the other way where it stands, and of the next text.
  ///
  /// 🗣️유저 2026-10-06: 「세로쓰기: 1차는 가로만」 → 「어차피 타임시트나
  /// x시트에서 가로쓰기/세로표기같은거 한거 많으니 그거 통합하면서
  /// 진행해도될듯」.
  Widget _writing() {
    final strings = AppText.strings;
    return reading.follow(
      (values) => (vertical: values.vertical, writable: values.writable),
      (shown) => ToolSettingChoiceRow<bool>(
        tool: 'text-tool',
        name: 'writing',
        label: strings.textToolWriting,
        current: shown.vertical,
        answers: [
          (value: false, key: 'lines', label: strings.textToolWritingLines),
          (
            value: true,
            key: 'columns',
            label: strings.textToolWritingColumns,
          ),
        ],
        onPick: (vertical) => shown.writable
            ? () => reading.now.setVertical(vertical)
            : null,
      ),
    );
  }

  /// Where the letters stand along their way: the three answers keep their
  /// values and are NAMED by what they are on screen — the left, the middle
  /// and the right of a line; the top, the middle and the bottom of a
  /// column.
  Widget _alignment() {
    final strings = AppText.strings;
    return reading.follow(
      (values) => (
        align: values.align,
        columns: values.vertical,
        writable: values.writable,
      ),
      (shown) => ToolSettingChoiceRow<TextCelAlign>(
        tool: 'text-tool',
        name: 'align',
        label: strings.textToolAlign,
        current: shown.align,
        answers: [
          for (final (align, label) in [
            (
              TextCelAlign.left,
              shown.columns
                  ? strings.textToolAlignTop
                  : strings.textToolAlignLeft,
            ),
            (TextCelAlign.center, strings.textToolAlignCenter),
            (
              TextCelAlign.right,
              shown.columns
                  ? strings.textToolAlignBottom
                  : strings.textToolAlignRight,
            ),
          ])
            (value: align, key: align.name, label: label),
        ],
        onPick: (align) =>
            shown.writable ? () => reading.now.setAlign(align) : null,
      ),
    );
  }

  /// 「고정할지 비고정할지는 도구설정에서 스왑가능」(유저 2026-10-06) — of the
  /// text in hand: with none, neither is lit and neither is taken.
  Widget _boxWidth() {
    final strings = AppText.strings;
    return reading.follow(
      (values) => (
        wraps: values.wraps,
        toGrow: values.canSetWraps(wraps: false),
        toBox: values.canSetWraps(wraps: true),
      ),
      (shown) => ToolSettingChoiceRow<bool>(
        tool: 'text-tool',
        name: 'box-width',
        label: strings.textToolBoxWidth,
        current: shown.wraps,
        answers: [
          (value: false, key: 'auto', label: strings.textToolWidthAuto),
          (value: true, key: 'fixed', label: strings.textToolWidthFixed),
        ],
        onPick: (boxed) => (boxed ? shown.toBox : shown.toGrow)
            ? () => reading.now.setWraps(boxed)
            : null,
      ),
    );
  }

  /// A line's pitch, read as a share of its letters' size.
  Widget _linePitch() => ToolSettingRow.bar(
    label: AppText.strings.textToolLineHeight,
    bar: reading.follow(
      (values) => (pitch: values.lineHeight, writable: values.writable),
      (shown) => FieldSlider.cell(
        key: const ValueKey<String>('text-tool-line-height'),
        label: AppText.strings.textToolLineHeight,
        min: _tightest,
        max: _loosest,
        divisions: ((_loosest - _tightest) / _pitchStep).round(),
        displayScale: 100,
        unit: '%',
        value: shown.pitch.clamp(_tightest, _loosest),
        onChanged: shown.writable
            ? (pitch) => reading.now.setLineHeight(pitch, settled: false)
            : null,
        onChangeEnd: (pitch) => reading.now.setLineHeight(pitch),
      ),
    ),
  );

  Widget _background() => ToolSettingRow.atEnd(
    label: AppText.strings.textToolBackground,
    child: reading.follow(
      (values) => values.backgroundColor,
      (colour) => ColorSwatchButton(
        keyValue: 'text-tool-background',
        color: colour,
        currentColorOf: currentColorOf,
        onChanged: (argb) =>
            reading.now.setBackgroundColor(argb, settled: false),
        onNone: () => reading.now.setBackgroundColor(null, settled: false),
        onSettled: () => reading.now.settle(),
      ),
    ),
  );
}
