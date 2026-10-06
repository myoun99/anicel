import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/text_cel_style.dart';
import '../../services/cel_text_box_edits.dart' show celTextMinFontSize;
import '../canvas/text/cel_text_tool.dart';
import '../dialogs/app_confirm_dialog.dart' show showAppNotice;
import '../text/app_strings.dart';
import '../text/canvas_letter_faces.dart';
import '../text/imported_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/color_swatch_button.dart';
import '../widgets/field_slider.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/pill_strip.dart';
import '../widgets/settings_rows.dart';
import 'cel_text_commands.dart';
import 'text_tool_options.dart';
import 'text_tool_settings_values.dart';
import 'tool_settings_section.dart';

/// The TEXT tool's settings (R9-rest) — mounted by the tool settings panel
/// like every other tool's (유저: 툴 설정은 툴 설정 패널에).
///
/// The layout is the one 유저 took on 2026-10-06, top to bottom: the text in
/// hand and its delete · **글자** — face, size, tracking, bold, colour,
/// outline, outline width · **상자** — alignment, box width, line spacing,
/// background.
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

  /// The brush's colour — what 「현재 색 반영」 copies into a colour here.
  /// Null where there is no brush to read.
  final int Function()? currentColorOf;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // ⚠️Not the fonts: the list of faces is made when it OPENS, and nothing
    // on the row itself is read from them.
    listenable: Listenable.merge([?options, ?commands]),
    builder: (context, _) {
      final values = TextToolSettingsValues(
        options: options,
        tool: commands?.tool,
      );
      final strings = AppText.strings;
      return ToolSettingsSection(
        tool: 'text',
        title: strings.toolText,
        children: [
          const SizedBox(height: 8),
          _TextInHandRow(commands: commands),
          ToolSettingsGroupHeader(strings.textToolLetters),
          _LetterRows(
            values: values,
            currentColorOf: currentColorOf,
            fonts: fonts,
          ),
          ToolSettingsGroupHeader(strings.textToolBox),
          _BoxRows(values: values, currentColorOf: currentColorOf),
        ],
      );
    },
  );
}

/// What a value several letters do not agree on reads as (유저 2026-10-06).
const String _mixed = '—';

/// The gap between two bars, as every section of the panel keeps it.
const SizedBox _gap = SizedBox(height: 8);

/// The text in hand, by its own letters — and the list of the cel's texts
/// it is picked from. 유저 2026-10-06: 「도구설정에 선택된 텍스트라는 항목이
/// 있었으면 좋겠음. 거기서 다른 텍스트 선택할수있게 리스트 고르는. 팝오버로
/// 리스트 고를수있게하고. 텍스트의 이름은 그냥 텍스트 글자대로. 그리고 옆에
/// 삭제버튼 있고」 — a delete beside the field, and one on every row of the
/// list (the drawing taken with it: 「1 ok」).
class _TextInHandRow extends StatelessWidget {
  const _TextInHandRow({required this.commands});

  final CelTextCommands? commands;

  /// A text's name is its own letters on ONE line: its breaks are not its
  /// name's.
  static String _nameOf(String text) => text.replaceAll('\n', ' ');

  @override
  Widget build(BuildContext context) {
    final tool = commands?.tool;
    final inHand = tool?.contentInHand;
    return Row(
      children: [
        Expanded(
          child: PanelFlyoutButton(
            key: const ValueKey<String>('text-tool-selected-text'),
            label: inHand == null ? '' : _nameOf(inHand.text),
            tooltip: AppText.strings.textToolSelectedText,
            expand: true,
            // With no text on the cel there is none to pick.
            enabled: tool != null && tool.list.texts.isNotEmpty,
            entriesBuilder: () => _listOf(tool),
          ),
        ),
        const SizedBox(width: 4),
        AppIconButton(
          keyValue: 'text-tool-delete-text',
          tooltip: AppText.strings.textToolDeleteText,
          icon: Icon(
            Icons.delete_outline,
            color: AppColors.deleteGlyph(enabled: inHand != null),
          ),
          onPressed: inHand == null ? null : commands?.deleteText,
        ),
      ],
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
    required this.values,
    required this.currentColorOf,
    required this.fonts,
  });

  final TextToolSettingsValues values;
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
  Widget build(BuildContext context) {
    final bold = values.letter((style) => style.bold);
    final outlined = values.letter((style) => style.outlineColor != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _FaceRow(values: values, fonts: fonts),
        _gap,
        _bar(_LetterNumber.size),
        _gap,
        _bar(_LetterNumber.tracking),
        SettingsSwitchRow(
          tileKey: const ValueKey<String>('text-tool-bold'),
          label: AppText.strings.textToolBold,
          value: !bold.mixed && bold.value,
          mixed: bold.mixed,
          onChanged: values.writable
              ? (on) => values.setLetters((style) => style.copyWith(bold: on))
              : null,
        ),
        _colour(),
        _outline(),
        _gap,
        // A width with no colour is no outline: until the letters have one
        // there is nothing for it to be the width of.
        _bar(
          _LetterNumber.outlineWidth,
          live: outlined.mixed || outlined.value,
        ),
      ],
    );
  }

  /// One number of the letters as a bar: dragged it shows, and where the
  /// hand lets go it lands.
  Widget _bar(_LetterNumber number, {bool live = true}) {
    final bar = _barOf(number);
    final shown = values.letter(bar.read);
    void set(double value, {required bool settled}) => values.setLetters(
      (style) => bar.write(style, value),
      settled: settled,
    );
    return FieldSlider(
      key: ValueKey<String>('text-tool-${bar.name}'),
      label: bar.label,
      min: bar.min,
      max: bar.max,
      scale: bar.scale,
      divisions: bar.divisions,
      unit: bar.unit,
      value: shown.value.clamp(bar.min, bar.max),
      valueTextBuilder: shown.mixed ? (_, _) => _mixed : null,
      onChanged: values.writable && live
          ? (value) => set(value, settled: false)
          : null,
      onChangeEnd: (value) => set(value, settled: true),
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

  Widget _colour() {
    final colour = values.letter((style) => style.color);
    return _SettingRow(
      label: AppText.strings.textToolColor,
      child: ColorSwatchButton(
        keyValue: 'text-tool-color',
        color: colour.value,
        mixed: colour.mixed,
        currentColorOf: currentColorOf,
        onChanged: (argb) => values.setLetters(
          (style) => style.copyWith(color: argb),
          settled: false,
        ),
        onSettled: values.settle,
      ),
    );
  }

  Widget _outline() {
    final outline = values.letter((style) => style.outlineColor);
    void set(int? argb) => values.setLetters(
      (style) => style.copyWith(outlineColor: argb),
      settled: false,
    );
    return _SettingRow(
      label: AppText.strings.textToolOutline,
      child: ColorSwatchButton(
        keyValue: 'text-tool-outline',
        color: outline.value,
        mixed: outline.mixed,
        currentColorOf: currentColorOf,
        onChanged: set,
        onNone: () => set(null),
        onSettled: values.settle,
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
  const _FaceRow({required this.values, required this.fonts});

  final TextToolSettingsValues values;
  final ImportedFonts? fonts;

  static const List<String?> _appFaces = [
    null,
    ...AppTypography.bundledFallback,
  ];

  static String _nameOf(String? family) =>
      family ?? AppTypography.bundledFamily;

  @override
  Widget build(BuildContext context) {
    final face = values.letter((style) => style.fontFamily);
    return PanelFlyoutButton(
      key: const ValueKey<String>('text-tool-font'),
      label: face.mixed ? _mixed : _nameOf(face.value),
      tooltip: AppText.strings.textToolFont,
      expand: true,
      enabled: values.writable,
      entriesBuilder: () => _faces(context, inUse: face),
    );
  }

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
  ) {
    final strings = AppText.strings;
    return [
      if (carried.isNotEmpty) ...[
        const PanelFlyoutDivider(),
        PanelFlyoutHeader(strings.textToolFontsOfProject),
      ],
      for (final family in carried)
        PanelFlyoutItem(
          keyValue: 'text-tool-project-font-$family',
          label: family,
          selected: isInUse(family),
          // Registered, and its bytes are nowhere this device can read: it
          // is the project's all the same, and says why its letters show
          // in another face.
          warning: CanvasLetterFaces.current.holds(family)
              ? null
              : strings.textToolFontNotOnThisDevice,
          onSelected: () => _pick(family),
          action: PanelFlyoutRowAction(
            keyValue: 'text-tool-project-font-$family-take-out',
            icon: Icons.remove,
            tooltip: strings.textToolFontTakeOut,
            does: PanelFlyoutActionDoes.deletes,
            onPressed: () => fonts.takeOutOfProject(family),
          ),
        ),
    ];
  }

  /// The fonts THIS DEVICE was brought, under their own heading — none of
  /// either, on a device that was brought none.
  List<PanelFlyoutEntry> _ofTheDevice(
    ImportedFonts fonts,
    List<ImportedFontFamily> brought,
    bool Function(String? family) isInUse,
  ) {
    final strings = AppText.strings;
    return [
      if (brought.isNotEmpty) ...[
        const PanelFlyoutDivider(),
        PanelFlyoutHeader(strings.textToolFontsOfDevice),
      ],
      for (final family in brought)
        PanelFlyoutItem(
          keyValue: 'text-tool-font-${family.name}',
          label: family.name,
          selected: isInUse(family.name),
          warning: family.ridesInEditedDocuments
              ? null
              : strings.textToolFontStaysOnThisDevice,
          onSelected: () => _pick(family.name),
          action: PanelFlyoutRowAction(
            keyValue: 'text-tool-font-${family.name}-delete',
            icon: Icons.delete_outline,
            tooltip: strings.textToolFontDelete,
            does: PanelFlyoutActionDoes.deletes,
            onPressed: () => unawaited(fonts.delete(family.name)),
          ),
        ),
    ];
  }

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
    values.setLetters((style) => style.copyWith(fontFamily: family));
  }

  /// The ＋: picks a file and brings it as a font — and the face brought is
  /// the face picked, for the ＋ stands in the list a face is picked from.
  ///
  /// A file that is not taken says why. So does one that IS taken and may
  /// not ride in a project (유저 2026-10-06: 「글꼴을 등록할때? 사용할때든
  /// 뭐든 글꼴 고를때든 … 적어두자」 — when it is registered is the first of
  /// those, and its row in the list says it from then on).
  Future<void> _bring(BuildContext context, ImportedFonts fonts) async {
    final outcome = await fonts.importFromFile();
    final family = outcome.family;
    if (family != null) {
      _pick(family);
    }
    final rides = family == null
        ? null
        : fonts.familyNamed(family)?.ridesInEditedDocuments;
    final notice =
        outcome.refusal ??
        (rides == false ? AppText.strings.textToolFontStaysOnThisDevice : null);
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
  const _BoxRows({required this.values, required this.currentColorOf});

  final TextToolSettingsValues values;
  final int Function()? currentColorOf;

  /// The line pitches set from here, as multiples of the letters' size, and
  /// the step between two of them.
  static const double _tightest = 0.5;
  static const double _loosest = 3;
  static const double _pitchStep = 0.05;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [_alignment(), _boxWidth(), _gap, _linePitch(), _background()],
  );

  Widget _alignment() {
    final strings = AppText.strings;
    return _ChoiceRow<TextCelAlign>(
      name: 'align',
      label: strings.textToolAlign,
      current: values.align,
      answers: [
        for (final (align, label) in [
          (TextCelAlign.left, strings.textToolAlignLeft),
          (TextCelAlign.center, strings.textToolAlignCenter),
          (TextCelAlign.right, strings.textToolAlignRight),
        ])
          (value: align, key: align.name, label: label),
      ],
      onPick: (align) =>
          values.writable ? () => values.setAlign(align) : null,
    );
  }

  /// 「고정할지 비고정할지는 도구설정에서 스왑가능」(유저 2026-10-06) — of the
  /// text in hand: with none, neither is lit and neither is taken.
  Widget _boxWidth() {
    final strings = AppText.strings;
    return _ChoiceRow<bool>(
      name: 'box-width',
      label: strings.textToolBoxWidth,
      current: values.wraps,
      answers: [
        (value: false, key: 'auto', label: strings.textToolWidthAuto),
        (value: true, key: 'fixed', label: strings.textToolWidthFixed),
      ],
      onPick: (boxed) => values.canSetWraps(wraps: boxed)
          ? () => values.setWraps(boxed)
          : null,
    );
  }

  /// A line's pitch, read as a share of its letters' size.
  Widget _linePitch() => FieldSlider(
    key: const ValueKey<String>('text-tool-line-height'),
    label: AppText.strings.textToolLineHeight,
    min: _tightest,
    max: _loosest,
    divisions: ((_loosest - _tightest) / _pitchStep).round(),
    displayScale: 100,
    unit: '%',
    value: values.lineHeight.clamp(_tightest, _loosest),
    onChanged: values.writable
        ? (pitch) => values.setLineHeight(pitch, settled: false)
        : null,
    onChangeEnd: values.setLineHeight,
  );

  Widget _background() => _SettingRow(
    label: AppText.strings.textToolBackground,
    child: ColorSwatchButton(
      keyValue: 'text-tool-background',
      color: values.backgroundColor,
      currentColorOf: currentColorOf,
      onChanged: (argb) => values.setBackgroundColor(argb, settled: false),
      onNone: () => values.setBackgroundColor(null, settled: false),
      onSettled: values.settle,
    ),
  );
}

/// A setting that is ONE OF A FEW ANSWERS, as the app's one grouped choice
/// ([PillStrip]) at the end of its line: the answer it is at lit, each
/// answer taking a press or refusing it as [onPick] says of that answer.
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.name,
    required this.label,
    required this.answers,
    required this.current,
    required this.onPick,
  });

  /// What the strip and its pills are keyed by: `text-tool-<name>`, and
  /// `text-tool-<name>-<key>` for each answer.
  final String name;
  final String label;
  final List<({T value, String key, String label})> answers;

  /// The answer the setting is at — null where it is at none of them, and
  /// no pill is lit.
  final T? current;

  /// What a press on [answer] does; null where that answer is refused —
  /// the pill keeps its place and loses its tap.
  final VoidCallback? Function(T answer) onPick;

  @override
  Widget build(BuildContext context) => _SettingRow(
    label: label,
    child: PillStrip(
      key: ValueKey<String>('text-tool-$name'),
      items: [
        for (final answer in answers)
          PillItem(
            keyValue: 'text-tool-$name-${answer.key}',
            label: answer.label,
            selected: answer.value == current,
            onTap: onPick(answer.value),
          ),
      ],
    ),
  );
}

/// A setting whose control stands at the end of its line — a swatch, a
/// strip of pills — its name where the line begins: the row the brush's
/// settings write a labelled picker in.
class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(width: 8),
        Expanded(
          child: Align(alignment: Alignment.centerRight, child: child),
        ),
      ],
    ),
  );
}
