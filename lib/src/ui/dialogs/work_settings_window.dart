import 'package:flutter/material.dart';

import '../../models/layer_mark.dart';
import '../../models/media_asset.dart';
import '../../models/timesheet_info.dart';
import '../export/export_settings_modules.dart' show ExportAccordion;
import '../text/app_strings.dart';
import '../widgets/app_window.dart';
import '../widgets/panel_flyout.dart';
import 'staff_process_folds.dart';

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
/// a fold per process, its worker and the corrections it references
/// ([StaffProcessFolds] — a cut's settings show the same).
class WorkSettingsWindow extends StatefulWidget {
  const WorkSettingsWindow({
    super.key,
    required this.initialInfo,
    required this.projectName,
    this.pictures = const [],
  });

  final TimesheetInfo initialInfo;

  /// The media pool's images — what the work's pictures are picked from
  /// (답 logo-home 「작품 설정 한 곳」: 「미디어 풀 그림을 한 번 고르면」).
  final List<MediaAsset> pictures;

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

  /// One name per colour label ([staffFieldsOf]).
  late final Map<LayerMark, TextEditingController> _staff = staffFieldsOf(
    widget.initialInfo.staffNameFor,
  );

  /// Each picture of the work, as picked so far.
  late final Map<WorkPicture, String?> _pictures = {
    for (final picture in WorkPicture.values)
      picture: picture.pathIn(widget.initialInfo),
  };

  bool _workOpen = true;
  bool _staffOpen = false;

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
  /// does not show — the sheet's options, the envelope's form — is not its
  /// to reset ([[make-the-invariant-unrepresentable]]).
  void _submit() {
    var next = widget.initialInfo.copyWith(
      title: _title.text.trim(),
      episode: _episode.text.trim(),
    );
    for (final MapEntry(key: picture, value: path) in _pictures.entries) {
      next = picture.withPath(next, path);
    }
    for (final MapEntry(key: mark, value: field) in _staff.entries) {
      next = next.withStaffName(mark, field.text.trim());
    }
    Navigator.of(context).pop(next);
  }

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
              summary: foldSummary([_title.text, _episode.text]),
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
              summary: foldSummary([
                for (final field in _staff.values) field.text,
              ]),
              expansion: (
                expanded: _staffOpen,
                onToggle: () => setState(() => _staffOpen = !_staffOpen),
              ),
              child: StaffProcessFolds(
                fields: _staff,
                keyPrefix: 'work-settings',
                onSubmitted: _submit,
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
      for (final picture in WorkPicture.values) ...[
        const SizedBox(height: 12),
        _pictureField(picture, strings),
      ],
    ],
  );

  /// A picture of the work: none, or one of the pool's images — named as
  /// the pool names it.
  Widget _pictureField(WorkPicture picture, AppStrings strings) {
    final path = _pictures[picture];
    String labelOf(String? value) => value == null
        ? strings.commonNone
        : mediaAssetNameFor(
            widget.pictures.where((asset) => asset.path == value).firstOrNull,
            value,
          );
    return AppWindowField(
      label: strings.workPictureName(picture),
      child: PanelFlyoutButton(
        key: ValueKey<String>('work-settings-picture-${picture.name}'),
        label: labelOf(path),
        expand: true,
        entriesBuilder: () =>
            <String?>[
              null,
              for (final asset in widget.pictures) asset.path,
            ].asFlyoutValueChoices(
              current: path,
              keyOf: (value) =>
                  'work-settings-picture-${picture.name}-${value ?? 'none'}',
              labelOf: labelOf,
              onPicked: (value) => setState(() => _pictures[picture] = value),
            ),
      ),
    );
  }
}
