import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../editor_session_manager.dart';
import '../shortcuts/editor_action_registry.dart' show EditorActionIds;
import '../shortcuts/editor_shortcut_scope.dart' show editorActionLabel;
import '../text/app_strings.dart';
import '../text/place_lines.dart' show cutNameWritten;
import '../widgets/panel_flyout.dart';
import 'layer_name_commands.dart' show renameCutWithDialog;
import 'timeline_layer_controls_header.dart' show LegendHeadingButton;

/// THE CUT LIST (I-154) — the timeline panel's legend heading: a button
/// that names the cut its playhead stands in and opens the list of the open
/// timeline's cuts, to stand in another.
///
/// 🗣️유저 2026-11-04: 「타임라인패널의 레전드행의 레이어부분, 콘티패널에선
/// 타임라인 버튼 보여주도록 바꼈으니 여기도 활용. 현재컷 이름을 여기로
/// 옮겨서, 누르면 컷 바꿀수있게 리스트팝오버로 비춤. 많으면 물론 스크롤바.
/// 그런부분은 콘티패널이나 다른 공용ui랑 법 통일. 그리고 해당 레전드의
/// 컷버튼 누르면 콘티패널은 타임라인 이름변경 삭제같은거 있는데 여기선
/// 이름변경만. 일단은」 — the conte panel's timeline list's button and list
/// (`timelineListButton`): the cut stood in in the accent, and each row's
/// one command its rename. A timeline of several tracks heads each track's
/// cuts with its name.
LegendHeadingButton cutListButton(
  BuildContext context,
  EditorSessionManager session,
) => LegendHeadingButton(
  label: _WrittenCutName(session.cutUnderPlayhead.cutName),
  tooltip: AppText.strings.cuts,
  entries: () => _entries(context, session),
);

List<PanelFlyoutEntry> _entries(
  BuildContext context,
  EditorSessionManager session,
) {
  final tracks = session.repository.requireProject().tracks;
  final standing = session.cutUnderPlayhead.listenable.value;
  return [
    PanelFlyoutHeader(AppText.strings.cuts),
    for (final track in tracks) ...[
      if (tracks.length > 1) PanelFlyoutHeader(track.name),
      for (final cut in track.cuts)
        PanelFlyoutItem(
          keyValue: 'cut-list-${cut.id.value}',
          label: cutNameWritten(cut.name),
          selected: cut.id == standing,
          onSelected: () => session.selectCut(cut.id),
          actions: [
            PanelFlyoutRowAction(
              keyValue: 'cut-list-${cut.id.value}-rename',
              icon: Icons.drive_file_rename_outline,
              tooltip: editorActionLabel(EditorActionIds.cutRename),
              onPressed: () =>
                  unawaited(renameCutWithDialog(context, session, cut)),
            ),
          ],
        ),
    ],
  ];
}

/// The cut stood in's name as its place writes it ([cutNameWritten]), heard
/// where [_name] turns over — equal for one source, as the kept legend
/// compares its heading.
@immutable
class _WrittenCutName implements ValueListenable<String> {
  const _WrittenCutName(this._name);

  final ValueListenable<String> _name;

  @override
  String get value => cutNameWritten(_name.value);

  @override
  void addListener(VoidCallback listener) => _name.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _name.removeListener(listener);

  @override
  bool operator ==(Object other) =>
      other is _WrittenCutName && identical(other._name, _name);

  @override
  int get hashCode => identityHashCode(_name);
}
