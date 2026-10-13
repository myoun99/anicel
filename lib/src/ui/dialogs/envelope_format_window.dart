import 'package:flutter/material.dart';

import '../../models/envelope/cut_envelope_presets.dart';
import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import '../widgets/panel_flyout.dart';
import 'dialog_verb.dart';

/// 「컷 봉투 서식」: the cut envelope's settings, in a window of their own as
/// the timesheet's are (`TimesheetFormatWindow`) — the form the work's
/// envelopes are printed on. Pops the id of the form picked, or null when
/// cancelled.
///
/// 🗣️유저 2026-10-12 (I-93): 「컷봉투패널도 마찬가지 … 컷봉투에서
/// 디지털/아날로그 프리셋 변경하는것도 마찬가지. 이런 프리셋 변경은 특히 앱
/// 통틀어서 리스트 팝오버로 구현하도록」 — so the form is picked from a list,
/// the app's one value picker. ↩️It was one button per form on the panel's
/// pill until this window.
class EnvelopeFormatWindow extends StatefulWidget {
  const EnvelopeFormatWindow({super.key, required this.initialFormId});

  final String initialFormId;

  @override
  State<EnvelopeFormatWindow> createState() => _EnvelopeFormatWindowState();
}

class _EnvelopeFormatWindowState extends State<EnvelopeFormatWindow> {
  late String _formId = widget.initialFormId;

  List<PanelFlyoutEntry> _forms() {
    final forms = CutEnvelopePresets.all;
    return forms.asFlyoutValueChoices(
      current: forms.where((form) => form.id == _formId).firstOrNull,
      choiceOf: (form) => PanelFlyoutChoice(
        key: 'envelope-format-form-${form.id}',
        label: form.name,
      ),
      onPicked: (form) => setState(() => _formId = form.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return AppWindow(
      windowKey: const ValueKey<String>('envelope-format-window'),
      title: strings.envelopeFormatTitle,
      titleIcon: Icons.description_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: 460,
      body: SizedBox(
        width: 400,
        child: AppWindowField(
          label: strings.envelopeForm,
          child: Align(
            alignment: Alignment.centerLeft,
            child: PanelFlyoutButton(
              key: const ValueKey<String>('envelope-format-form'),
              label: CutEnvelopePresets.byId(_formId).name,
              entriesBuilder: _forms,
            ),
          ),
        ),
      ),
      actions: saveActions(
        context,
        prefix: 'envelope-format',
        onSave: () => Navigator.of(context).pop<String>(_formId),
      ),
    );
  }
}
