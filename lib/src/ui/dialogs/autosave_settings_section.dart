import 'dart:io' show File, Platform;

import 'package:flutter/material.dart';

import '../../services/persistence/app_documents.dart'
    show appRecordingsDirectory;
import '../../services/audio/conform_cache_maintenance.dart'
    show clearConformCache, conformCacheBytes;
import '../../services/persistence/app_save_settings.dart';
import '../../services/persistence/project_autosave_service.dart';
import '../../services/persistence/recent_projects.dart' show AppRecent;
import '../editor_session_manager.dart';
import '../text/app_strings.dart';
import '../text/byte_size_label.dart';
import '../theme/app_theme.dart' show AppShapes;
import '../widgets/app_window.dart';
import '../widgets/field_slider.dart';
import '../widgets/settings_rows.dart';
import 'app_confirm_dialog.dart';
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
                  Text(
                    AppText.strings.autosaveEvery,
                    style: const TextStyle(fontSize: 12),
                  ),
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
                        unit: AppText.strings.commonMinutesShort,
                      ),
                      // ⛔No rounding here: the track has one stop per
                      // minute, so `next` IS whole, and `sliderValueText`
                      // renders a whole number whole. (`onChanged` below
                      // still rounds — that is the MODEL's int, not the
                      // label's text.)
                      valueTextBuilder: (next) => sliderValueText(
                        next,
                        unit: AppText.strings.commonMinutesShort,
                      ),
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
            // Q-recovery-gc (유저 08-26): the snapshots made visible —
            // 「위치나 수정날짜같은거 다 있고 거기서 여러개 선택해서
            // 삭제가능하게」. The 30-day sweep handles the abandoned ones
            // on its own; this is the by-hand door for everything else.
            const SettingsSectionHeading(
              label: 'Recovery snapshots',
              help:
                  'Unsaved work autosave has written, one per project. '
                  'Saving a project retires its snapshot; one untouched '
                  'for 30 days is cleaned up on launch.',
            ),
            const SizedBox(height: 4),
            const _RecoverySnapshotsBlock(),
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
                      child: Text(AppText.strings.autosaveDefault),
                    ),
                  TextButton(
                    key: const ValueKey<String>('settings-recordings-browse'),
                    onPressed: () async {
                      // The GRANT flavour: this path is read again at the
                      // NEXT launch, and on macOS a stored path without
                      // its token is refused there — the setting stayed
                      // on screen while every write quietly failed
                      // (Q-scoped-folder-settings, 유저 「알아서 맡김」).
                      final grant = await pickFolderGrantForUser(context);
                      final path = grant?.path;
                      if (path != null) {
                        session.setSaveSettings(
                          AppSave.settings.value.copyWith(
                            recordingsDirectory: GrantedDirectory(
                              path: path,
                              bookmark: grant!.bookmark,
                            ),
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
                      child: Text(AppText.strings.autosaveDefault),
                    ),
                  TextButton(
                    key: const ValueKey<String>('settings-conform-browse'),
                    onPressed: () async {
                      // The GRANT flavour, same reason as the recordings
                      // folder above.
                      final grant = await pickFolderGrantForUser(context);
                      final path = grant?.path;
                      if (path != null) {
                        session.setSaveSettings(
                          AppSave.settings.value.copyWith(
                            conformDirectory: GrantedDirectory(
                              path: path,
                              bookmark: grant!.bookmark,
                            ),
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

/// The recovery snapshots on disk: name/location, modified date and size
/// per row, multi-select, one Delete.
///
/// A stateful MEASUREMENT like the conform row below — a directory scan
/// has no business rerunning on every settings rebuild. Unlike that row's
/// cache, a snapshot can be the ONLY copy of unsaved crash work, so this
/// delete confirms first.
class _RecoverySnapshotsBlock extends StatefulWidget {
  const _RecoverySnapshotsBlock();

  @override
  State<_RecoverySnapshotsBlock> createState() =>
      _RecoverySnapshotsBlockState();
}

class _RecoverySnapshotsBlockState extends State<_RecoverySnapshotsBlock> {
  late List<RecoverySnapshotInfo> _rows = _load();
  final Set<String> _selected = <String>{};
  final ScrollController _scroll = ScrollController();

  static List<RecoverySnapshotInfo> _load() =>
      ProjectAutosaveService.listRecoverySnapshots(
        knownProjectPaths: [
          for (final entry in AppRecent.projects.value.entries) entry.path,
        ],
      );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  static String _dateLabel(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}';
  }

  Future<void> _confirmDelete() async {
    final strings = AppText.strings;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AppConfirmDialog(
        windowKey: const ValueKey<String>('recovery-delete-dialog'),
        title: strings.recoveryDeleteTitle,
        titleIcon: Icons.delete_outline,
        message: strings.recoveryDeleteMessageTemplate.replaceAll(
          '{n}',
          '${_selected.length}',
        ),
        actions: [
          AppWindowAction(
            label: strings.commonCancel,
            actionKey: const ValueKey<String>('recovery-delete-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          AppWindowAction(
            label: strings.commonDelete,
            actionKey: const ValueKey<String>('recovery-delete-confirm'),
            emphasis: AppWindowActionEmphasis.danger,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) {
      return;
    }
    for (final path in _selected) {
      try {
        File(path).deleteSync();
      } on Object {
        // Locked by a sync client: the row comes back on the reload below
        // and says so more honestly than a crash would.
      }
    }
    setState(() {
      _selected.clear();
      _rows = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    var total = 0;
    for (final row in _rows) {
      total += row.bytes;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _rows.isEmpty
                    ? 'Empty'
                    : '${_rows.length} · ${byteSizeLabel(total)}',
                key: const ValueKey<String>('settings-recovery-size'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
            TextButton(
              key: const ValueKey<String>('settings-recovery-delete'),
              onPressed: _selected.isEmpty ? null : _confirmDelete,
              child: Text(AppText.strings.commonDelete),
            ),
          ],
        ),
        // ⛔The well is always here, empty or not — 없다가 생기는 UI 금지.
        Container(
          height: 120,
          clipBehavior: Clip.antiAlias,
          decoration: ShapeDecoration(
            shape: AppShapes.container(
              AppShapes.wellRadius,
              side: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          child: Scrollbar(
            controller: _scroll,
            child: ListView.builder(
              controller: _scroll,
              itemCount: _rows.length,
              itemExtent: 24,
              itemBuilder: (context, index) {
                final row = _rows[index];
                final selected = _selected.contains(row.path);
                return InkWell(
                  key: ValueKey<String>('settings-recovery-row-${row.path}'),
                  onTap: () => setState(() {
                    if (!_selected.add(row.path)) {
                      _selected.remove(row.path);
                    }
                  }),
                  child: Container(
                    // Selection is COLOR only (법): no mark, no reflow.
                    color: selected
                        ? colorScheme.primary.withValues(alpha: 0.16)
                        : null,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            row.projectPath ?? row.projectName,
                            style: TextStyle(
                              fontSize: 12,
                              color: selected ? colorScheme.primary : null,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _dateLabel(row.modified),
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          byteSizeLabel(row.bytes),
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
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
            child: Text(AppText.strings.autosaveEmptyNow),
          ),
      ],
    );
  }
}
