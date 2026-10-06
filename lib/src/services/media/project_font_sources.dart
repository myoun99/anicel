import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/font_face_facts.dart';
import '../../models/project.dart';
import '../persistence/anicel_project_archive.dart';
import 'media_byte_source.dart';
import 'project_media_sources.dart' show readableAnicelLayout;

/// WHAT A SAVE SHOULD DO ABOUT THE FONTS A PROJECT CARRIES (R9-rest, the
/// text tool's faces): the entry names the project may hold, and where the
/// bytes of each one that can be read are right now.
///
/// 🚨TWO FIELDS, ASKED TWO QUESTIONS. [held] is every font file registered
/// with the project (`Project.fonts`) — WHAT LEAVES is asked of it, and of
/// nothing else. [entries] is the ones whose bytes could be found — what
/// the save can write. A font whose bytes are nowhere this machine can
/// reach is held and has no entry: the save writes nothing for it, takes
/// nothing away, and does not fail.
///
/// ⛔Not one map whose keys answer both, as a conform's is
/// (`ProjectConforms`: "one field cannot disagree with itself" — and its
/// second set was buried there). That works for a conform because losing
/// one to a wrong "nothing here" costs a rebuild. A font cannot be made
/// again and may be on no device but the one it came from, so what takes it
/// out of a file has to be the one thing that is a person's decision — the
/// project's own list (유저 2026-10-06: 「뺄때까지 두는게 맞지않나 싶은데.
/// 글꼴을 사실상 등록하는거잖아」) — and never whether this save happened to
/// find bytes: a file that could not be read at that moment would otherwise
/// read as a font taken out. ⚠️[held] is a pure reading of the list, with
/// one name a font, so it cannot keep what the list let go of — which is
/// how the conforms' second set leaked.
@immutable
class ProjectFontsToStore {
  const ProjectFontsToStore({required this.held, required this.entries});

  /// A project that carries no font: every font entry in the file leaves.
  const ProjectFontsToStore.none() : held = const {}, entries = const {};

  /// Every archive ENTRY NAME the project may hold.
  final Set<String> held;

  /// **Archive entry name** → where those bytes are right now: the entry
  /// the project file already holds, or the device's own copy of the font.
  final Map<String, MediaByteSource> entries;
}

/// What a save of [project] onto — or away from — the file at
/// [projectFilePath] should do about its fonts.
///
/// The file's own entry first, and the device's copy where the file has
/// none ([deviceFontFileFor] — the path of this device's file of that face,
/// or null): once written, an entry is what the name MEANS, and the device
/// may have been brought another file of the same face since.
///
/// ⚠️Resolved fresh at every save, like the media sources: the archive
/// half is a byte range, and offsets belong to one layout.
ProjectFontsToStore projectFontSources({
  required Project project,
  required String? projectFilePath,
  required String? Function(FontFaceFacts face) deviceFontFileFor,
}) {
  if (project.fonts.isEmpty) {
    return const ProjectFontsToStore.none();
  }
  final layout = readableAnicelLayout(projectFilePath);
  final entries = <String, MediaByteSource>{};
  for (final font in project.fonts) {
    final name = anicelFontEntryName(font.carriedAs);
    final inFile = layout?.entryNamed(name);
    if (inFile != null) {
      entries[name] = MediaArchiveBytes.ofEntry(
        archivePath: projectFilePath!,
        entry: inFile,
      );
      continue;
    }
    final onDevice = deviceFontFileFor(font.facts);
    if (onDevice != null && File(onDevice).existsSync()) {
      entries[name] = MediaFileBytes(onDevice);
    }
  }
  return ProjectFontsToStore(
    held: {
      for (final font in project.fonts) anicelFontEntryName(font.carriedAs),
    },
    entries: entries,
  );
}
