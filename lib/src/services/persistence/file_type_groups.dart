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

import 'anicel_project_archive.dart';

/// The exported type for a project file — the identifier declared in both
/// Apple Info.plists. Public because a test pins the two together.
const String anicelProjectUti = 'com.myoun.anicel.project';

/// Apple's umbrella types. Filtering on the umbrella rather than on a dozen
/// concrete identifiers is deliberate: it keeps working for formats the OS
/// gains later, and it is the only way `flac`/`ogg`/`mkv`/`webm` become
/// selectable at all (the Info.plists import them CONFORMING to these, so
/// the umbrella catches them).
const String _utiImage = 'public.image';
const String _utiAudio = 'public.audio';
const String _utiMovie = 'public.movie';
const String _utiPdf = 'com.adobe.pdf';
const String _utiJson = 'public.json';

/// Everything. Used where a filter would do more harm than good — see
/// [FileTypeGroups.brushes].
const String _utiData = 'public.data';

/// Raster formats the tip/image decoders accept.
const List<String> imageFileExtensions = [
  'png',
  'jpg',
  'jpeg',
  'webp',
  'bmp',
  'gif',
];

/// Sound formats the audio conform can decode.
const List<String> audioFileExtensions = [
  'mp3',
  'wav',
  'm4a',
  'aac',
  'flac',
  'ogg',
];

/// Movie containers the media pool will register.
const List<String> videoFileExtensions = ['mp4', 'mov', 'avi', 'mkv', 'webm'];

/// Brush packs Anicel can import.
const List<String> brushFileExtensions = ['abr', 'sut', 'sutg'];

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
  _utiJson: 'application/json',
  _utiData: '*/*',
  anicelProjectUti: '*/*',
};

/// Every identifier this file hands to a picker. Public so the test can
/// assert the mapping covers all of them.
@visibleForTesting
const List<String> allPickerUtis = [
  _utiImage,
  _utiAudio,
  _utiMovie,
  _utiPdf,
  _utiJson,
  _utiData,
  anicelProjectUti,
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

  /// Brush packs (Photoshop `.abr`, Clip Studio `.sut`/`.sutg`) — the one
  /// group that cannot be the same on every Apple platform.
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

  /// Still images — the brush tip importer.
  static const XTypeGroup images = XTypeGroup(
    label: 'Images',
    extensions: imageFileExtensions,
    uniformTypeIdentifiers: [_utiImage],
  );

  /// What the media viewer can actually display today.
  static const XTypeGroup viewableMedia = XTypeGroup(
    label: 'Viewable media',
    extensions: [...imageFileExtensions, 'pdf'],
    uniformTypeIdentifiers: [_utiImage, _utiPdf],
  );

  /// What the import window can place on the timeline: stills, documents and
  /// sound. Video is absent because placement is not implemented — the import
  /// window refuses a movie by kind, so offering one in its picker would only
  /// produce a warning row.
  static const XTypeGroup importableMedia = XTypeGroup(
    label: 'Media',
    extensions: [...imageFileExtensions, 'pdf', ...audioFileExtensions],
    uniformTypeIdentifiers: [_utiImage, _utiPdf, _utiAudio],
  );

  /// A TVPaint JSON export — the `.json` sitting beside the per-instance
  /// image folders it describes.
  static const XTypeGroup tvpaintJson = XTypeGroup(
    label: 'TVPaint JSON export',
    extensions: ['json'],
    uniformTypeIdentifiers: [_utiJson],
  );

  /// Everything the media pool will register, movies included. Wider than
  /// [importableMedia] because the browser registers assets rather than
  /// placing them.
  static const XTypeGroup poolMedia = XTypeGroup(
    label: 'Media',
    extensions: [
      ...audioFileExtensions,
      ...imageFileExtensions,
      ...videoFileExtensions,
      'pdf',
    ],
    uniformTypeIdentifiers: [_utiAudio, _utiImage, _utiMovie, _utiPdf],
  );
}
