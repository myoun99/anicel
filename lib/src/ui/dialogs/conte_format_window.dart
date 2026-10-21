import 'package:flutter/material.dart';

import '../../models/conte/conte_sheet_form.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import '../widgets/panel_flyout.dart';
import '../widgets/pill_strip.dart';
import 'dialog_verb.dart';

/// What the 「콘티 용지 서식」 window answers: the form the sheet is printed
/// in and whether its pictures stand in the black, and the front the conte
/// book is printed with — its cover, and the blank page behind it.
typedef ConteFormat = ({
  ConteSheetForm form,
  bool outlined,
  bool cover,
  bool blankPage,
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

  static String _formName(ConteSheetForm form) => switch (form) {
    ConteSheetForm.analog => AppText.strings.conteFormAnalog,
    ConteSheetForm.digital => AppText.strings.conteFormDigital,
  };

  /// One yes/no of the sheet, said in [words].
  Widget _toggle({
    required String label,
    required String keyValue,
    required bool on,
    required ({String on, String off}) words,
    required ValueChanged<bool> onChanged,
  }) => AppWindowField(
    label: label,
    child: Align(
      alignment: Alignment.centerLeft,
      child: TogglePill(
        keyValue: keyValue,
        on: on,
        words: words,
        onChanged: onChanged,
      ),
    ),
  );

  /// One page of the front, put in or left out.
  Widget _page({
    required String label,
    required String keyValue,
    required bool on,
    required ValueChanged<bool> onChanged,
  }) {
    final strings = AppText.strings;
    return _toggle(
      label: label,
      keyValue: keyValue,
      on: on,
      words: (on: strings.conteFrontIn, off: strings.conteFrontOut),
      onChanged: onChanged,
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
            AppWindowField(
              label: strings.conteForm,
              child: Align(
                alignment: Alignment.centerLeft,
                child: PanelFlyoutButton(
                  key: const ValueKey<String>('conte-format-form'),
                  label: _formName(_form),
                  entriesBuilder: () => ConteSheetForm.values.asFlyoutChoices(
                    current: _form,
                    keyPrefix: 'conte-format-form-',
                    labelOf: _formName,
                    onPicked: (form) => setState(() => _form = form),
                  ),
                ),
              ),
            ),
            _toggle(
              label: strings.conteOutline,
              keyValue: 'conte-format-outline',
              on: _outlined,
              words: (on: strings.conteOutlineOn, off: strings.conteOutlineOff),
              onChanged: (on) => setState(() => _outlined = on),
            ),
            _page(
              label: strings.conteCoverPage,
              keyValue: 'conte-format-cover',
              on: _cover,
              onChanged: (on) => setState(() => _cover = on),
            ),
            _page(
              label: strings.conteBlankPage,
              keyValue: 'conte-format-blank-page',
              on: _blankPage,
              onChanged: (on) => setState(() => _blankPage = on),
            ),
          ],
        ),
      ),
      actions: saveActions(
        context,
        prefix: 'conte-format',
        onSave: () => Navigator.of(context).pop<ConteFormat>((
          form: _form,
          outlined: _outlined,
          cover: _cover,
          blankPage: _blankPage,
        )),
      ),
    );
  }
}
