import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import '../widgets/pill_strip.dart';
import 'dialog_verb.dart';

/// What the 「콘티 용지 서식」 window answers: the front the conte book is
/// printed with — its cover, and the blank page behind it.
typedef ConteFormat = ({bool cover, bool blankPage});

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
class ConteFormatWindow extends StatefulWidget {
  const ConteFormatWindow({super.key, required this.initial});

  final ConteFormat initial;

  @override
  State<ConteFormatWindow> createState() => _ConteFormatWindowState();
}

class _ConteFormatWindowState extends State<ConteFormatWindow> {
  late bool _cover = widget.initial.cover;
  late bool _blankPage = widget.initial.blankPage;

  /// One page of the front, put in or left out.
  Widget _page({
    required String label,
    required String keyValue,
    required bool on,
    required ValueChanged<bool> onChanged,
  }) {
    final strings = AppText.strings;
    return AppWindowField(
      label: label,
      child: Align(
        alignment: Alignment.centerLeft,
        child: TogglePill(
          keyValue: keyValue,
          on: on,
          words: (on: strings.conteFrontIn, off: strings.conteFrontOut),
          onChanged: onChanged,
        ),
      ),
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
        onSave: () => Navigator.of(context).pop<ConteFormat>(
          (cover: _cover, blankPage: _blankPage),
        ),
      ),
    );
  }
}
