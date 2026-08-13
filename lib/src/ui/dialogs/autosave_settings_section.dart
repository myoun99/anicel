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
/// an explicit save alone. Its own knobs came down to on/off: the cadence
/// went with the timer, and the snapshot's location is the app's own folder
/// now rather than a place the user has to keep out of a sync client's way.
///
/// The two folders below are here because they are the caches and shelves
/// that used to sit beside the project and no longer do — the section is
/// "what the app writes on its own, and where".
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
            const Divider(height: 16),
            // The conform cache. Movable for the same reason the recordings
            // folder is, and desktop-only for the same reason too: on
            // mobile the app container is the one place writable without
            // asking an OS, and a cache in a scoped folder would need a
            // grant held for a session that writes to it unannounced.
            const Text(
              'Conform cache',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'Decoded audio, kept so a waveform and playback do not decode '
              'the same file twice. A conform is around twelve times the '
              'size of its source, so point this at a drive with room — and '
              'out of a cloud-synced folder. Deleting it costs time, never '
              'content.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppSave.conformRootDirectory,
                    key: const ValueKey<String>('settings-conform-directory'),
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!Platform.isAndroid && !Platform.isIOS) ...[
                  if (settings.conformDirectory != null)
                    TextButton(
                      key: const ValueKey<String>('settings-conform-reset'),
                      onPressed: () => session.setSaveSettings(
                        settings.copyWith(conformDirectory: null),
                      ),
                      child: const Text('Default'),
                    ),
                  TextButton(
                    key: const ValueKey<String>('settings-conform-browse'),
                    onPressed: () async {
                      final directory = await pickFolderForUser(context);
                      if (directory != null) {
                        session.setSaveSettings(
                          AppSave.settings.value.copyWith(
                            conformDirectory: directory,
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
