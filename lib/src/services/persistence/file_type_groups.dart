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

import 'package:file_selector/file_selector.dart';

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

/// The picker filters, one per surface that opens a file dialog.
abstract final class FileTypeGroups {
  /// Project files. The only type this app OWNS, hence a private identifier
  /// rather than an umbrella.
  static const XTypeGroup anicelProject = XTypeGroup(
    label: 'Anicel project',
    extensions: [anicelProjectExtension],
    uniformTypeIdentifiers: [anicelProjectUti],
  );

  /// Brush packs (Photoshop `.abr`, Clip Studio `.sut`/`.sutg`).
  ///
  /// These fall back to `public.data` — i.e. no filtering on Apple platforms —
  /// on purpose. Apple ships no type for any of them, and the honest choice
  /// is between showing everything and showing NOTHING: a filter naming
  /// identifiers the system has never heard of greys out every file in the
  /// picker, including the brush the user came to fetch. Declaring imported
  /// types under Adobe's and Celsys' reverse-DNS would be squatting on
  /// identifiers neither vendor has published. The importer already rejects a
  /// wrong file with a real message, so the loose filter costs nothing.
  static const XTypeGroup brushes = XTypeGroup(
    label: 'Brushes (Photoshop, Clip Studio)',
    extensions: brushFileExtensions,
    uniformTypeIdentifiers: [_utiData],
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
