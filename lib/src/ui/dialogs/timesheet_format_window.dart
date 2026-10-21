import 'package:flutter/material.dart';

import '../../models/timesheet_info.dart';
import '../../models/timesheet_sheet_kind.dart';
import '../widgets/app_tooltip.dart';
import '../widgets/app_window.dart';
import 'dialog_verb.dart';
import '../text/app_strings.dart';
import '../text/full_width_numerals.dart';
import '../widgets/pill_strip.dart';

/// What the 「타임시트 서식」 window answers: the work's sheet format and the
/// paper of the cut the sheet shows — null in the gap, where there is no
/// cut to set it on.
typedef TimesheetFormat = ({TimesheetInfo info, TimesheetSheetKind? kind});

/// 「타임시트 서식」: how the paper timesheet prints — the paper the cut on
/// the sheet prints on, which header boxes it carries, the stretch lines,
/// the SE wash. Pops the edited [TimesheetFormat], or null when cancelled.
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

  /// The cut the sheet shows: the paper it chose, and the cel columns its
  /// sheet prints — what decides whether the 6-second sheet holds them
  /// ([sheetKindFits]). Null in the gap.
  final ({TimesheetSheetKind kind, int celColumns})? sheet;

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
  late bool _seEmptyFill = widget.initialInfo.seEmptyFill;
  late TimesheetSheetKind? _kind = widget.sheet?.kind;

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
        seEmptyFill: _seEmptyFill,
      ),
      kind: _kind,
    );
    Navigator.of(context).pop(format);
  }

  /// The paper the cut prints on: one strip, one of its two pills lit —
  /// the paper the sheet prints on now. A paper the cut's cel columns do
  /// not fit keeps its pill and takes no tap (유저 2026-09-25,
  /// timesheet-sheet-capacity-Q1 「3초 시트로 고정(6초 끔)」); in the gap
  /// neither does.
  Widget _paper() {
    final sheet = widget.sheet;
    final chosen = _kind;
    final printed = sheet == null || chosen == null
        ? TimesheetSheetKind.sixSeconds
        : sheetKindFor(chosen, celColumns: sheet.celColumns);
    return PillStrip(
      items: [
        for (final kind in const [
          TimesheetSheetKind.threeSeconds,
          TimesheetSheetKind.sixSeconds,
        ])
          PillItem(
            keyValue: 'timesheet-format-paper-${kind.jsonValue}',
            label: AppText.strings.sheetKindName(kind),
            selected: kind == printed,
            onTap:
                sheet != null &&
                    sheetKindFits(kind, celColumns: sheet.celColumns)
                ? () => setState(() => _kind = kind)
                : null,
          ),
      ],
    );
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

  Widget _seWash() {
    final strings = AppText.strings;
    return AppWindowField(
      label: strings.sheetSeEmptyFill,
      child: Align(
        alignment: Alignment.centerLeft,
        child: TogglePill(
          keyValue: 'timesheet-format-se-empty-fill',
          on: _seEmptyFill,
          words: (on: strings.sheetFillOn, off: strings.sheetFillOff),
          onChanged: (on) => setState(() => _seEmptyFill = on),
        ),
      ),
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
              child: Align(alignment: Alignment.centerLeft, child: _paper()),
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
            _seWash(),
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
