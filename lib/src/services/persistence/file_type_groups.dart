/// PICK-1: the one place that knows what a file picker may accept.
///
/// Six call sites used to spell their own `XTypeGroup` out inline, and every
/// one of them was broken on iPadOS for the same reason: `file_selector_ios`
/// filters by UNIFORM TYPE IDENTIFIER and throws `ArgumentError` on a group
/// that carries only extensions. Apple's picker has no notion of "*.png" —
/// a filter is a list of types or it is nothing.
///
/// So a group here always carries BOTH:
///   - `extensions`, which is what Windows, Linux and Android filter on
///     (`file_selector_android` throws its own `ArgumentError` on a group
///     with neither extensions nor MIME types), and
///   - `uniformTypeIdentifiers`, which is what iOS and macOS filter on.
///
/// Adding a format means adding it in one place, and the platforms stay in
/// agreement by construction rather than by everyone remembering.
///
/// ⚠️Two of these lists have a partner OUTSIDE Dart. [anicelProjectUti] is
/// declared in `ios/Runner/Info.plist` and `macos/Runner/Info.plist`, and the
/// formats Apple ships no type for (`flac`, `ogg`, `mkv`, `webm`) are imported
/// there so that the broad filters below can reach them at all — an extension
/// with no declared type is not merely unfiltered on iOS, it is UNSELECTABLE.
/// `test/services/persistence/file_type_groups_test.dart` reads those plists
/// and fails if the two sides drift.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import '../../models/media_asset.dart'
    show
        audioFileExtensions,
        imageFileExtensions,
        mediaAssetKindForPath,
        pdfFileExtensions,
        videoFileExtensions;
import '../brush_pack_file.dart';
import '../fx_plugins/fx_plugin_bundle.dart' show anicelFxPluginExtension;
import '../shortcuts/program_keymap.dart' show shortcutFileExtensions;
import 'anicel_project_archive.dart';
import 'provider_documents.dart';
import 'settings_file.dart';

/// The exported type for a project file — the identifier declared in both
/// Apple Info.plists. Public because a test pins the two together.
const String anicelProjectUti = 'com.myoun.anicel.project';

/// The exported type for a brush file this app writes — declared in both
/// Apple Info.plists beside [anicelProjectUti], and pinned to them by the
/// same test.
///
/// ⚠️It is OURS, so it gets a private identifier rather than the `public.data`
/// umbrella the imported brush packs use: Apple ships no type for `.abr` or
/// `.sut` and squatting on Adobe's or Celsys' reverse-DNS would be wrong,
/// but nobody else owns `.anibrush`.
const String anicelBrushUti = 'com.myoun.anicel.brush';

/// The exported types for the settings files this app writes (I-142) — ours,
/// declared beside [anicelBrushUti] for the same reason.
const String anicelPaletteUti = 'com.myoun.anicel.palette';
const String anicelShortcutUti = 'com.myoun.anicel.shortcut';
const String anicelSettingsUti = 'com.myoun.anicel.settings';

/// Apple's umbrella types. Filtering on the umbrella rather than on a dozen
/// concrete identifiers is deliberate: it keeps working for formats the OS
/// gains later, and it is the only way `flac`/`ogg`/`mkv`/`webm` become
/// selectable at all (the Info.plists import them CONFORMING to these, so
/// the umbrella catches them).
const String _utiImage = 'public.image';
const String _utiAudio = 'public.audio';
const String _utiMovie = 'public.movie';
const String _utiPdf = 'com.adobe.pdf';

/// Everything. Used where a filter would do more harm than good — see
/// [FileTypeGroups.brushes].
const String _utiData = 'public.data';

/// Brush files Anicel can import — the two it borrows, and its own.
///
/// ⚠️`anibrush` is in here because import and export are one door: a format
/// the app writes and cannot read back would leave every exported brush
/// stranded on the machine that made it.
const List<String> brushFileExtensions = [
  anicelBrushExtension,
  'abr',
  'sut',
  'sutg',
];

/// Font files this device's letters can be set in — the text tool's
/// library. A collection is read as its first face (`font_file_reader`).
const List<String> fontFileExtensions = ['ttf', 'otf', 'ttc'];

/// What 「열기」 opens — and what a file dropped on the window is asked by,
/// so the two entrances read one list (F-247, 유저 2026-09-30: 「드래그앤드롭으로
/// 외부파일 임포트시 확장자?에 맞도록. anicel이면 배치창이아니라 새 프로젝트로
/// 열도록. tvpp도 똑같이」).
///
/// TVPaint projects open through the same door (the user's call: ONE
/// entry, the Open button — the import pickers retire later). A .tvpp
/// converts into cuts rather than loading as a project. So does a CLIP
/// STUDIO file: every timeline a cut (card `csp-clip-import-analysis` — a
/// cut container opens AS A PROJECT).
///
/// 🚨These are now what the open ACCEPTS, not what the dialog SHOWS —
/// 유저 2026-08-29 named this exact dialog: 「특히 윈도우 열기시 anicel
/// 이랑 tvp만 설정따라서 보이게 되있는데 그게아니라 … 어떤 확장자던
/// 선택할수 있게」.
const List<String> projectOpenExtensions = [
  anicelProjectExtension,
  'tvpp',
  'clip',
];

/// What a file OPENS AS — the one judgement every door a file comes in
/// through asks: the menu's 「파일 열기」, a drop on the window, the media
/// panel's ＋ and the viewer's 「미디어에 등록」 (F-282, 유저 2026-10-09:
/// 「열기랑 임포트랑 되도록 하나로 합치고싶고, 드래그앤드롭으로 파일
/// 여는거라던가 풀에 등록할떄? 등 관련 임포트 전부 점검」 · 「최대한
/// 통일하고싶음」).
///
/// ⚠️A FOLDER is no name's answer: the door that holds the path asks the
/// disk, and a folder comes in through the import window as a cut folder.
enum OpenedAs {
  /// Opens in a tab of its own ([projectOpenExtensions]).
  project,

  /// Comes in through the import window — a picture, a movie, a sound, a
  /// PDF ([mediaAssetKindForPath]).
  media,

  /// Goes into the brush library ([brushFileExtensions]).
  brush,

  /// Goes into this device's fonts ([fontFileExtensions]).
  font,

  /// Makes a program's keys a preset ([shortcutFileExtensions], I-107) —
  /// and our own file's preset one too ([anicelShortcutExtension], I-142).
  /// ⚠️`.txt` · `.ini` · `.cfg` are names other files use too: what is not
  /// a program's shortcut file is said so when it is read (the cost
  /// I-107-Q2 named — 유저 2026-10-18: 「다섯 다」).
  shortcuts,

  /// Goes into the palettes ([anicelPaletteExtension], I-142).
  palette,

  /// Comes in through the import window as its settings, a row each
  /// ([anicelSettingsExtension] — 🗣️I-142-Q6: 「임포트 창에 설정 파일의
  /// 행으로」).
  settings,

  /// Is installed as an fx plugin, once the person has seen what it says of
  /// itself ([anicelFxPluginExtension], I-132).
  fxPlugin,
}

/// What the file [pathOrUri] names opens as — null for a file nothing in the
/// app opens, which every door says by name.
///
/// By NAME, the way every door tells a file: a provider document's URI says
/// nothing of what it is (PICK-7), so its own name is read.
OpenedAs? openedAs(String pathOrUri) {
  final name = ProviderDocuments.nameOf(pathOrUri);
  final dot = name.lastIndexOf('.');
  if (dot < 0) {
    return null;
  }
  final extension = name.substring(dot + 1).toLowerCase();
  if (projectOpenExtensions.contains(extension)) {
    return OpenedAs.project;
  }
  if (brushFileExtensions.contains(extension)) {
    return OpenedAs.brush;
  }
  if (fontFileExtensions.contains(extension)) {
    return OpenedAs.font;
  }
  if (shortcutFileExtensions.contains(extension) ||
      extension == anicelShortcutExtension) {
    return OpenedAs.shortcuts;
  }
  if (extension == anicelPaletteExtension) {
    return OpenedAs.palette;
  }
  if (extension == anicelFxPluginExtension) {
    return OpenedAs.fxPlugin;
  }
  if (extension == anicelSettingsExtension) {
    return OpenedAs.settings;
  }
  return mediaAssetKindForPath(name) == null ? null : OpenedAs.media;
}

/// Every extension some door takes ([openedAs]) — what 「파일 열기」
/// accepts, and what the notice for a file it does not names.
const List<String> openableExtensions = [
  ...projectOpenExtensions,
  ...imageFileExtensions,
  ...videoFileExtensions,
  ...audioFileExtensions,
  ...pdfFileExtensions,
  ...brushFileExtensions,
  ...fontFileExtensions,
  ...shortcutFileExtensions,
  anicelShortcutExtension,
  anicelPaletteExtension,
  anicelSettingsExtension,
  anicelFxPluginExtension,
];

/// What each identifier means to Android, which filters by MIME and has
/// never heard of a uniform type identifier.
///
/// PICK-5: the native file picker takes both lists and each platform reads
/// its own, so the translation belongs beside the identifiers rather than at
/// a call site that would have to remember. A type with no sensible MIME
/// (the project's own) maps to `*/*` — the picker is a location chooser
/// there and the importer is what actually judges the file.
///
/// ⚠️A test fails if an identifier below gains no entry here: an unmapped
/// one silently narrows the Android picker to nothing, and the symptom
/// ("the picker shows no files") points nowhere near this map.
@visibleForTesting
const Map<String, String> mimeForUti = {
  _utiImage: 'image/*',
  _utiAudio: 'audio/*',
  _utiMovie: 'video/*',
  _utiPdf: 'application/pdf',
  _utiData: '*/*',
  anicelProjectUti: '*/*',
  anicelBrushUti: '*/*',
  anicelPaletteUti: '*/*',
  anicelShortcutUti: '*/*',
  anicelSettingsUti: '*/*',
};

/// Every identifier this file hands to a picker. Public so the test can
/// assert the mapping covers all of them.
@visibleForTesting
const List<String> allPickerUtis = [
  _utiImage,
  _utiAudio,
  _utiMovie,
  _utiPdf,
  _utiData,
  anicelProjectUti,
  anicelBrushUti,
  anicelPaletteUti,
  anicelShortcutUti,
  anicelSettingsUti,
];

/// The picker filters, one per surface that opens a file dialog.
abstract final class FileTypeGroups {
  /// The identifiers [groups] accept, flattened and de-duplicated.
  static List<String> utisFor(List<XTypeGroup> groups) {
    final seen = <String>{};
    for (final group in groups) {
      seen.addAll(group.uniformTypeIdentifiers ?? const []);
    }
    return seen.toList();
  }

  /// The MIME types [groups] accept. An identifier with no mapping is
  /// DROPPED rather than guessed — a wrong MIME filters out the very files
  /// the user came for, and `*/*` from the fallback below is the safer miss.
  static List<String> mimeTypesFor(List<XTypeGroup> groups) {
    final seen = <String>{};
    for (final uti in utisFor(groups)) {
      final mime = mimeForUti[uti];
      if (mime != null) {
        seen.add(mime);
      }
    }
    // A picker asked for nothing shows nothing on some providers; asked for
    // everything it at least lets the importer do the judging.
    return seen.isEmpty ? const ['*/*'] : seen.toList();
  }

  /// Project files. The only type this app OWNS, hence a private identifier
  /// rather than an umbrella.
  static const XTypeGroup anicelProject = XTypeGroup(
    label: 'Anicel project',
    extensions: [anicelProjectExtension],
    uniformTypeIdentifiers: [anicelProjectUti],
  );

  /// A plain WAV, for the one dialog that WRITES one: the pool's conform
  /// export. Apple publishes a UTI for this format, so unlike [brushesFor]
  /// below there is nothing to split per platform.
  static const XTypeGroup wav = XTypeGroup(
    label: 'WAV audio',
    extensions: ['wav'],
    uniformTypeIdentifiers: ['com.microsoft.waveform-audio'],
  );

  /// Anicel's OWN brush file, for the one place that WRITES one: the preset
  /// panel's export. We own the type, so it is declared rather than borrowed
  /// — see [anicelBrushUti].
  static const XTypeGroup anicelBrush = XTypeGroup(
    label: 'Anicel brush',
    extensions: [anicelBrushExtension],
    uniformTypeIdentifiers: [anicelBrushUti],
  );

  /// Anicel's own palette and shortcut preset files (I-142), for the places
  /// that write one: the palette's menu and the shortcut window's preset
  /// rows.
  static const XTypeGroup anicelPalette = XTypeGroup(
    label: 'Anicel palette',
    extensions: [anicelPaletteExtension],
    uniformTypeIdentifiers: [anicelPaletteUti],
  );

  static const XTypeGroup anicelShortcut = XTypeGroup(
    label: 'Anicel shortcut preset',
    extensions: [anicelShortcutExtension],
    uniformTypeIdentifiers: [anicelShortcutUti],
  );

  /// Every setting that travels, from the preferences window (I-142-Q1).
  static const XTypeGroup anicelSettings = XTypeGroup(
    label: 'Anicel settings',
    extensions: [anicelSettingsExtension],
    uniformTypeIdentifiers: [anicelSettingsUti],
  );

  /// Brush files for the IMPORT picker — ours plus the two it borrows
  /// (Photoshop `.abr`, Clip Studio `.sut`/`.sutg`). The one group that
  /// cannot be the same on every Apple platform.
  ///
  /// Apple ships no type for any of these formats, and declaring imported
  /// ones under Adobe's and Celsys' reverse-DNS would be squatting on
  /// identifiers neither vendor has published. On **iOS** that leaves a
  /// choice between showing everything and showing NOTHING — the picker
  /// filters on identifiers alone, so a group naming types the system has
  /// never heard of greys out every file including the brush the user came
  /// to fetch. `public.data` is the honest answer there, and the importer
  /// rejects a wrong file with a real message.
  ///
  /// On **macOS** the same `public.data` is a mistake: `file_selector_macos`
  /// passes extensions AND identifiers to the panel, which takes their
  /// UNION, so the umbrella swallows the extension filter and the panel
  /// offers every file on the disk. Dropping it leaves the extensions doing
  /// exactly the job they do on Windows and Linux.
  static XTypeGroup get brushes => brushesFor(Platform.operatingSystem);

  /// The decision as a pure function of the OS name, so the shape both
  /// Apple platforms get can be pinned from the Windows workstation this
  /// app is written on (the same seam `FolderPicker.scopedForPlatform`
  /// uses, and for the same reason: neither branch is reachable here).
  @visibleForTesting
  static XTypeGroup brushesFor(String operatingSystem) => XTypeGroup(
    label: 'Brushes (Photoshop, Clip Studio)',
    extensions: brushFileExtensions,
    uniformTypeIdentifiers: operatingSystem == 'macos'
        ? const []
        : const [_utiData],
  );

  /// Everything the media pool will register, movies included — what the
  /// one door sends to the import window, a relink's pick, and what the
  /// media viewer's Open takes.
  ///
  /// ⛔The viewer's half is a CLAIM about the viewer: it opens every kind
  /// here — a movie (2026-08-29), a sound as its waveform (09-08) — and a
  /// picker narrower than the viewer makes that untrue from the user's
  /// side, with nothing in the viewer failing to say so. ↩️It had a list of
  /// its own that still left sound out, 「the one deliberate absence」, a
  /// month after the viewer learned to open one (F-282-Q2, 유저 2026-10-09:
  /// 받는 종류는 열기와 같게, 소리 포함).
  static const XTypeGroup poolMedia = XTypeGroup(
    label: 'Media',
    extensions: [
      ...audioFileExtensions,
      ...imageFileExtensions,
      ...videoFileExtensions,
      ...pdfFileExtensions,
    ],
    uniformTypeIdentifiers: [_utiAudio, _utiImage, _utiMovie, _utiPdf],
  );
}
