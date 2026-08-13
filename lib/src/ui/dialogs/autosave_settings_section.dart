import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../services/persistence/app_documents.dart'
    show appRecordingsDirectory;
import '../../services/audio/conform_cache_maintenance.dart'
    show clearConformCache, conformCacheBytes;
import '../../services/persistence/app_save_settings.dart';
import '../editor_session_manager.dart';
import '../text/app_strings.dart';
import '../text/byte_size_label.dart';
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
            const Text(
              'Crash recovery',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Text(
              'Snapshots unsaved changes so a crash or a flat battery does '
              'not cost them. The project file itself only changes when you '
              'save; a snapshot is discarded the moment the work stops '
              'being unsaved.',
              style: TextStyle(fontSize: 12),
            ),
            SwitchListTile(
              key: const ValueKey<String>('settings-autosave-enabled'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('When leaving the app'),
              subtitle: const Text(
                'Closing the project, switching away, or the system putting '
                'the app to sleep. Costs nothing — nobody is drawing — and '
                'on a phone or tablet it is the only warning the system '
                'gives before it stops the app.',
              ),
              value: settings.lifecycleSnapshotEnabled,
              onChanged: (enabled) => session.setSaveSettings(
                settings.copyWith(lifecycleSnapshotEnabled: enabled),
              ),
            ),
            SwitchListTile(
              key: const ValueKey<String>('settings-autosave-pause'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('When you pause'),
              subtitle: const Text(
                'A few seconds without touching anything is enough. Once per '
                'pause, not on a repeat — sitting idle does not keep '
                'rewriting the same file.',
              ),
              value: settings.pauseSnapshotEnabled,
              onChanged: (enabled) => session.setSaveSettings(
                settings.copyWith(pauseSnapshotEnabled: enabled),
              ),
            ),
            SwitchListTile(
              key: const ValueKey<String>('settings-autosave-periodic'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('While you keep working'),
              subtitle: Text(
                settings.periodicSnapshotMinutes == null
                    // The reason to want it: a long focused stretch never
                    // pauses, so a pause-only guard covers nothing during
                    // exactly the hours that hold the most work.
                    ? 'Off. Pauses alone cover a session that has them — a '
                          'long stretch without one goes unprotected.'
                    : 'At most ${settings.periodicSnapshotMinutes} minutes '
                          'of work is ever unprotected. Any snapshot resets '
                          'the count, so this only fires when nothing else '
                          'did.',
              ),
              value: settings.periodicSnapshotMinutes != null,
              onChanged: (enabled) => session.setSaveSettings(
                settings.copyWith(
                  periodicSnapshotMinutes: enabled
                      ? AppSaveSettings.defaultPeriodicSnapshotMinutes
                      : null,
                ),
              ),
            ),
            if (settings.periodicSnapshotMinutes != null)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Row(
                  children: [
                    const Text('Minutes', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 8),
                    for (final minutes in const <int>[5, 10, 20, 30])
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: ChoiceChip(
                          key: ValueKey<String>('settings-autosave-$minutes'),
                          label: Text('$minutes'),
                          selected: settings.periodicSnapshotMinutes == minutes,
                          onSelected: (_) => session.setSaveSettings(
                            settings.copyWith(
                              periodicSnapshotMinutes: minutes,
                            ),
                          ),
                        ),
                      ),
                  ],
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
              'Where voice takes land. Saving copies the ones a project '
              'uses into the project file; every take stays here either '
              'way, so a recording is never in one place only.',
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
            _ConformCacheSizeRow(
              directory: AppSave.conformRootDirectory,
              releaseDiskBackedConforms:
                  session.audioConformStore.releaseDiskBacked,
            ),
          ],
        );
      },
    );
  }
}

/// What the conform cache is holding, and the one button that empties it.
///
/// Its own widget because it holds a MEASUREMENT: a directory scan has no
/// business in a build that reruns on every settings change, and after
/// emptying, the number has to come back changed.
///
/// It exists at all because of the iPad. On a desktop the folder is a
/// place someone can open and delete; inside an app container it is
/// neither visible nor reachable, so without this the only honest thing
/// to say about the cache would be "it is somewhere, and it is some size".
class _ConformCacheSizeRow extends StatefulWidget {
  const _ConformCacheSizeRow({
    required this.directory,
    required this.releaseDiskBackedConforms,
  });

  /// Read only to NOTICE it changed — the measurement follows the root.
  final String directory;

  /// Makes the session let go of the conforms whose PCM lives only on
  /// disk, so that emptying the cache means what it says.
  final VoidCallback releaseDiskBackedConforms;

  @override
  State<_ConformCacheSizeRow> createState() => _ConformCacheSizeRowState();
}

class _ConformCacheSizeRowState extends State<_ConformCacheSizeRow> {
  late int _bytes = conformCacheBytes();

  @override
  void didUpdateWidget(covariant _ConformCacheSizeRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.directory != widget.directory) {
      setState(() => _bytes = conformCacheBytes());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            _bytes == 0 ? 'Empty' : 'Holding ${byteSizeLabel(_bytes)}',
            key: const ValueKey<String>('settings-conform-size'),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        if (_bytes > 0)
          TextButton(
            key: const ValueKey<String>('settings-conform-clear'),
            // No confirmation on purpose: a conform is derived data, so
            // the worst this can cost is a re-decode. Asking "are you
            // sure" about something that cannot lose anything teaches
            // people to click through the dialogs that can.
            //
            // 🚨 That is only true once the SESSION has let go. A conform
            // past the streaming threshold is held with no resident PCM
            // and the file as the copy of record — delete it underneath
            // and the clip is silent for the rest of the session and in
            // the export, and on Windows the open reader blocks the
            // delete so the biggest entries survive the emptying.
            onPressed: () {
              widget.releaseDiskBackedConforms();
              clearConformCache();
              setState(() => _bytes = conformCacheBytes());
            },
            child: const Text('Empty now'),
          ),
      ],
    );
  }
}
