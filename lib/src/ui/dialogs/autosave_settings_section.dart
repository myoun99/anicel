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
import '../widgets/field_slider.dart';
import '../widgets/settings_rows.dart';
import 'folder_pick_flow.dart';

/// SAVE-1: the autosave policy section (Preferences ▸ Autosave).
///
/// Autosave writes a recovery snapshot only — the project file changes on
/// an explicit save alone. 🚨F-1 (2026-08-26) cut the policy down to what
/// the user asked for: **a switch and a number of minutes**. The location
/// is the app's own folder rather than somewhere the user has to keep out
/// of a sync client's way, so there is nothing else to set.
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
            const SettingsSectionHeading(
              label: 'Autosave',
              help:
                  'Writes a recovery snapshot every so often, so a crash or '
                  'a flat battery costs at most that much work. The project '
                  'file itself only changes when you save.',
            ),
            const SizedBox(height: 4),
            // 🚨F-1 (유저 2026-08-26): 「**자동저장 on off만 남기고** … 심플
            // 하게 명시적저장 / n분주기 자동저장만 남김」. Three switches
            // stood here — leaving the app, pausing, and the clock — and
            // two of them named triggers that no longer exist.
            SettingsSwitchRow(
              tileKey: const ValueKey<String>('settings-autosave-enabled'),
              label: 'Autosave',
              help:
                  'Off means the project only changes when you save it, and '
                  'a crash costs everything since.',
              value: settings.periodicSnapshotMinutes != null,
              onChanged: (enabled) => session.setSaveSettings(
                settings.copyWith(
                  periodicSnapshotMinutes: enabled
                      ? AppSaveSettings.defaultPeriodicSnapshotMinutes
                      : null,
                ),
              ),
            ),
            // ⛔The row is always here, switched on or off — 없다가 생기는
            // UI 금지. It goes INERT rather than absent: a FieldSlider with
            // a null `onChanged` dims itself and stops taking input.
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 8, bottom: 4),
              child: Row(
                children: [
                  const Text('Every', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FieldSlider(
                      key: const ValueKey<String>('settings-autosave-minutes'),
                      min: AppSaveSettings.minPeriodicSnapshotMinutes
                          .toDouble(),
                      max: AppSaveSettings.maxPeriodicSnapshotMinutes
                          .toDouble(),
                      // Whole minutes: the range is 3..60, so the track has
                      // one stop per minute and the number under the thumb
                      // is the number the clock uses.
                      divisions:
                          AppSaveSettings.maxPeriodicSnapshotMinutes -
                          AppSaveSettings.minPeriodicSnapshotMinutes,
                      value:
                          (settings.periodicSnapshotMinutes ??
                                  AppSaveSettings
                                      .defaultPeriodicSnapshotMinutes)
                              .toDouble(),
                      valueText: sliderValueText(
                        settings.periodicSnapshotMinutes ??
                            AppSaveSettings.defaultPeriodicSnapshotMinutes,
                        unit: ' min',
                      ),
                      // ⛔No rounding here: the track has one stop per
                      // minute, so `next` IS whole, and `sliderValueText`
                      // renders a whole number whole. (`onChanged` below
                      // still rounds — that is the MODEL's int, not the
                      // label's text.)
                      valueTextBuilder: (next) =>
                          sliderValueText(next, unit: ' min'),
                      onChanged: settings.periodicSnapshotMinutes == null
                          ? null
                          : (next) => session.setSaveSettings(
                              settings.copyWith(
                                periodicSnapshotMinutes: next.round(),
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
            const SettingsSectionHeading(
              label: 'Recordings folder',
              help:
                  'Where voice takes land. Saving copies the ones a '
                  'project uses into the project file; every take stays '
                  'here either way, so a recording is never in one place '
                  'only.',
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
            const SettingsSectionHeading(
              label: 'Conform cache',
              help:
                  'Decoded audio, kept so a waveform and playback do not '
                  'decode the same file twice. A conform is around twelve '
                  'times the size of its source, so point this at a drive '
                  'with room — and out of a cloud-synced folder. Deleting '
                  'it costs time, never content.',
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
