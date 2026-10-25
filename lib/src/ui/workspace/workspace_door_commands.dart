import 'package:flutter/foundation.dart';

import '../../services/persistence/folder_grant.dart' show FolderGrant;
import '../sheet/paper_editing.dart';

/// The workspace's door as the top strip's 「파일 열기」 and 「폴더 열기」
/// reach it (F-282): the WORKSPACE holds what the door hands files to —
/// the import window, the brush library, the fonts — and the strip only
/// knocks. The mounted `EditorWorkspace` binds the verbs; a row pressed by
/// hand or by key calls in. Unbound calls are no-ops.
///
/// And what the export window edits its papers with ([paperEditing],
/// I-127): the workspace holds the sheets' ink and switches too.
class WorkspaceDoorCommands {
  VoidCallback? _openFiles;
  VoidCallback? _openFolder;
  ValueSetter<List<FolderGrant>>? _openHanded;
  ValueGetter<PaperEditing?>? _paperEditing;
  Object? _owner;

  /// ⚠️Owner-scoped — see `TimelineLayerNavCommands.bind` for the failure
  /// an unconditional `unbind()` produced (유저 #13, 2026-08-14).
  void bind(
    Object owner, {
    required VoidCallback openFiles,
    required VoidCallback openFolder,
    required ValueSetter<List<FolderGrant>> openHanded,
    ValueGetter<PaperEditing?>? paperEditing,
  }) {
    _owner = owner;
    _openFiles = openFiles;
    _openFolder = openFolder;
    _openHanded = openHanded;
    _paperEditing = paperEditing;
  }

  void unbind(Object owner) {
    if (!identical(_owner, owner)) {
      return;
    }
    _owner = null;
    _openFiles = null;
    _openFolder = null;
    _openHanded = null;
    _paperEditing = null;
  }

  /// The papers' editing as the workspace on screen holds it, or null with
  /// none bound — a window then shows its papers without editing them.
  PaperEditing? get paperEditing => _paperEditing?.call();

  /// 「파일 열기」: pick files of any kind, and take each where it goes.
  void openFiles() => _openFiles?.call();

  /// 「폴더 열기」: pick a folder, and take it in as a cut folder.
  void openFolder() => _openFolder?.call();

  /// Files the OS handed the app, each where it goes — as a drop on the
  /// window takes them (`open-door-windows-open-with`: a file opened with
  /// Anicel from the Explorer arrives as a launch argument;
  /// `open-door-android-share`: one another app shares arrives as a pick).
  void openHanded(List<FolderGrant> handed) => _openHanded?.call(handed);
}
