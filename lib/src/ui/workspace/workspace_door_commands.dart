import 'package:flutter/foundation.dart';

/// The workspace's door as the top strip's 「파일 열기…」 and 「폴더 열기…」
/// reach it (F-282): the WORKSPACE holds what the door hands files to —
/// the import window, the brush library, the fonts — and the strip only
/// knocks. The mounted `EditorWorkspace` binds the verbs; a row pressed by
/// hand or by key calls in. Unbound calls are no-ops.
class WorkspaceDoorCommands {
  VoidCallback? _openFiles;
  VoidCallback? _openFolder;
  ValueSetter<List<String>>? _openPaths;
  Object? _owner;

  /// ⚠️Owner-scoped — see `TimelineLayerNavCommands.bind` for the failure
  /// an unconditional `unbind()` produced (유저 #13, 2026-08-14).
  void bind(
    Object owner, {
    required VoidCallback openFiles,
    required VoidCallback openFolder,
    required ValueSetter<List<String>> openPaths,
  }) {
    _owner = owner;
    _openFiles = openFiles;
    _openFolder = openFolder;
    _openPaths = openPaths;
  }

  void unbind(Object owner) {
    if (!identical(_owner, owner)) {
      return;
    }
    _owner = null;
    _openFiles = null;
    _openFolder = null;
    _openPaths = null;
  }

  /// 「파일 열기…」: pick files of any kind, and take each where it goes.
  void openFiles() => _openFiles?.call();

  /// 「폴더 열기…」: pick a folder, and take it in as a cut folder.
  void openFolder() => _openFolder?.call();

  /// Paths the OS handed the app, each where it goes — as a drop on the
  /// window takes them (`open-door-windows-open-with`: a file opened with
  /// Anicel from the Explorer arrives as a launch argument).
  void openPaths(List<String> paths) => _openPaths?.call(paths);
}
