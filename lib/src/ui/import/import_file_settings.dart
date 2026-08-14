import '../../models/media_asset.dart';
import '../../services/project_lookup.dart' show mediaKindCarriedByDefault;
import '../../services/import/media_import_planner.dart' show ImportDestination;

/// What one FILE in the import window is set to.
///
/// The window used to hold one setting for the whole batch, and it lied
/// about whichever file the batch did not describe: a sound cannot be
/// rasterized, and an expanded PSD is baked by definition. A row per file
/// with a column per question tells the truth by construction — the cell
/// shows what THIS file will do.
///
/// The kind decides DEFAULTS, not ceilings. A movie starts as a reference
/// because that is what a three-gigabyte take should be, and it can still
/// be carried by someone who means it (user decision 2026-08-14, reversing
/// the ceiling set on 08-13).
///
/// Everything here is pure so the rules can be tested without a window: the
/// table renders these answers, it does not compute them.

/// How a file comes into the project. One axis, three answers, because
/// they are the same question — what does the project end up holding?
enum ImportFileMode {
  /// A pointer to where the file lives. Dies if the original moves.
  reference,

  /// The bytes travel inside the `.anicel`.
  keepInside,

  /// Not a file at all: the pixels become cels and nothing registers.
  rasterize,
}

/// A Photoshop document arrives one of two ways.
enum PsdPlaceMode {
  /// The composite: one picture, adjustments and effects already applied.
  merge,

  /// The stack: layers in a folder named after the file. Always baked.
  expand,
}

/// One row's answers.
class ImportFileSettings {
  const ImportFileSettings({
    this.mode = ImportFileMode.keepInside,
    this.into = ImportDestination.activeCutLayer,
    this.fit = MediaFitMode.contain,
    this.psd = PsdPlaceMode.merge,
    this.inFrame = 0,
    this.outFrame,
  });

  final ImportFileMode mode;

  /// Where a PLACED file lands. Ignored when the window is registering
  /// into the pool.
  final ImportDestination into;

  final MediaFitMode fit;
  final PsdPlaceMode psd;

  /// The trim, in source frames/pages. [outFrame] null means "to the end",
  /// which is what an un-trimmed source is — storing the last index would
  /// go stale the moment the count is read.
  final int inFrame;
  final int? outFrame;

  bool get isTrimmed => inFrame > 0 || outFrame != null;

  ImportFileSettings copyWith({
    ImportFileMode? mode,
    ImportDestination? into,
    MediaFitMode? fit,
    PsdPlaceMode? psd,
    int? inFrame,
    int? outFrame,
    bool clearOut = false,
  }) => ImportFileSettings(
    mode: mode ?? this.mode,
    into: into ?? this.into,
    fit: fit ?? this.fit,
    psd: psd ?? this.psd,
    inFrame: inFrame ?? this.inFrame,
    outFrame: clearOut ? null : (outFrame ?? this.outFrame),
  );

  @override
  bool operator ==(Object other) =>
      other is ImportFileSettings &&
      other.mode == mode &&
      other.into == into &&
      other.fit == fit &&
      other.psd == psd &&
      other.inFrame == inFrame &&
      other.outFrame == outFrame;

  @override
  int get hashCode => Object.hash(mode, into, fit, psd, inFrame, outFrame);
}

/// What a file of this [kind] answers before anyone has answered for it.
///
/// The one place the kind still speaks: a movie starts as a reference so
/// that dropping a three-gigabyte take does not quietly make a
/// three-gigabyte project, and everything else starts carried so that
/// moving a folder does not break the project.
ImportFileMode defaultImportMode(MediaAssetKind? kind) =>
    kind == null || mediaKindCarriedByDefault(kind)
    ? ImportFileMode.keepInside
    : ImportFileMode.reference;

/// Whether [path] is a Photoshop document — the only kind with a second
/// way in.
bool importPathIsPsd(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) {
    return false;
  }
  final extension = path.substring(dot + 1).toLowerCase();
  return extension == 'psd' || extension == 'psb';
}

/// Whether [mode] is offered for [kind]. A cell the file's own nature
/// refuses is shown OFF rather than hidden: the question was asked, and
/// the answer is that this file cannot.
bool importModeAllowed({
  required MediaAssetKind? kind,
  required ImportFileMode mode,
  required bool psdExpanding,
  required bool placing,
  required bool trimmed,
}) {
  switch (mode) {
    case ImportFileMode.rasterize:
      // Nothing is placed into the pool, so nothing can be absorbed there.
      if (!placing) {
        return false;
      }
      // Sound has no pixels; a movie has no decoder yet.
      return kind == MediaAssetKind.image || kind == MediaAssetKind.pdf;
    case ImportFileMode.keepInside:
      // An expanded PSD IS its pixels — there is no file left to keep.
      if (psdExpanding) {
        return false;
      }
      // Every kind may be carried now. The kind still decides what a file
      // answers by DEFAULT — a movie starts as a reference — but a person
      // who wants a three-second take inside the project file gets to say
      // so, with the size warning naming the cost before it lands.
      return true;
    case ImportFileMode.reference:
      if (psdExpanding) {
        return false;
      }
      // A trim keeps only part of the source, and a pointer cannot say
      // "part". What is trimmed has to be carried.
      return !trimmed;
  }
}

/// [settings] with every answer this file can actually give.
///
/// The window never has to remember which combinations are impossible: it
/// stores what the user pressed and asks here what that MEANS for this
/// file. A movie set to Keep inside comes back Reference, and the row says
/// Reference — the same answer the save would have reached anyway, arrived
/// at before the user is surprised by it.
ImportFileSettings resolvedImportSettings(
  ImportFileSettings settings, {
  required MediaAssetKind? kind,
  required bool isPsd,
  required bool placing,
}) {
  final expanding = isPsd && placing && settings.psd == PsdPlaceMode.expand;
  if (expanding) {
    // Expanding bakes the whole stack: "one of them baked means all of
    // them are" (the user's rule), so the file question has one answer.
    return settings.copyWith(mode: ImportFileMode.rasterize);
  }
  final trimmed = settings.isTrimmed;
  if (importModeAllowed(
    kind: kind,
    mode: settings.mode,
    psdExpanding: false,
    placing: placing,
    trimmed: trimmed,
  )) {
    return settings;
  }
  // The fallback order is the least surprising one left: a file that
  // cannot be absorbed is carried, and one that cannot be carried is
  // pointed at.
  for (final fallback in const [
    ImportFileMode.keepInside,
    ImportFileMode.reference,
  ]) {
    if (importModeAllowed(
      kind: kind,
      mode: fallback,
      psdExpanding: false,
      placing: placing,
      trimmed: trimmed,
    )) {
      return settings.copyWith(mode: fallback);
    }
  }
  return settings.copyWith(mode: ImportFileMode.reference);
}

/// The short word the row's cell shows.
String importModeLabel(ImportFileMode mode) => switch (mode) {
  ImportFileMode.reference => 'Ref',
  ImportFileMode.keepInside => 'Keep',
  ImportFileMode.rasterize => 'Raster',
};

String importFitLabel(MediaFitMode fit) => switch (fit) {
  MediaFitMode.stretch => 'Stretch',
  MediaFitMode.contain => 'Keep',
  MediaFitMode.none => '1:1',
};

String importIntoLabel(ImportDestination into) => switch (into) {
  ImportDestination.activeCutLayer => 'Layer',
  ImportDestination.newCut => 'New cut',
};
