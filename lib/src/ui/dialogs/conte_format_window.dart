import 'package:flutter/material.dart';

import '../../models/conte/conte_sheet_form.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/pill_strip.dart';
import 'dialog_verb.dart';

/// What the 「콘티 용지 서식」 window answers: the form the sheet is printed
/// in and whether its pictures stand in the black, the front the conte
/// book is printed with — its cover, and the blank page behind it — and
/// whether a cell writes what its camera does (I-93).
typedef ConteFormat = ({
  ConteSheetForm form,
  bool outlined,
  bool cover,
  bool blankPage,
  bool fixedText,
});

/// 「콘티 용지 서식」: the conte sheet's settings, in a window of their own
/// as the timesheet's are (`TimesheetFormatWindow`). Pops the edited
/// [ConteFormat], or null when cancelled.
///
/// 🗣️유저 2026-10-12 (I-93): 「타임시트처럼 전용 설정창 만들어서 거기다 표지
/// 빈용지체크 이런거 다 넣고 … 캔버스 베이스 패널은 무언가 설정할게 있다면
/// 설정버튼만들어서 누르면 창 열려서 거기서 설정하도록」. ↩️The two switches
/// were rows of the panel's settings list from I-59 (10-07) until this
/// window, each a row a key pressed (I-40); a button in a window takes no
/// key (I-40-Q1), so the key is the one that opens the window.
///
/// The form is picked from a list, as the envelope's is (I-93: 「이런 프리셋
/// 변경은 특히 앱 통틀어서 리스트 팝오버로」), and the outline is either
/// form's (유저 2026-10-21, I-118: 「서식 옵션으로 공통적용되게 화면에 검은
/// 외곽선 적용/미적용 버튼」).
class ConteFormatWindow extends StatefulWidget {
  const ConteFormatWindow({super.key, required this.initial});

  final ConteFormat initial;

  @override
  State<ConteFormatWindow> createState() => _ConteFormatWindowState();
}

class _ConteFormatWindowState extends State<ConteFormatWindow> {
  late ConteSheetForm _form = widget.initial.form;
  late bool _outlined = widget.initial.outlined;
  late bool _cover = widget.initial.cover;
  late bool _blankPage = widget.initial.blankPage;
  late bool _fixedText = widget.initial.fixedText;

  static String _formName(ConteSheetForm form) => switch (form) {
    ConteSheetForm.analog => AppText.strings.conteFormAnalog,
    ConteSheetForm.digital => AppText.strings.conteFormDigital,
  };

  /// One row of the window: [label], and what sets it.
  static Widget _field(String label, Widget child) => AppWindowField(
    label: label,
    child: Align(alignment: Alignment.centerLeft, child: child),
  );

  /// The forms, the one picked lit.
  List<PanelFlyoutEntry> _forms() => ConteSheetForm.values.asFlyoutChoices(
    current: _form,
    keyPrefix: 'conte-format-form-',
    labelOf: _formName,
    onPicked: (form) => setState(() => _form = form),
  );

  /// One page of the front, put in or left out.
  Widget _page(String keyValue, bool on, ValueChanged<bool> onChanged) {
    final strings = AppText.strings;
    return TogglePill(
      keyValue: keyValue,
      on: on,
      words: (on: strings.conteFrontIn, off: strings.conteFrontOut),
      onChanged: onChanged,
    );
  }

  /// Whether each cell writes what its camera does over its ACTION words
  /// (🗣️I-93, 유저 2026-10-12: 「고정텍스트 표기할지 안할지 콘티용지패널에
  /// 설정할수있도록」).
  Widget _fixedTextSwitch() {
    final strings = AppText.strings;
    return TogglePill(
      keyValue: 'conte-format-fixed-text',
      on: _fixedText,
      // ⚠️Mine: the outline's words — a plain on and off in every language.
      words: (on: strings.conteOutlineOn, off: strings.conteOutlineOff),
      onChanged: (on) => setState(() => _fixedText = on),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return AppWindow(
      windowKey: const ValueKey<String>('conte-format-window'),
      title: strings.conteFormatTitle,
      titleIcon: Icons.description_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: 460,
      body: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            _field(
              strings.conteForm,
              PanelFlyoutButton(
                key: const ValueKey<String>('conte-format-form'),
                label: _formName(_form),
                entriesBuilder: _forms,
              ),
            ),
            _field(
              strings.conteOutline,
              TogglePill(
                keyValue: 'conte-format-outline',
                on: _outlined,
                words: (on: strings.conteOutlineOn, off: strings.conteOutlineOff),
                onChanged: (on) => setState(() => _outlined = on),
              ),
            ),
            _field(
              strings.conteCoverPage,
              _page(
                'conte-format-cover',
                _cover,
                (on) => setState(() => _cover = on),
              ),
            ),
            _field(
              strings.conteBlankPage,
              _page(
                'conte-format-blank-page',
                _blankPage,
                (on) => setState(() => _blankPage = on),
              ),
            ),
            _field(strings.conteFixedText, _fixedTextSwitch()),
          ],
        ),
      ),
      actions: saveActions(
        context,
        prefix: 'conte-format',
        onSave: () => Navigator.of(context).pop<ConteFormat>(_edited),
      ),
    );
  }

  ConteFormat get _edited => (
    form: _form,
    outlined: _outlined,
    cover: _cover,
    blankPage: _blankPage,
    fixedText: _fixedText,
  );
}
