import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../services/persistence/app_documents.dart'
    show ensuredAppDocumentsDirectorySync;
import '../../services/persistence/file_type_groups.dart';
import '../../services/persistence/folder_grant.dart';
import '../../services/persistence/provider_documents.dart';
import '../brush/picked_file.dart' show PickedFile;
import '../dialogs/app_confirm_dialog.dart' show showAppNotice;
import '../dialogs/folder_pick_flow.dart';
import '../dialogs/open_file_flow.dart' show noticeUnsupportedFiles;
import '../text/app_strings.dart';
import 'project_open_door.dart' show ProjectPick, projectPickOf;

/// What a door holds, sorted by where each goes ([openedAs]).
typedef SortedOpen = ({
  List<ProjectPick> projects,
  List<FolderGrant> media,
  List<FolderGrant> brushes,
  List<FolderGrant> fonts,
  List<FolderGrant> shortcuts,
  List<FolderGrant> palettes,
  List<FolderGrant> settings,
  List<FolderGrant> fxPlugins,
  List<String> refused,
});

/// [handed] sorted by the one judgement: a project opens in a tab, a
/// picture · movie · sound · PDF, a FOLDER (a cut folder) and a settings
/// file come in through the import window, a brush goes to the brush
/// library, a font
/// to this device's fonts, a program's shortcut files into a preset, a
/// palette into the palettes and an fx plugin into this device's plugins —
/// and what nothing opens is named.
SortedOpen sortOpened(List<FolderGrant> handed) {
  final projects = <ProjectPick>[];
  final media = <FolderGrant>[];
  final brushes = <FolderGrant>[];
  final fonts = <FolderGrant>[];
  final shortcuts = <FolderGrant>[];
  final palettes = <FolderGrant>[];
  final settings = <FolderGrant>[];
  final fxPlugins = <FolderGrant>[];
  final refused = <String>[];
  for (final grant in handed) {
    final named = grant.document?.uri ?? grant.path;
    if (named == null) {
      continue;
    }
    if (grant.kind == GrantKind.folder) {
      media.add(grant);
      continue;
    }
    switch (openedAs(named)) {
      case OpenedAs.project:
        projects.add(projectPickOf(grant)!);
      case OpenedAs.media:
        media.add(grant);
      case OpenedAs.brush:
        brushes.add(grant);
      case OpenedAs.font:
        fonts.add(grant);
      case OpenedAs.shortcuts:
        shortcuts.add(grant);
      case OpenedAs.settings:
        settings.add(grant);
      case OpenedAs.fxPlugin:
        fxPlugins.add(grant);
      case OpenedAs.palette:
        palettes.add(grant);
      case null:
        // Named as every pick's refusal names it: a file by its path, a
        // document by its own name (its URI says nothing).
        refused.add(grant.path ?? ProviderDocuments.nameOf(named));
    }
  }
  return (
    projects: projects,
    media: media,
    brushes: brushes,
    fonts: fonts,
    shortcuts: shortcuts,
    palettes: palettes,
    settings: settings,
    fxPlugins: fxPlugins,
    refused: refused,
  );
}

/// 「파일 열기」's pick: every kind some door takes, several at once — a
/// file nothing takes is named by the pick itself, and a document with no
/// filesystem path is taken as one (PICK-7).
///
/// A DESKTOP starting folder, and the SYNC twin on purpose: async `dart:io`
/// never completes under the widget-test clock, and this is the first line
/// of the open flow. Withheld wherever grants are scoped — on macOS the
/// sandbox makes `$HOME` the container, so this would point at
/// `~/Library/Containers/…/Documents/Anicel` and the panel would open
/// inside the sandbox on every Open. With no hint the Apple pickers restore
/// wherever the user last was, which is what Files trains them to expect.
/// (The project Open's hint; the import window's own pick had none.)
Future<List<FolderGrant>> pickFilesToOpen(BuildContext context) =>
    pickFileGrantsForUser(
      context,
      supportedExtensions: openableExtensions,
      allowMultiple: true,
      acceptsDocuments: true,
      initialDirectory: FolderPicker.grantsAreScoped
          ? null
          : ensuredAppDocumentsDirectorySync(),
    );

/// THE ONE DOOR. F-282 (유저 2026-10-09): 「열기랑 임포트랑 되도록 하나로
/// 합치고싶고, 드래그앤드롭으로 파일 여는거라던가 풀에 등록할떄? 등 관련
/// 임포트 전부 점검하는게 목표」 · 「최대한 통일하고싶음」. Every way a file
/// comes in hands what it holds here — the menu's 「파일 열기」 and
/// 「폴더 열기」, a drop on the window, the media panel's ＋, the viewer's
/// 「미디어에 등록」 — and one judgement ([sortOpened]) says where each goes.
///
/// ↩️Each door judged on its own until then: the menu's Open took projects
/// alone, its 「가져오기/배치…」 opened the window on nothing, a drop let
/// any file into the window — and the window registered what it could not
/// name as a picture.
///
/// One order, whatever came: what nothing opens is said first, then what
/// the libraries took, then the import window — and the projects once it
/// has closed (F-247, 유저 2026-09-30: its files go into the project the
/// drop landed on, which an open would take off the screen).
final class OpenedFilesDoor {
  const OpenedFilesDoor({
    required this.openProjects,
    required this.importWindow,
    required this.bringBrushes,
    required this.bringFont,
    required this.bringShortcuts,
    required this.bringPalettes,
    required this.bringFxPlugins,
  });

  /// Opens each pick in a tab of its own — the shell's Open door, which
  /// holds the tabs a project opens into.
  final Future<void> Function(List<ProjectPick> picks) openProjects;

  /// The import window over [picked], answering once it has closed.
  /// [toPool]: it was a pool's door that was knocked on — the media panel's
  /// ＋ or the viewer's 「미디어에 등록」 — so the window registers.
  final Future<void> Function(List<FolderGrant> picked, {required bool toPool})
  importWindow;

  /// Brings the brush file [name], holding [bytes], into the library — what
  /// to say of it.
  final Future<String?> Function(String name, Uint8List bytes) bringBrushes;

  /// Brings the font file holding [bytes] into this device's fonts — what to
  /// say of it.
  final Future<String?> Function(Uint8List bytes) bringFont;

  /// Makes the shortcut files [files] into presets (I-107) — what to say of
  /// them. All at once: one program's files that come in together make one
  /// preset.
  final Future<List<String>> Function(List<PickedFile> files) bringShortcuts;

  /// Brings the palette file [name], holding [bytes], into the palettes
  /// (I-142) — what to say of it.
  final Future<String?> Function(String name, Uint8List bytes) bringPalettes;

  /// Installs the fx plugin file [name], holding [bytes], once the person
  /// has said yes to what it says of itself (I-132) — what to say of it.
  final Future<String?> Function(String name, Uint8List bytes)
  bringFxPlugins;

  /// Takes [handed] in, each where the judgement sends it.
  Future<void> open(
    BuildContext context,
    List<FolderGrant> handed, {
    bool toPool = false,
  }) async {
    final sorted = sortOpened(handed);
    if (sorted.refused.isNotEmpty) {
      await noticeUnsupportedFiles(context, sorted.refused, openableExtensions);
      if (!context.mounted) {
        return;
      }
    }
    final shortcuts = [
      for (final grant in sorted.shortcuts) await _read(grant),
    ];
    final said = [
      for (final grant in sorted.brushes) await _bring(grant, bringBrushes),
      for (final grant in sorted.fonts)
        await _bring(grant, (_, bytes) => bringFont(bytes)),
      for (final grant in sorted.palettes) await _bring(grant, bringPalettes),
      for (final grant in sorted.fxPlugins)
        await _bring(grant, bringFxPlugins),
      for (final (:name, :bytes) in shortcuts)
        if (bytes == null) AppText.strings.imUnreadable(name),
      if (shortcuts.any((file) => file.bytes != null))
        ...await bringShortcuts([
          for (final (:name, :bytes) in shortcuts)
            if (bytes != null) (name: name, bytes: bytes),
        ]),
    ].nonNulls.toList();
    if (!context.mounted) {
      return;
    }
    if (said.isNotEmpty) {
      await showAppNotice(
        context,
        title: AppText.strings.commonNotice,
        message: said.join('\n'),
        windowKey: const ValueKey<String>('opened-into-libraries-notice'),
      );
      if (!context.mounted) {
        return;
      }
    }
    // A settings file comes in through the import window too, its settings
    // rows of it (🗣️I-142-Q6: 「임포트 창에 설정 파일의 행으로」 —
    // 「최대한 통일하고싶은게 이유」).
    final intoTheWindow = [...sorted.media, ...sorted.settings];
    if (intoTheWindow.isNotEmpty) {
      await importWindow(intoTheWindow, toPool: toPool);
      if (!context.mounted) {
        return;
      }
    }
    if (sorted.projects.isNotEmpty) {
      await openProjects(sorted.projects);
    }
  }

  /// [grant]'s bytes handed to [bring] under the file's own name — what it
  /// said, or why the file could not be read.
  static Future<String?> _bring(
    FolderGrant grant,
    Future<String?> Function(String name, Uint8List bytes) bring,
  ) async {
    final (:name, :bytes) = await _read(grant);
    return bytes == null
        ? AppText.strings.imUnreadable(name)
        : bring(name, bytes);
  }

  /// [grant]'s bytes under the file's own name — none where it could not be
  /// read.
  static Future<({String name, Uint8List? bytes})> _read(
    FolderGrant grant,
  ) async {
    final named = grant.document?.uri ?? grant.path!;
    final name = ProviderDocuments.nameOf(named);
    try {
      return (name: name, bytes: await _bytesOf(grant));
    } on Object {
      return (name: name, bytes: null);
    }
  }

  /// What [grant] holds: the file at its path, or — a document with no
  /// filesystem path (PICK-7) — its working copy, let go of once read.
  static Future<Uint8List> _bytesOf(FolderGrant grant) async {
    final path = grant.path;
    if (path != null) {
      return File(path).readAsBytes();
    }
    final source = await FolderPicker.materializeOpenedFile(
      grant.document!.uri,
    );
    try {
      return await File(source.path).readAsBytes();
    } finally {
      ProviderDocuments.letGo(source.path);
      if (source.staged) {
        await File(source.path).delete().then<void>((_) {}, onError: (_) {});
      }
    }
  }
}
