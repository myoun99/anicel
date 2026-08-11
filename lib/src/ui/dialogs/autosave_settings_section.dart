import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../services/persistence/app_documents.dart'
    show appRecordingsDirectory;
import '../../services/persistence/app_save_settings.dart';
import '../editor_session_manager.dart';
import '../text/app_strings.dart';
import 'folder_pick_flow.dart';

/// SAVE-1: the autosave policy section (Preferences ▸ Autosave).
///
/// Autosave writes a recovery SIDECAR only — the project file changes on
/// an explicit save alone. Every knob is user-customizable: on/off, the
/// cadence (default 5 minutes) and where sidecars live (beside the
/// project file, or one folder of the user's choosing — the escape for
/// cloud-synced folders where a big sidecar next to the file would
/// upload on every tick).
class AutosaveSettingsSection extends StatelessWidget {
  const AutosaveSettingsSection({super.key, required this.session});

  final EditorSessionManager session;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppSaveSettings>(
      valueListenable: AppSave.settings,
      builder: (context, settings, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: const ValueKey<String>('settings-autosave-enabled'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Autosave'),
              subtitle: const Text(
                'Snapshots unsaved changes into a recovery sidecar '
                '(.autosave). The project file itself only changes when '
                'you save.',
              ),
              value: settings.autosaveEnabled,
              onChanged: (enabled) => session.setSaveSettings(
                settings.copyWith(autosaveEnabled: enabled),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Interval (minutes)',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: _MinutesField(
                    key: const ValueKey<String>('settings-autosave-interval'),
                    enabled: settings.autosaveEnabled,
                    minutes: settings.autosaveIntervalMinutes,
                    onCommitted: (minutes) => session.setSaveSettings(
                      settings.copyWith(autosaveIntervalMinutes: minutes),
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            SwitchListTile(
              key: const ValueKey<String>('settings-sidecar-custom'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(AppText.strings.autosaveSidecarFolder),
              subtitle: const Text(
                'OFF (default): the sidecar sits beside the project file.\n'
                'ON: every sidecar goes to one folder of your choosing — '
                'for cloud-synced project folders that should not upload '
                'a snapshot every interval.',
              ),
              value: settings.sidecarDirectory != null,
              onChanged: (custom) => session.setSaveSettings(
                settings.copyWith(sidecarDirectory: custom ? '' : null),
              ),
            ),
            if (settings.sidecarDirectory != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      settings.sidecarDirectory!.isEmpty
                          ? 'No folder chosen yet'
                          : settings.sidecarDirectory!,
                      key: const ValueKey<String>('settings-sidecar-directory'),
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    key: const ValueKey<String>('settings-sidecar-browse'),
                    onPressed: () async {
                      // PICK-2: this row is NOT platform-gated (its sibling
                      // below is), so on iPad it was reaching a
                      // `getDirectoryPath` that iOS never implemented — a
                      // thrown UnimplementedError on every tap.
                      final directory = await pickFolderForUser(context);
                      if (directory != null) {
                        session.setSaveSettings(
                          AppSave.settings.value.copyWith(
                            sidecarDirectory: directory,
                          ),
                        );
                      }
                    },
                    child: Text(AppText.strings.autosaveChoose),
                  ),
                ],
              ),
            const Divider(height: 16),
            // REC1-B2: the take shelf. Mobile shows where takes land but
            // cannot move it (the app documents home is the only sane
            // place there); desktop may point it anywhere.
            const Text(
              'Recordings folder',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'Where voice takes land while a project has never been '
              'saved. The first save moves the project\'s takes into its '
              'Media folder; unused takes stay here.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    appRecordingsDirectory(),
                    key: const ValueKey<String>(
                      'settings-recordings-directory',
                    ),
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!Platform.isAndroid && !Platform.isIOS) ...[
                  if (settings.recordingsDirectory != null)
                    TextButton(
                      key: const ValueKey<String>('settings-recordings-reset'),
                      onPressed: () => session.setSaveSettings(
                        settings.copyWith(recordingsDirectory: null),
                      ),
                      child: const Text('Default'),
                    ),
                  TextButton(
                    key: const ValueKey<String>('settings-recordings-browse'),
                    onPressed: () async {
                      final directory = await pickFolderForUser(context);
                      if (directory != null) {
                        session.setSaveSettings(
                          AppSave.settings.value.copyWith(
                            recordingsDirectory: directory,
                          ),
                        );
                      }
                    },
                    child: Text(AppText.strings.autosaveChoose),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }
}

/// A compact integer-minutes field that commits on submit/focus loss and
/// snaps back to the live value on bad input (1–1440 accepted).
class _MinutesField extends StatefulWidget {
  const _MinutesField({
    super.key,
    required this.minutes,
    required this.enabled,
    required this.onCommitted,
  });

  final int minutes;
  final bool enabled;
  final ValueChanged<int> onCommitted;

  @override
  State<_MinutesField> createState() => _MinutesFieldState();
}

class _MinutesFieldState extends State<_MinutesField> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.minutes}',
  );
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        _commit();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _MinutesField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.minutes != oldWidget.minutes && !_focus.hasFocus) {
      _controller.text = '${widget.minutes}';
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null || parsed < 1 || parsed > 1440) {
      _controller.text = '${widget.minutes}';
      return;
    }
    if (parsed != widget.minutes) {
      widget.onCommitted(parsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      enabled: widget.enabled,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.end,
      style: const TextStyle(fontSize: 12),
      decoration: const InputDecoration(isDense: true),
      onSubmitted: (_) => _commit(),
    );
  }
}
