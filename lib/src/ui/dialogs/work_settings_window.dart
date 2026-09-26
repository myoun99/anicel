import 'package:flutter/material.dart';

import '../../models/layer_mark.dart';
import '../../models/layer_process.dart';
import '../../models/timesheet_info.dart';
import '../export/export_settings_modules.dart' show ExportAccordion;
import '../text/app_strings.dart';
import '../widgets/app_window.dart';

/// 작품 설정 — the work's words every paper form prints: its title, its
/// episode, and who does each stage's work. Pops the edited
/// [TimesheetInfo], or null when cancelled.
///
/// 🗣️유저 09-25 (project-settings-window): 「작품명/화수는 이제
/// 타임시트패널같은곳에서 편집안하게. 작업자든 뭐든. 해당 설정은 프로젝트
/// 설정쪽에 버튼둬서. 상단띠의 설정버튼이 낫겟지」 — so it opens from the top
/// strip's ⚙, and the sheets only print what it holds.
///
/// Two folds, named as the user named them — 「작품설정이나 스태프설정
/// 접을수있게. 기본값은 스태프설정만 접기」. The staff is the colour labels':
/// a fold per process, its worker and the corrections it references (답
/// staff-roles-from-labels 「공정별 묶음 — 작업자 + 그 공정의 수정 담당」).
class WorkSettingsWindow extends StatefulWidget {
  const WorkSettingsWindow({
    super.key,
    required this.initialInfo,
    required this.projectName,
  });

  final TimesheetInfo initialInfo;

  /// What the forms print for a work with no title — shown faintly in the
  /// empty title, as what the paper will carry.
  final String projectName;

  @override
  State<WorkSettingsWindow> createState() => _WorkSettingsWindowState();
}

class _WorkSettingsWindowState extends State<WorkSettingsWindow> {
  late final TextEditingController _title = TextEditingController(
    text: widget.initialInfo.title,
  );
  late final TextEditingController _episode = TextEditingController(
    text: widget.initialInfo.episode,
  );

  /// One name per colour label, in the order the label popover lists them
  /// ([everyLayerMark] — the one enumeration of the labels).
  ///
  /// ⛔EVERY label gets a row, including 用紙's worker: leaving one out
  /// would be a 「~는 제외한다」 rule nobody asked for.
  late final Map<LayerMark, TextEditingController> _staff = {
    for (final mark in everyLayerMark())
      if (!mark.isNone)
        mark: TextEditingController(
          text: widget.initialInfo.staffNameFor(mark),
        ),
  };

  bool _workOpen = true;
  bool _staffOpen = false;
  final Set<LayerProcess> _foldedProcesses = {};

  @override
  void dispose() {
    _title.dispose();
    _episode.dispose();
    for (final field in _staff.values) {
      field.dispose();
    }
    super.dispose();
  }

  /// 🚨Built on the info it was given, NOT a fresh one: what this window
  /// does not show — the logo, the sheet's options, the envelope's form —
  /// is not its to reset ([[make-the-invariant-unrepresentable]]).
  void _submit() {
    var next = widget.initialInfo.copyWith(
      title: _title.text.trim(),
      episode: _episode.text.trim(),
    );
    for (final MapEntry(key: mark, value: field) in _staff.entries) {
      next = next.withStaffName(mark, field.text.trim());
    }
    Navigator.of(context).pop(next);
  }

  /// The words a folded section shows beside its title: what it holds.
  String _summaryOf(Iterable<String> words) =>
      [for (final word in words) if (word.trim().isNotEmpty) word.trim()]
          .join(' · ');

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return AppWindow(
      windowKey: const ValueKey<String>('work-settings-window'),
      title: strings.workSettingsTitle,
      titleIcon: Icons.theaters_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: 460,
      // ⛔No scroller of its own: `AppWindow` scrolls its body.
      body: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExportAccordion(
              key: const ValueKey<String>('work-settings-work'),
              title: strings.workSettingsTitle,
              summary: _summaryOf([_title.text, _episode.text]),
              expansion: (
                expanded: _workOpen,
                onToggle: () => setState(() => _workOpen = !_workOpen),
              ),
              child: _workFields(strings),
            ),
            const SizedBox(height: 8),
            ExportAccordion(
              key: const ValueKey<String>('work-settings-staff'),
              title: strings.workSettingsStaff,
              summary: _summaryOf([
                for (final field in _staff.values) field.text,
              ]),
              expansion: (
                expanded: _staffOpen,
                onToggle: () => setState(() => _staffOpen = !_staffOpen),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final process in LayerProcess.values)
                    _processFold(process, strings),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        AppWindowAction(
          label: strings.commonCancel,
          actionKey: const ValueKey<String>('work-settings-cancel-button'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppWindowAction(
          label: strings.commonSave,
          actionKey: const ValueKey<String>('work-settings-save-button'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: _submit,
        ),
      ],
    );
  }

  Widget _workFields(AppStrings strings) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppWindowField(
        label: strings.sheetFieldTitle,
        emphasized: true,
        child: TextField(
          key: const ValueKey<String>('work-settings-title-field'),
          controller: _title,
          autofocus: true,
          decoration: InputDecoration(hintText: widget.projectName),
          onSubmitted: (_) => _submit(),
        ),
      ),
      const SizedBox(height: 12),
      AppWindowField(
        label: strings.sheetFieldEpisode,
        child: TextField(
          key: const ValueKey<String>('work-settings-episode-field'),
          controller: _episode,
          onSubmitted: (_) => _submit(),
        ),
      ),
    ],
  );

  /// One process's fold: its worker, then the corrections it references
  /// ([revisesFor], through [everyLayerMark]).
  Widget _processFold(LayerProcess process, AppStrings strings) {
    final marks = [
      for (final mark in _staff.keys)
        if (mark.process == process) mark,
    ];
    final open = !_foldedProcesses.contains(process);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ExportAccordion(
        key: ValueKey<String>('work-settings-process-${process.jsonValue}'),
        title: strings.layerProcessName(process.jsonValue, process.displayName),
        summary: _summaryOf([for (final mark in marks) _staff[mark]!.text]),
        expansion: (
          expanded: open,
          onToggle: () => setState(() {
            if (open) {
              _foldedProcesses.add(process);
            } else {
              _foldedProcesses.remove(process);
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
                  key: ValueKey<String>('work-settings-staff-${mark.keySlug}'),
                  controller: _staff[mark],
                  onSubmitted: (_) => _submit(),
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
