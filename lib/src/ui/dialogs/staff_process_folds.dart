import 'package:flutter/material.dart';

import '../../models/layer_mark.dart';
import '../../models/layer_process.dart';
import '../export/export_settings_modules.dart' show ExportAccordion;
import '../text/app_strings.dart';
import '../widgets/app_window.dart';

/// One name field per colour label [holder] keeps ([staffHolderOf]), in
/// the order the label popover lists them ([everyLayerMark] — the one
/// enumeration of the labels), each starting at [nameOf] it.
///
/// ⛔EVERY label gets a field, including 用紙's worker: leaving one out
/// would be a 「~는 제외한다」 rule nobody asked for.
/// ↩️The user has asked since (2026-10-05, F-291: 「용지라는 스태프는
/// 없음」): every label but 用紙's — paper is nobody's work. And
/// (2026-10-08, F-291-Q1) each window the stages its holder keeps: the
/// work the conte's, a cut every other.
Map<LayerMark, TextEditingController> staffFieldsOf(
  String Function(LayerMark mark) nameOf, {
  required StaffHolder holder,
}) => {
  for (final mark in everyLayerMark())
    if (mark.process case final process?)
      if (staffHolderOf(process) == holder)
        mark: TextEditingController(text: nameOf(mark)),
};

/// The words a folded section shows beside its title: what it holds.
String foldSummary(Iterable<String> words) => [
  for (final word in words)
    if (word.trim().isNotEmpty) word.trim(),
].join(' · ');

/// The staff, a fold per process: its worker, then the corrections it
/// references — the fields of [staffFieldsOf], named as the labels name
/// them (답 staff-roles-from-labels 「공정별 묶음 — 작업자 + 그 공정의 수정
/// 담당」). The work's settings and a cut's settings show it alike, each
/// with the stages it keeps.
///
/// ↩️A cut's empty field showed the work's name faintly, the name the forms
/// printed in its place — until a cut's stages stopped falling back to the
/// work's (F-291-Q1).
class StaffProcessFolds extends StatefulWidget {
  const StaffProcessFolds({
    super.key,
    required this.fields,
    required this.keyPrefix,
    this.onSubmitted,
  });

  /// The window's fields, one per label ([staffFieldsOf]).
  final Map<LayerMark, TextEditingController> fields;

  /// What the folds' and the fields' keys start with — the window's name.
  final String keyPrefix;

  /// Enter in a field.
  final VoidCallback? onSubmitted;

  @override
  State<StaffProcessFolds> createState() => _StaffProcessFoldsState();
}

class _StaffProcessFoldsState extends State<StaffProcessFolds> {
  final Set<LayerProcess> _folded = {};

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A process with no field here has no fold: 用紙, and the stages the
        // other holder keeps ([staffFieldsOf]).
        for (final process in LayerProcess.values)
          if (widget.fields.keys.any((mark) => mark.process == process))
            _fold(process, strings),
      ],
    );
  }

  /// One process's fold: its worker, then the corrections it references
  /// ([revisesFor], through [everyLayerMark]).
  Widget _fold(LayerProcess process, AppStrings strings) {
    final marks = [
      for (final mark in widget.fields.keys)
        if (mark.process == process) mark,
    ];
    final open = !_folded.contains(process);
    final prefix = widget.keyPrefix;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ExportAccordion(
        key: ValueKey<String>('$prefix-process-${process.jsonValue}'),
        title: strings.layerProcessName(process.jsonValue, process.displayName),
        summary: foldSummary([
          for (final mark in marks) widget.fields[mark]!.text,
        ]),
        expansion: (
          expanded: open,
          onToggle: () => setState(() {
            if (open) {
              _folded.add(process);
            } else {
              _folded.remove(process);
            }
          }),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final mark in marks) ...[
              AppWindowField(
                label: switch (mark.revise) {
                  null => strings.staffWorker,
                  final revise => strings.layerReviseName(
                    revise.jsonValue,
                    revise.displayName,
                  ),
                },
                child: TextField(
                  key: ValueKey<String>('$prefix-staff-${mark.keySlug}'),
                  controller: widget.fields[mark],
                  onSubmitted: (_) => widget.onSubmitted?.call(),
                ),
              ),
              const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }
}
