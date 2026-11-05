import 'package:flutter/material.dart';

import '../../models/timesheet_info.dart';
import '../../models/timesheet_sheet_kind.dart';
import '../widgets/app_tooltip.dart';
import '../widgets/app_window.dart';
import 'dialog_verb.dart';
import '../text/app_strings.dart';
import '../text/full_width_numerals.dart';
import '../widgets/pill_strip.dart';
import 'work_and_cut_setting_field.dart';

/// What the 「타임시트 서식」 window answers: the work's sheet format and the
/// paper of the cut the sheet shows — null in the gap, where there is no
/// cut to set it on — and whether it writes its fixed lines (`cutFixedText`
/// — null where none was picked, its `to` null for the format's; F-542).
typedef TimesheetFormat = ({
  TimesheetInfo info,
  TimesheetSheetKind? kind,
  ({bool? to})? cutFixedText,
});

/// 「타임시트 서식」: how the paper timesheet prints — the paper the cut on
/// the sheet prints on, which header boxes it carries, the stretch lines and
/// the fixed lines. Pops the edited [TimesheetFormat], or null when cancelled.
///
/// ⛔The work's words are not here: its title, episode and staff are set in
/// the work's settings (`WorkSettingsWindow`, 유저 09-25 「작품명/화수는
/// 이제 타임시트패널같은곳에서 편집안하게 … 해당 설정은 프로젝트 설정쪽에」).
/// The sheet's own format stays with the sheet's panel (유저 09-25: 「이거는
/// 버튼둬서 바꿀수있게. 타임시트 서식 변경? 뭐 이런 버튼 둬서 창 열어서
/// 관련된거 편집하는창」).
///
/// Every choice is the export window's pill (유저 09-25: 「시트나 머리칸이나
/// 이런 설정 토글은 기존 출력창의 토글같은거 버튼 재사용해서 알기쉽게」):
/// the header boxes are one strip with several on at once, and each yes/no
/// is one [TogglePill].
class TimesheetFormatWindow extends StatefulWidget {
  const TimesheetFormatWindow({
    super.key,
    required this.initialInfo,
    this.sheet,
  });

  final TimesheetInfo initialInfo;

  /// The cut the sheet shows: the paper it chose, the cel columns its
  /// sheet prints and the frames a second it counts — what decides which
  /// papers it can print on ([sheetKindRefusal]) — the words that say which
  /// cut, and the fixed text it keeps (null for the format's). Null in the
  /// gap.
  final ({
    TimesheetSheetKind kind,
    int celColumns,
    int fps,
    String words,
    bool? fixedText,
  })?
  sheet;

  @override
  State<TimesheetFormatWindow> createState() => _TimesheetFormatWindowState();
}

class _TimesheetFormatWindowState extends State<TimesheetFormatWindow> {
  late final Set<TimesheetHeaderField> _hiddenFields = {
    ...widget.initialInfo.hiddenFields,
  };
  late final _StretchLine _actionLine = _StretchLine(
    widget.initialInfo.exposureBarThreshold,
    suggested: TimesheetInfo.defaultExposureBarThreshold,
  );
  late final _StretchLine _cellLine = _StretchLine(
    widget.initialInfo.cellExposureBarThreshold,
    suggested: TimesheetInfo.defaultCellExposureBarThreshold,
  );
  late TimesheetSheetKind? _kind = widget.sheet?.kind;
  late bool _fixedText = widget.initialInfo.sheetFixedText;

  /// The cut's own fixed text as picked — null until one is, so saving
  /// leaves it as it stands.
  ({bool? to})? _cutFixedText;

  static String _fieldLabel(TimesheetHeaderField field) {
    final strings = AppText.strings;
    return switch (field) {
      TimesheetHeaderField.title => strings.sheetFieldTitle,
      TimesheetHeaderField.episode => strings.sheetFieldEpisode,
      TimesheetHeaderField.scene => strings.sheetFieldScene,
      TimesheetHeaderField.cut => strings.sheetFieldCut,
      TimesheetHeaderField.time => strings.sheetFieldTime,
      TimesheetHeaderField.name => strings.sheetFieldName,
      TimesheetHeaderField.sheet => strings.sheetFieldSheet,
    };
  }

  @override
  void dispose() {
    _actionLine.n.dispose();
    _cellLine.n.dispose();
    super.dispose();
  }

  void _submit() {
    // 🚨★★★copyWith, NOT a fresh TimesheetInfo. Building one from scratch
    // listed the fields this dialog edits and silently dropped every field
    // it does not — `staff` and `logoAssetPath` both default to empty, so
    // opening this window and pressing save WIPED the production staff and
    // the logo. Nothing said so; they simply were not there afterwards.
    //
    // ⛔A re-construction cannot be made safe by remembering to add the
    // next field: remembering is the part that failed. `copyWith` carries
    // what it was not asked about ([[make-the-invariant-unrepresentable]]).
    final format = (
      info: widget.initialInfo.copyWith(
        hiddenFields: {..._hiddenFields},
        exposureBarThreshold: () => _actionLine.threshold,
        cellExposureBarThreshold: () => _cellLine.threshold,
        sheetFixedText: _fixedText,
      ),
      kind: _kind,
      cutFixedText: _cutFixedText,
    );
    Navigator.of(context).pop(format);
  }

  /// The papers the cut prints on, [kinds] of them in a strip, the one the
  /// sheet prints on now lit — one choice across our sheets' strip and the
  /// XDTS Viewer's (I-162). A paper the cut cannot print on keeps its pill,
  /// takes no tap and says why ([sheetKindRefusal]); in the gap none takes
  /// one.
  Widget _papers(List<TimesheetSheetKind> kinds) {
    final sheet = widget.sheet;
    final chosen = _kind;
    final printed = sheet == null || chosen == null
        ? TimesheetSheetKind.sixSeconds
        : sheetKindFor(chosen, celColumns: sheet.celColumns, fps: sheet.fps);
    PillItem paper(TimesheetSheetKind kind) {
      final refusal = sheet == null
          ? null
          : sheetKindRefusal(
              kind,
              celColumns: sheet.celColumns,
              fps: sheet.fps,
            );
      return PillItem(
        keyValue: 'timesheet-format-paper-${kind.jsonValue}',
        label: AppText.strings.sheetKindName(kind),
        selected: kind == printed,
        tooltip: sheet == null || refusal == null
            ? null
            : AppText.strings.sheetKindRefused(
                refusal,
                celColumns: sheet.celColumns,
              ),
        onTap: sheet != null && refusal == null
            ? () => setState(() => _kind = kind)
            : null,
      );
    }

    return PillStrip(items: [for (final kind in kinds) paper(kind)]);
  }

  void _toggleField(TimesheetHeaderField field) => setState(() {
    if (!_hiddenFields.remove(field)) {
      _hiddenFields.add(field);
    }
  });

  Widget _headerBoxes() => PillStrip(
    items: [
      for (final field in TimesheetHeaderField.values)
        PillItem(
          keyValue: 'timesheet-format-visible-${field.name}',
          label: _fieldLabel(field),
          selected: !_hiddenFields.contains(field),
          onTap: () => _toggleField(field),
        ),
    ],
  );

  /// One block's stretch line, [label]led: whether it is drawn, and from
  /// how long a run. The ACTION and CELL blocks each have one, set apart
  /// (F-430).
  Widget _stretchLine(String label, String keyValue, _StretchLine line) {
    final strings = AppText.strings;
    return AppWindowField(
      label: label,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TogglePill(
              keyValue: keyValue,
              on: line.on,
              words: (
                on: strings.sheetStretchLineOn,
                off: strings.sheetStretchLineOff,
              ),
              onChanged: (on) => setState(() => line.on = on),
            ),
            const SizedBox(width: 12),
            // The threshold keeps its place while the line is off, refusing
            // input rather than leaving (「없다가 생기는 UI 금지」) — it used
            // to appear only once the line was switched on.
            AppTooltip(
              message: strings.sheetStretchLineHelp,
              child: SizedBox(
                width: 72,
                child: TextField(
                  key: ValueKey<String>('$keyValue-threshold'),
                  controller: line.n,
                  enabled: line.on,
                  keyboardType: TextInputType.number,
                  inputFormatters: halfWidthDigitsOnly,
                  decoration: const InputDecoration(prefixText: 'N  '),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Whether a page writes its fixed lines: the whole work's and the cut's,
  /// as the conte's window sets its own (F-542).
  Widget _fixedTextField() {
    final strings = AppText.strings;
    return FixedTextSettingField(
      work: TogglePill(
        keyValue: 'timesheet-format-fixed-text',
        on: _fixedText,
        words: (on: strings.conteOutlineOn, off: strings.conteOutlineOff),
        onChanged: (on) => setState(() => _fixedText = on),
      ),
      keyValue: 'timesheet-format-cut-fixed-text',
      cutWords: widget.sheet?.words,
      picked: _cutFixedText,
      stands: widget.sheet?.fixedText,
      onPicked: (on) => setState(() => _cutFixedText = (to: on)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return AppWindow(
      windowKey: const ValueKey<String>('timesheet-format-window'),
      title: strings.sheetFormatTitle,
      titleIcon: Icons.description_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: 460,
      // ⛔The body does NOT bring its own scroller. `AppWindow` already
      // scrolls it, and it applies the body padding OUTSIDE that scroller —
      // so the window's bar lands on 12px of dead padding, while a bar
      // belonging to a scroller in HERE would lie across the right edge of
      // every field and swallow the taps that focus them.
      body: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            AppWindowField(
              label: strings.sheetLength,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _papers(const [
                  TimesheetSheetKind.threeSeconds,
                  TimesheetSheetKind.sixSeconds,
                ]),
              ),
            ),
            AppWindowField(
              label: strings.sheetXdtsPapers,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _papers([
                  for (final kind in TimesheetSheetKind.values)
                    if (kind.xdts != null) kind,
                ]),
              ),
            ),
            AppWindowField(
              label: strings.sheetVisibleBoxes,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _headerBoxes(),
              ),
            ),
            _stretchLine(
              strings.sheetStretchLineAction,
              'timesheet-format-stretch-line-action',
              _actionLine,
            ),
            _stretchLine(
              strings.sheetStretchLineCell,
              'timesheet-format-stretch-line-cell',
              _cellLine,
            ),
            _fixedTextField(),
          ],
        ),
      ),
      actions: saveActions(
        context,
        prefix: 'timesheet-format',
        onSave: _submit,
      ),
    );
  }
}

/// One block's stretch line as the window edits it: whether it is drawn
/// ([on]) and the run it starts past ([n]) — kept while the line is off,
/// so switching it back on brings the same N back.
class _StretchLine {
  _StretchLine(int? threshold, {required this.suggested})
    : on = threshold != null,
      n = TextEditingController(text: '${threshold ?? suggested}');

  bool on;
  final TextEditingController n;

  /// The N a line switched on starts from when its field holds none.
  final int suggested;

  /// The threshold the work keeps: null when the line is off.
  int? get threshold =>
      on ? (halfWidthInt(n.text) ?? suggested).clamp(1, 999) : null;
}
