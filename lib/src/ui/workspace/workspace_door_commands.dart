import 'package:flutter/foundation.dart';

/// The workspace's door as the top strip's 「파일 열기…」 and 「폴더 열기…」
/// reach it (F-282): the WORKSPACE holds what the door hands files to —
/// the import window, the brush library, the fonts — and the strip only
/// knocks. The mounted `EditorWorkspace` binds the verbs; a row pressed by
/// hand or by key calls in. Unbound calls are no-ops.
class WorkspaceDoorCommands {
  VoidCallback? _openFiles;
  VoidCallback? _openFolder;
  Object? _owner;

  /// ⚠️Owner-scoped — see `TimelineLayerNavCommands.bind` for the failure
  /// an unconditional `unbind()` produced (유저 #13, 2026-08-14).
  void bind(
    Object owner, {
    required VoidCallback openFiles,
    required VoidCallback openFolder,
  }) {
    _owner = owner;
    _openFiles = openFiles;
    _openFolder = openFolder;
  }

  void unbind(Object owner) {
    if (!identical(_owner, owner)) {
      return;
    }
    _owner = null;
    _openFiles = null;
    _openFolder = null;
  }

  /// 「파일 열기…」: pick files of any kind, and take each where it goes.
  void openFiles() => _openFiles?.call();

  /// 「폴더 열기…」: pick a folder, and take it in as a cut folder.
  void openFolder() => _openFolder?.call();
}
