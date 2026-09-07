import 'dart:io' show Directory, File, Platform;

import 'package:flutter/material.dart';

import '../../services/persistence/app_save_settings.dart';
import '../../services/persistence/app_support_path.dart';
import '../../services/persistence/session_scratch.dart';
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
import '../input/control_press_claim.dart';

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
            SettingsSectionHeading(
              label: AppText.strings.autosaveTitle,
              help: AppText.strings.autosaveSectionHelp,
            ),
            const SizedBox(height: 4),
            // 🚨F-1 (유저 2026-08-26): 「**자동저장 on off만 남기고** … 심플
            // 하게 명시적저장 / n분주기 자동저장만 남김」. Three switches
            // stood here — leaving the app, pausing, and the clock — and
            // two of them named triggers that no longer exist.
            SettingsSwitchRow(
              tileKey: const ValueKey<String>('settings-autosave-enabled'),
              label: AppText.strings.autosaveTitle,
              help: AppText.strings.autosaveSwitchHelp,
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
            SettingsSectionHeading(
              label: AppText.strings.recoverySnapshotsTitle,
              help: AppText.strings.recoverySnapshotsHelp,
            ),
            const SizedBox(height: 4),
            const _RecoverySnapshotsBlock(),
            const Divider(height: 16),
            // 유저 2026-08-30 thought this was already here — 「설정에서
            // 어차피 앱 컨테이너 파일 볼수있게 되있으니까 안되있으면
            // 되있도록하고 그거 유념」. Half of it was: the snapshots above
            // had a list and the other four tenants had none.
            SettingsSectionHeading(
              label: AppText.strings.appContainerTitle,
              help: AppText.strings.appContainerHelp,
            ),
            const SizedBox(height: 4),
            const _AppContainerBlock(),
            const Divider(height: 16),
            // REC1-B2: the take shelf. Mobile shows where takes land but
            // cannot move it (the app documents home is the only sane
            // place there); desktop may point it anywhere.
            SettingsSectionHeading(
              label: AppText.strings.recordingsFolderTitle,
              help: AppText.strings.recordingsFolderHelp,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppSave.recordingsRootDirectory,
                    key: const ValueKey<String>(
                      'settings-recordings-directory',
                    ),
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!Platform.isAndroid && !Platform.isIOS) ...[
                  if (settings.recordingsDirectory != null)
                    ControlPressClaim(
                      onPressed: () => session.setSaveSettings(
                        settings.copyWith(recordingsDirectory: null),
                      ),
                      child: TextButton(
                        key: const ValueKey<String>(
                          'settings-recordings-reset',
                        ),
                        onPressed: silentPress(
                          () => session.setSaveSettings(
                            settings.copyWith(recordingsDirectory: null),
                          ),
                        ),
                        child: Text(AppText.strings.autosaveDefault),
                      ),
                    ),
                  ControlPressClaim(
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
                    child: TextButton(
                      key: const ValueKey<String>('settings-recordings-browse'),
                      onPressed: silentPress(() async {
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
                      }),
                      child: Text(AppText.strings.autosaveChoose),
                    ),
                  ),
                ],
              ],
            ),
            // 🪦**THE CONFORM CACHE BLOCK IS GONE** — a heading, a movable
            // root, a size and an「empty now」button. All four existed
            // because the cache was an unbounded pile that outlived every
            // run, invisible on the platforms where it mattered most. A
            // conform now waits in the RUN'S room and moves into the
            // project at the next save, so the room's own row in the
            // container block below already counts it, and the room's own
            // ending already empties it.
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
    final proceed = await askConfirm(
      context,
      ConfirmQuestion(
        keys: (
          window: const ValueKey<String>('recovery-delete-dialog'),
          decline: const ValueKey<String>('recovery-delete-cancel'),
          accept: const ValueKey<String>('recovery-delete-confirm'),
        ),
        title: strings.recoveryDeleteTitle,
        titleIcon: Icons.delete_outline,
        message: strings.recoveryDeleteMessageTemplate.replaceAll(
          '{n}',
          '${_selected.length}',
        ),
      ),
      accept: ConfirmChoice(
        strings.commonDelete,
        emphasis: AppWindowActionEmphasis.danger,
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
                    ? AppText.strings.containerEmpty
                    : '${_rows.length} · ${byteSizeLabel(total)}',
                key: const ValueKey<String>('settings-recovery-size'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
            ControlPressClaim(
              onPressed: _selected.isEmpty ? null : _confirmDelete,
              child: TextButton(
                key: const ValueKey<String>('settings-recovery-delete'),
                onPressed: silentPress(
                  _selected.isEmpty ? null : _confirmDelete,
                ),
                child: Text(AppText.strings.commonDelete),
              ),
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
          // ⛔NO SCROLLBAR BY HAND. `AppScrollBehavior` already gives every
          // scrollable in the app the same one, so this was a SECOND bar over
          // it. 🧪It was also the app's one auto-hiding bar — the framework's
          // default fades the thumb when the list stops — which is how a rule
          // gets broken by writing nothing.
          child: ListView.builder(
            controller: _scroll,
            itemCount: _rows.length,
            itemExtent: 24,
            itemBuilder: (context, index) {
              final row = _rows[index];
              final selected = _selected.contains(row.path);
              return ControlPressClaim(
                onPressed: () => setState(() {
                  if (!_selected.add(row.path)) {
                    _selected.remove(row.path);
                  }
                }),
                child: InkWell(
                  key: ValueKey<String>('settings-recovery-row-${row.path}'),
                  onTap: silentPress(
                    () => setState(() {
                      if (!_selected.add(row.path)) {
                        _selected.remove(row.path);
                      }
                    }),
                  ),
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
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}


/// 🚨★★★**WHAT THE APP KEEPS OUTSIDE YOUR PROJECT FILE.**
///
/// 유저 2026-08-30 believed this was already here — 「설정에서 어차피 앱
/// 컨테이너 파일 볼수있게 되있으니까 **안되있으면 되있도록**하고 그거
/// 유념」 — and it was half true. Recovery snapshots had a list above;
/// the settings files, the brush tips, the conformed audio and the media
/// an import copied in had none, so a person deciding whether to let
/// imports live there could not see what was there already.
///
/// ⛔**Read-only, deliberately.** Recovery has a delete because a snapshot
/// is a copy of something that also exists. These are not all like that:
/// `Staged/` holds the ONLY copy of media a carried import has not yet
/// been saved into a project, and a delete button beside it would be a way
/// to lose exactly what the staging exists to keep. Seeing is what was
/// asked for.
///
/// ⛔The rows are FIXED, so the block never grows or shrinks as folders
/// come and go — 없다가 생기는 UI 금지. A folder the app has never written
/// to shows「—」rather than 0, because those are different facts.
class _AppContainerBlock extends StatefulWidget {
  const _AppContainerBlock();

  @override
  State<_AppContainerBlock> createState() => _AppContainerBlockState();
}

class _AppContainerBlockState extends State<_AppContainerBlock> {
  /// ⚠️The recovery row repeats the heading above it on purpose: this
  /// block accounts for the WHOLE container, and a total that quietly left
  /// one tenant out would be the least useful number on the screen.
  late final List<_ContainerArea> _rows = _measure();

  static List<_ContainerArea> _measure() {
    final strings = AppText.strings;
    return [
      _ContainerArea.settingsFiles('settings', strings.containerAreaSettings),
      _ContainerArea.folder(
        'brush-tips',
        strings.containerAreaBrushTips,
        appSupportFilePath('brush_tips'),
      ),
      _ContainerArea.folder(
        'recovery',
        strings.containerAreaRecovery,
        AppSave.recoveryDirectory(),
      ),
      // 🪦**NO `Conformed/` ROW.** Nothing writes there any more — a
      // conform waits in the run's room and moves into the project at the
      // next save — so the row would report 0 for ever, which reads as
      // 「the app keeps no conforms」 rather than 「that folder is retired」.
      // What the app DOES keep is counted by the session row below.
      // 🚨The WHOLE `Sessions/` tree, not this run's staged folder. Staged
      // media moved into a room per run, and the rooms of runs that
      // crashed are still holding bytes — pointing this row at our own
      // room would show a person 0 while the container held a gigabyte of
      // leftovers, which is the one question this panel exists to answer.
      _ContainerArea.folder(
        'session-scratch',
        strings.containerAreaSessionScratch,
        SessionScratch.rootFolder(),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    var total = 0;
    for (final row in _rows) {
      total += row.bytes;
    }
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in _rows)
          Padding(
            key: ValueKey<String>('settings-container-${row.id}'),
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(row.label, style: const TextStyle(fontSize: 12)),
                ),
                Text(
                  row.exists ? '${row.count}' : '—',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 76,
                  child: Text(
                    row.exists ? byteSizeLabel(row.bytes) : '—',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
              ],
            ),
          ),
        const Divider(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                AppText.strings.containerTotal,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            SizedBox(
              width: 76,
              child: Text(
                byteSizeLabel(total),
                key: const ValueKey<String>('settings-container-total'),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One area of the container, measured.
class _ContainerArea {
  const _ContainerArea({
    required this.id,
    required this.label,
    required this.count,
    required this.bytes,
    required this.exists,
  });

  /// The loose settings files, which share the container's root with the
  /// folders rather than having one of their own.
  factory _ContainerArea.settingsFiles(String id, String label) {
    final root = appSupportFilePath('');
    return _measureDirectory(
      id: id,
      label: label,
      path: root.endsWith('/') ? root.substring(0, root.length - 1) : root,
      recursive: false,
    );
  }

  factory _ContainerArea.folder(String id, String label, String path) =>
      _measureDirectory(id: id, label: label, path: path, recursive: true);

  static _ContainerArea _measureDirectory({
    required String id,
    required String label,
    required String path,
    required bool recursive,
  }) {
    final directory = Directory(path);
    if (!directory.existsSync()) {
      return _ContainerArea(
        id: id,
        label: label,
        count: 0,
        bytes: 0,
        exists: false,
      );
    }
    var count = 0;
    var bytes = 0;
    for (final entity in directory.listSync(recursive: recursive)) {
      if (entity is File) {
        count += 1;
        bytes += entity.lengthSync();
      }
    }
    return _ContainerArea(
      id: id,
      label: label,
      count: count,
      bytes: bytes,
      exists: true,
    );
  }

  /// Keys the row so a test can name it — the recovery row repeats the
  /// heading above it, and text alone cannot tell them apart.
  final String id;

  final String label;
  final int count;
  final int bytes;

  /// ⚠️A folder that does not exist yet is not a folder holding nothing —
  /// the app has simply never written there.
  final bool exists;
}
