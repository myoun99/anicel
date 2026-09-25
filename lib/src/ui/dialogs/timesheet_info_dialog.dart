import '../widgets/app_tooltip.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/layer_process.dart';
import '../../models/timesheet_info.dart';
import '../widgets/app_window.dart';
import '../text/app_strings.dart';
import '../widgets/settings_rows.dart';
import '../widgets/panel_flyout.dart';
import '../theme/app_theme.dart';
import '../../services/persistence/file_type_groups.dart';
import 'folder_pick_flow.dart';
import '../input/control_press_claim.dart';

/// Edits the sheet-header text (title/episode/scene/artist) the paper
/// timesheet reads, and which header boxes the form prints. Pops the
/// edited [TimesheetInfo], or null when cancelled.
class TimesheetInfoDialog extends StatefulWidget {
  const TimesheetInfoDialog({super.key, required this.initialInfo});

  final TimesheetInfo initialInfo;

  @override
  State<TimesheetInfoDialog> createState() => _TimesheetInfoDialogState();
}

class _TimesheetInfoDialogState extends State<TimesheetInfoDialog> {
  late final TextEditingController _titleController = TextEditingController(
    text: widget.initialInfo.title,
  );
  late final TextEditingController _episodeController = TextEditingController(
    text: widget.initialInfo.episode,
  );
  late final TextEditingController _sceneController = TextEditingController(
    text: widget.initialInfo.scene,
  );
  late final TextEditingController _artistController = TextEditingController(
    text: widget.initialInfo.artist,
  );
  late final Set<TimesheetHeaderField> _hiddenFields = {
    ...widget.initialInfo.hiddenFields,
  };
  late bool _exposureBarEnabled =
      widget.initialInfo.exposureBarThreshold != null;
  late final TextEditingController
  _exposureBarThresholdController = TextEditingController(
    text:
        '${widget.initialInfo.exposureBarThreshold ?? TimesheetInfo.defaultExposureBarThreshold}',
  );
  late bool _seEmptyFill = widget.initialInfo.seEmptyFill;

  /// One name field per 공정 — the list the user designed (I-4), which
  /// `LayerProcess` already is and the cut envelope already binds by
  /// (`{staff.<role>.name}`).
  ///
  /// ⛔EVERY process gets a row, including 用紙. Leaving one out would be a
  /// 「~는 제외한다」 rule nobody asked for, and an empty row costs a line
  /// while a missing one costs a question — the same reason a rail row
  /// reserves every slot.
  /// The stamp each role is carrying, edited live and written on submit —
  /// the names go through controllers, and this is their other half.
  late final Map<String, String?> _stamps = {
    for (final process in LayerProcess.values)
      process.jsonValue: widget.initialInfo
          .staffFor(process.jsonValue)
          .stampAssetPath,
  };

  late final Map<String, TextEditingController> _staffControllers = {
    for (final process in LayerProcess.values)
      process.jsonValue: TextEditingController(
        text: widget.initialInfo.staffFor(process.jsonValue).name,
      ),
  };

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
    _titleController.dispose();
    _episodeController.dispose();
    _sceneController.dispose();
    _artistController.dispose();
    _exposureBarThresholdController.dispose();
    for (final controller in _staffControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final threshold = int.tryParse(_exposureBarThresholdController.text.trim());
    // 🚨★★★copyWith, NOT a fresh TimesheetInfo. Building one from scratch
    // listed the fields this dialog edits and silently dropped every field
    // it does not — `staff` and `logoAssetPath` both default to empty, so
    // opening this window and pressing save WIPED the production staff and
    // the logo. Nothing said so; they simply were not there afterwards.
    //
    // ⛔A re-construction cannot be made safe by remembering to add the
    // next field: remembering is the part that failed. `copyWith` carries
    // what it was not asked about ([[make-the-invariant-unrepresentable]]).
    Navigator.of(context).pop(
      widget.initialInfo.copyWith(
        title: _titleController.text.trim(),
        episode: _episodeController.text.trim(),
        scene: _sceneController.text.trim(),
        artist: _artistController.text.trim(),
        hiddenFields: {..._hiddenFields},
        exposureBarThreshold: () => _exposureBarEnabled && threshold != null
            ? threshold.clamp(1, 999)
            : _exposureBarEnabled
            ? TimesheetInfo.defaultExposureBarThreshold
            : null,
        seEmptyFill: _seEmptyFill,
        // A role survives if it has EITHER half — a stamp with no name is a
        // real answer, and so is a name with no stamp.
        staff: {
          for (final entry in _staffControllers.entries)
            if (entry.value.text.trim().isNotEmpty ||
                _stamps[entry.key] != null)
              entry.key: widget.initialInfo
                  .staffFor(entry.key)
                  .copyWith(
                    name: entry.value.text.trim(),
                    stampAssetPath: () => _stamps[entry.key],
                  ),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    return AppWindow(
      windowKey: const ValueKey<String>('timesheet-info-dialog'),
      title: strings.sheetInfoTitle,
      titleIcon: Icons.description_outlined,
      onClose: () => Navigator.of(context).pop(),
      width: 420,
      // ⛔The body does NOT bring its own scroller. `AppWindow` already
      // scrolls it, and it applies the body padding OUTSIDE that scroller —
      // so the window's bar lands on 12px of dead padding, while a bar
      // belonging to a scroller in HERE would lie across the right edge of
      // every field and swallow the taps that focus them.
      body: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppWindowField(
              label: strings.sheetFieldTitle,
              emphasized: true,
              child: TextField(
                key: const ValueKey<String>('timesheet-info-title-field'),
                controller: _titleController,
                autofocus: true,
                decoration: InputDecoration(hintText: strings.sheetTitleHint),
              ),
            ),
            const SizedBox(height: 12),
            AppWindowField(
              label: strings.sheetFieldEpisode,
              child: TextField(
                key: const ValueKey<String>('timesheet-info-episode-field'),
                controller: _episodeController,
              ),
            ),
            const SizedBox(height: 12),
            AppWindowField(
              label: strings.sheetFieldScene,
              child: TextField(
                key: const ValueKey<String>('timesheet-info-scene-field'),
                controller: _sceneController,
              ),
            ),
            const SizedBox(height: 12),
            AppWindowField(
              label: strings.sheetArtist,
              child: TextField(
                key: const ValueKey<String>('timesheet-info-artist-field'),
                controller: _artistController,
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              strings.sheetStaffByProcess,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            // 🚨One row per 공정, always all of them — the cut envelope binds
            // `{staff.<role>.name}` by this same key, so what the form can
            // fill and what a form can print are one list.
            for (final process in LayerProcess.values) ...[
              AppWindowField(
                label: process.displayName,
                // 「담당자 = 이름 + 도장 이미지 한 세트」 — one row, both
                // halves, so the field never has to be read as the whole
                // answer.
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: ValueKey<String>(
                          'timesheet-info-staff-${process.jsonValue}',
                        ),
                        controller: _staffControllers[process.jsonValue],
                        onSubmitted: (_) => _submit(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StaffStampCell(
                      process: process,
                      assetPath: _stamps[process.jsonValue],
                      onPicked: (path) =>
                          setState(() => _stamps[process.jsonValue] = path),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 16),
            Text(
              strings.sheetVisibleBoxes,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            // The app's one boolean (guide-sym ⑥⑧: 「진짜 불리언값 모든곳에
            // 적용」). These were FilterChips, which mark ON with a check — the
            // mark 「선택 표시는 색상만」 names — and did not claim their press
            // in a window that scrolls.
            for (final field in TimesheetHeaderField.values)
              SettingsSwitchRow(
                tileKey: ValueKey<String>(
                  'timesheet-info-visible-${field.name}',
                ),
                label: _fieldLabel(field),
                value: !_hiddenFields.contains(field),
                onChanged: (visible) => setState(() {
                  if (visible) {
                    _hiddenFields.remove(field);
                  } else {
                    _hiddenFields.add(field);
                  }
                }),
              ),
            const SizedBox(height: 16),
            Text(
              strings.sheetNotation,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            SettingsSwitchRow(
              tileKey: const ValueKey<String>('timesheet-info-exposure-bar'),
              label: strings.sheetExposureBar,
              help: strings.sheetExposureBarHelp,
              value: _exposureBarEnabled,
              onChanged: (value) => setState(() => _exposureBarEnabled = value),
            ),
            if (_exposureBarEnabled)
              AppWindowField(
                label: strings.sheetExposureBarN,
                child: TextField(
                  key: const ValueKey<String>(
                    'timesheet-info-exposure-bar-threshold',
                  ),
                  controller: _exposureBarThresholdController,
                  keyboardType: TextInputType.number,
                ),
              ),
            SettingsSwitchRow(
              tileKey: const ValueKey<String>('timesheet-info-se-empty-fill'),
              label: strings.sheetSeEmptyFill,
              value: _seEmptyFill,
              onChanged: (value) => setState(() => _seEmptyFill = value),
            ),
          ],
        ),
      ),
      actions: [
        AppWindowAction(
          label: strings.commonCancel,
          actionKey: const ValueKey<String>('timesheet-info-cancel-button'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppWindowAction(
          label: strings.commonSave,
          actionKey: const ValueKey<String>('timesheet-info-save-button'),
          emphasis: AppWindowActionEmphasis.primary,
          onPressed: _submit,
        ),
      ],
    );
  }
}

/// The stamp beside a staff name — 「담당자 = 이름 + 도장 이미지 한 세트」
/// (cut-envelope 정본 §7). The envelope already binds `{staff.<role>.stamp}`
/// and the model already holds [ProductionStaff.stampAssetPath]; what was
/// missing was any way in the app to CHOOSE one.
///
/// 🚨THE SLOT IS ALWAYS HERE. An empty stamp draws its outline, not nothing:
/// a cell that appeared only once a file was chosen would be UI popping into
/// existence, and the row would jump the first time anyone used it.
///
/// ⚠️Aspect ratio is PRESERVED (`BoxFit.contain`) — 정본: 「늘어난 도장은
/// 도장이 아니다」.
class _StaffStampCell extends StatelessWidget {
  const _StaffStampCell({
    required this.process,
    required this.assetPath,
    required this.onPicked,
  });

  final LayerProcess process;
  final String? assetPath;
  final ValueChanged<String?> onPicked;

  static const double _size = AppShapes.controlLarge;

  Future<void> _pick(BuildContext context) async {
    final grants = await pickFileGrantsForUser(
      context,
      supportedExtensions: imageFileExtensions,
    );
    if (grants.isEmpty) {
      // A cancelled picker changes nothing — it does not clear what was
      // already chosen. That is what the menu's Remove is for.
      return;
    }
    onPicked(grants.first.path);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // A control's corner is a fraction of its own size — never a circular
    // radius, which the shapes ratchet is there to keep out.
    final shape = AppShapes.control(
      _size,
      side: BorderSide(color: colors.outlineVariant),
    );
    final strings = AppText.strings;
    final path = assetPath;
    return AppTooltip(
      message: strings.sheetStampPick,
      child: ControlPressClaim(
        onPressed: () => showPanelFlyout(
          context,
          entries: [
            PanelFlyoutItem(
              keyValue: 'timesheet-stamp-pick-${process.jsonValue}',
              label: strings.sheetStampPick,
              icon: Icons.image_outlined,
              onSelected: () => unawaited(_pick(context)),
            ),
            // ⛔BOTH entries, always, even with no stamp set: a menu that
            // grows a row the moment a file lands is the same popping this
            // widget's own slot exists to avoid. Clearing an empty stamp is
            // a no-op, which is a fine thing for a menu row to be.
            PanelFlyoutItem(
              keyValue: 'timesheet-stamp-clear-${process.jsonValue}',
              label: strings.sheetStampClear,
              icon: Icons.backspace_outlined,
              onSelected: () => onPicked(null),
            ),
          ],
        ),
        child: InkWell(
          key: ValueKey<String>('timesheet-stamp-${process.jsonValue}'),
          customBorder: shape,
          onTap: silentPress(
            () => showPanelFlyout(
              context,
              entries: [
                PanelFlyoutItem(
                  keyValue: 'timesheet-stamp-pick-${process.jsonValue}',
                  label: strings.sheetStampPick,
                  icon: Icons.image_outlined,
                  onSelected: () => unawaited(_pick(context)),
                ),
                // ⛔BOTH entries, always, even with no stamp set: a menu that
                // grows a row the moment a file lands is the same popping this
                // widget's own slot exists to avoid. Clearing an empty stamp is
                // a no-op, which is a fine thing for a menu row to be.
                PanelFlyoutItem(
                  keyValue: 'timesheet-stamp-clear-${process.jsonValue}',
                  label: strings.sheetStampClear,
                  icon: Icons.backspace_outlined,
                  onSelected: () => onPicked(null),
                ),
              ],
            ),
          ),
          child: Container(
            width: _size,
            height: _size,
            decoration: ShapeDecoration(shape: shape),
            padding: const EdgeInsets.all(3),
            child: path == null
                ? null
                : Image.file(File(path), fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
