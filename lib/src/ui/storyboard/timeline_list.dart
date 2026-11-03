import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../models/project_timeline.dart';
import '../dialogs/app_prompt_dialog.dart';
import '../dialogs/dialog_verb.dart' show askThenCommit;
import '../session/timeline_verbs.dart';
import '../text/app_strings.dart';
import '../timeline/timeline_layer_controls_header.dart'
    show LegendHeadingButton;
import '../widgets/panel_flyout.dart';

/// What [timeline] is called: its name, or the one its number gives.
String timelineNameOf(ProjectTimeline timeline) =>
    timeline.name ?? AppText.strings.timelineNumbered(timeline.number);

/// THE TIMELINE LIST (I-150) — the conte panel's legend heading: a button
/// that names the open timeline and opens the list of them.
///
/// 🗣️유저 2026-11-03: 「기본값은 트랙1이고 누르면 리스트 팝오버로 트랙
/// 리스트뜸. 해당 영역 전부 버튼이고, 리스트에서 선택되있는 트랙이 텍스트
/// 강조색 … 각 리스트에 오른쪽정렬로 오른쪽부터 삭제, 그 왼쪽에 복제 아이콘,
/// 그 왼쪽에 연필아이콘」. The app's one list (`PanelFlyoutItem`): the open
/// one in the accent, a ＋ on the heading, and the row's commands at its end
/// in the shortcut presets' order and glyphs — rename, duplicate, delete.
LegendHeadingButton timelineListButton(
  BuildContext context,
  TimelineVerbs verbs,
) => LegendHeadingButton(
  label: timelineNameOf(
    verbs.timelines.firstWhere(
      (timeline) => timeline.id == verbs.currentTimelineId,
    ),
  ),
  tooltip: AppText.strings.timelines,
  entries: () => _entries(context, verbs),
);

List<PanelFlyoutEntry> _entries(BuildContext context, TimelineVerbs verbs) {
  final strings = AppText.strings;
  final timelines = verbs.timelines;
  return [
    PanelFlyoutHeader(
      strings.timelines,
      action: PanelFlyoutRowAction(
        keyValue: 'timeline-add',
        icon: Icons.add,
        tooltip: strings.timelineNew,
        does: PanelFlyoutActionDoes.adds,
        onPressed: verbs.addTimeline,
      ),
    ),
    for (final timeline in timelines)
      PanelFlyoutItem(
        keyValue: 'timeline-${timeline.id.value}',
        label: timelineNameOf(timeline),
        selected: timeline.id == verbs.currentTimelineId,
        onSelected: () => verbs.openTimeline(timeline.id),
        actions: [
          PanelFlyoutRowAction(
            keyValue: 'timeline-${timeline.id.value}-rename',
            icon: Icons.drive_file_rename_outline,
            tooltip: strings.timelineRename,
            onPressed: () => unawaited(_rename(context, verbs, timeline)),
          ),
          PanelFlyoutRowAction(
            keyValue: 'timeline-${timeline.id.value}-duplicate',
            icon: Icons.content_copy,
            tooltip: strings.timelineDuplicate,
            does: PanelFlyoutActionDoes.adds,
            onPressed: () => unawaited(_duplicate(context, verbs, timeline)),
          ),
          PanelFlyoutRowAction(
            keyValue: 'timeline-${timeline.id.value}-delete',
            icon: Icons.delete_outline,
            tooltip: strings.timelineDelete,
            does: PanelFlyoutActionDoes.deletes,
            enabled: timelines.length > 1,
            onPressed: () => verbs.deleteTimeline(timeline.id),
          ),
        ],
      ),
  ];
}

/// [timeline] named as the user says — a name left as it was is no step,
/// and a blank one gives it back the name its number gives.
Future<void> _rename(
  BuildContext context,
  TimelineVerbs verbs,
  ProjectTimeline timeline,
) {
  final called = timelineNameOf(timeline);
  return askThenCommit<String>(
    context,
    dialog: (_) => AppPromptDialog.keyed(
      keyPrefix: 'timeline-rename',
      title: AppText.strings.timelineRename,
      titleIcon: Icons.drive_file_rename_outline,
      fieldLabel: AppText.strings.commonNameField,
      initialValue: called,
      confirmLabel: AppText.strings.commonRename,
    ),
    commit: (name) {
      if (name.trim() != called) {
        verbs.renameTimeline(timeline.id, name);
      }
    },
  );
}

/// [timeline] copied whole, right after it and opened, under the name the
/// user gives — offered as a copy's, as a shortcut preset's duplicate is.
Future<void> _duplicate(
  BuildContext context,
  TimelineVerbs verbs,
  ProjectTimeline timeline,
) => askThenCommit<String>(
  context,
  dialog: (_) => AppPromptDialog.keyed(
    keyPrefix: 'timeline-duplicate',
    title: AppText.strings.timelineDuplicate,
    titleIcon: Icons.content_copy,
    fieldLabel: AppText.strings.commonNameField,
    initialValue: AppText.strings.copyNamed(timelineNameOf(timeline)),
    confirmLabel: AppText.strings.commonSave,
  ),
  commit: (name) => verbs.duplicateTimeline(timeline.id, name),
);
