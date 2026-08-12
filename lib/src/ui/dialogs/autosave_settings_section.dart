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
/// Autosave writes a recovery snapshot only — the project file changes on
/// an explicit save alone. One knob left, on/off, because the other two
/// stopped naming anything: the cadence went with the timer, and the
/// location is the app's own folder now rather than a place the user has
/// to keep out of a sync client's way.
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
                'Snapshots unsaved changes for crash recovery whenever you '
                'leave the app. The project file itself only changes when '
                'you save.',
              ),
              value: settings.autosaveEnabled,
              onChanged: (enabled) => session.setSaveSettings(
                settings.copyWith(autosaveEnabled: enabled),
              ),
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
