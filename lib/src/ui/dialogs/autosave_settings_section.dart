import 'dart:io' show Directory, File, FileStat, FileSystemEntityType, Platform;

import 'package:flutter/material.dart';

import '../../services/diagnostics/memory_black_box.dart';
import '../../services/persistence/app_save_settings.dart';
import '../../services/persistence/app_support_path.dart';
import '../../services/persistence/session_scratch.dart';
import '../editor_session_manager.dart';
import '../text/app_strings.dart';
import '../text/byte_size_label.dart';
import '../widgets/field_slider.dart';
import '../widgets/settings_rows.dart';
import 'folder_pick_flow.dart';
import '../input/control_press_claim.dart';

/// SAVE-1: the autosave policy section (Preferences ▸ Autosave).
///
/// 🚨★★★**AUTOSAVE SAVES THE PROJECT FILE** (유저 2026-09-07: 「기존 결정
/// 대로 자동저장이 파일갱신. 그게 싫으면 자동저장 off하면된다」). This doc
/// said the opposite — 「a recovery snapshot only, the project file changes
/// on an explicit save alone」 — for as long as a snapshot was what the
/// tick wrote. There is no snapshot and no location to name any more; the
/// switch and the number ARE the policy.
///
/// 🚨F-1 (2026-08-26) is what cut it to those two: **a switch and a number
/// of minutes**, nothing else to set.
///
/// The folders below are here because they are the shelves that used to
/// sit beside the project and no longer do — the section is "what the app
/// writes on its own, and where".
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
            // 🪦**THE RECOVERY SNAPSHOTS BLOCK IS GONE** — a heading, a list
            // with a size and a date per row, multi-select and a confirmed
            // Delete. It was asked for by name (Q-recovery-gc, 유저 08-26:
            //「위치나 수정날짜같은거 다 있고 거기서 여러개 선택해서 삭제」)
            // and it answered honestly for as long as snapshots existed.
            // The autosave tick saves the project file now, so there is no
            // second copy of anybody's work to show, to age out, or to
            // delete — and a panel listing a folder nothing writes to is a
            // row that says 「0」 for ever.
            // 유저 2026-08-30 thought this was already here — 「설정에서
            // 어차피 앱 컨테이너 파일 볼수있게 되있으니까 안되있으면
            // 되있도록하고 그거 유념」. Half of it was: the snapshots had a
            // list of their own and the other tenants had none. It is the
            // whole of it now.
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

/// 🚨★★★**WHAT THE APP KEEPS OUTSIDE YOUR PROJECT FILE.**
///
/// 유저 2026-08-30 believed this was already here — 「설정에서 어차피 앱
/// 컨테이너 파일 볼수있게 되있으니까 **안되있으면 되있도록**하고 그거
/// 유념」 — and it was half true. Recovery snapshots had a list of their
/// own; the settings files, the brush tips, the conformed audio and the
/// media an import copied in had none, so a person deciding whether to let
/// imports live there could not see what was there already. This block is
/// the whole answer now that the snapshots are gone.
///
/// ⛔**Read-only, deliberately.** The recovery list had a delete because a
/// snapshot was a copy of something that also existed. Nothing left here is
/// like that: `Staged/` holds the ONLY copy of media a carried import has
/// not yet been saved into a project, and a delete button beside it would
/// be a way to lose exactly what the staging exists to keep. Seeing is what
/// was asked for.
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
  /// ⚠️Every tenant of the container gets a row, down to a log measured in
  /// kilobytes: this block accounts for the WHOLE of it, and a total that
  /// quietly left one out would be the least useful number on the screen.
  late final List<_ContainerArea> _rows = _measure();

  static List<_ContainerArea> _measure() {
    final strings = AppText.strings;
    return [
      // 🪦**ONE ROW WHERE THERE WERE TWO.** The settings row measured the
      // loose files at the container ROOT and `brush-tips` measured the
      // folder beside them; both now live under `Settings/`, and two rows
      // over one tree would double-count — which on a block whose whole
      // job is a trustworthy total is worse than a missing line.
      _ContainerArea.folder(
        'settings',
        strings.containerAreaSettings,
        appSupportFilePath('Settings'),
      ),
      // 🪦**NO `Recovery/` ROW.** Same reasoning as the conform row below,
      // and a round later: the autosave tick saves the project file, so
      // nothing writes a snapshot and the row would report 0 for ever.
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
      // The black box's one page. It is kilobytes, and it is a row anyway:
      // it is the last thing in the container that is not one of the two
      // rooms, and the total above it claims to be the whole of it.
      _ContainerArea.file(
        'diagnostics',
        strings.containerAreaDiagnostics,
        MemoryBlackBox.logPath(),
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

  // 🪦`_ContainerArea.settingsFiles` measured the container ROOT
  // non-recursively, because the settings were loose files sharing it with
  // the folders. They have a room now, so the ordinary folder factory
  // measures it and this special case has nothing left to be special
  // about.


  factory _ContainerArea.folder(String id, String label, String path) =>
      _measureDirectory(id: id, label: label, path: path, recursive: true);

  /// One FILE at the container root, as a row of its own.
  ///
  /// ⚠️It exists because the total has to stay true. The block's whole job
  /// is「what is outside my project files, and how much」, and a tenant
  /// left out makes that number the least useful thing on the screen — the
  /// size being small is not the same as the row being optional.
  factory _ContainerArea.file(String id, String label, String path) {
    final stat = FileStat.statSync(path);
    final found = stat.type == FileSystemEntityType.file;
    return _ContainerArea(
      id: id,
      label: label,
      count: found ? 1 : 0,
      bytes: found ? stat.size : 0,
      exists: found,
    );
  }

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

  /// Keys the row so a test can name it, rather than reaching for a label
  /// that changes with the language.
  final String id;

  final String label;
  final int count;
  final int bytes;

  /// ⚠️A folder that does not exist yet is not a folder holding nothing —
  /// the app has simply never written there.
  final bool exists;
}
