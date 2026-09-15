import '../../services/media/media_asset_uses.dart';
import '../../services/persistence/cel_places.dart';
import 'app_strings.dart';

/// A place in a project as one line of a list: the names it is found by,
/// joined the way the canvas title joins a cut, a layer and a frame.
///
/// Two lists speak in these lines — the pictures a save could not carry
/// (C-save-percent) and the uses of a media pool file (F-118) — so a frame
/// on a row reads the same in both.
String celPlaceLine(CelPlace place) {
  final strings = AppText.strings;
  return switch (place) {
    DrawingCelPlace(:final ownerName, :final layerName, :final celName) =>
      '$ownerName · $layerName · $celName',
    ContePageInkPlace(:final pageNumber) =>
      '${strings.panelConte} · p$pageNumber',
    ConteRowInkPlace(:final cutName, :final celName) =>
      '${strings.panelConte} · $cutName · $celName',
    EnvelopeInkPlace(:final cutName) => '${strings.panelEnvelope} · $cutName',
    GoneCelPlace() => strings.saveCelsLostGone,
  };
}

/// One use of a media pool file as a line of the list the pool shows: a row
/// by its cut and its name, a frame as [celPlaceLine] names it.
String mediaAssetUseLine(MediaAssetUse use) => switch (use) {
  RowMediaUse(:final ownerName, :final layerName) => '$ownerName · $layerName',
  FrameMediaUse(:final place) => celPlaceLine(place),
};
