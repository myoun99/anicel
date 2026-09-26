import 'package:flutter/material.dart';

import '../../models/layer_mark.dart';
import '../../models/layer_process.dart';
import '../export/export_settings_modules.dart' show ExportAccordion;
import '../text/app_strings.dart';
import '../widgets/app_window.dart';

/// One name field per colour label, in the order the label popover lists
/// them ([everyLayerMark] — the one enumeration of the labels), each
/// starting at [nameOf] it.
///
/// ⛔EVERY label gets a field, including 用紙's worker: leaving one out
/// would be a 「~는 제외한다」 rule nobody asked for.
Map<LayerMark, TextEditingController> staffFieldsOf(
  String Function(LayerMark mark) nameOf,
) => {
  for (final mark in everyLayerMark())
    if (!mark.isNone) mark: TextEditingController(text: nameOf(mark)),
};

/// The words a folded section shows beside its title: what it holds.
String foldSummary(Iterable<String> words) => [
  for (final word in words)
    if (word.trim().isNotEmpty) word.trim(),
].join(' · ');

/// The staff, a fold per process: its worker, then the corrections it
/// references — the fields of [staffFieldsOf], named as the labels name
/// them (답 staff-roles-from-labels 「공정별 묶음 — 작업자 + 그 공정의 수정
/// 담당」). The work's settings and a cut's settings show it alike.
class StaffProcessFolds extends StatefulWidget {
  const StaffProcessFolds({
    super.key,
    required this.fields,
    required this.keyPrefix,
    this.hintFor,
    this.onSubmitted,
  });

  /// The window's fields, one per label ([staffFieldsOf]).
  final Map<LayerMark, TextEditingController> fields;

  /// What the folds' and the fields' keys start with — the window's name.
  final String keyPrefix;

  /// What an empty field shows faintly: the name the forms print in its
  /// place, or null for none.
  final String? Function(LayerMark mark)? hintFor;

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
        for (final process in LayerProcess.values) _fold(process, strings),
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
                  decoration: InputDecoration(
                    hintText: widget.hintFor?.call(mark),
                  ),
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
