import '../../models/media_asset.dart';
import '../../services/project_lookup.dart' show mediaKindCarriedByDefault;
import '../../services/import/import_layer_spot.dart';
import '../../services/import/media_import_planner.dart' show ImportDestination;
import '../text/app_strings.dart';

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

/// How a file is KEPT — the pool's question: a pointer to where the file
/// lives, or its bytes inside the project file.
///
/// ↩️It had a third answer, `rasterize`, from 2026-08-14 (`0154b50e`: 「they
/// were always one — what does the project end up holding」). The user split
/// the two again on 2026-09-11 (미디어 배치 라운드 5: 「플레이스에 따라서
/// 제대로 나누도록」). Once every placement's material is a pool entry,
/// baking stopped answering 「what does the project hold」 and started
/// answering 「what does the LAYER become」 — and a pooled file dropped on a
/// frame area answers both at once, which one cell cannot say. Baking is
/// [ImportFileSettings.bake] now.
enum ImportFileMode {
  /// A pointer to where the file lives. Dies if the original moves.
  reference,

  /// The bytes travel inside the `.anicel`.
  keepInside,
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
    this.bake = false,
    this.into = ImportDestination.activeCutLayer,
    this.fit = MediaFitMode.contain,
    this.psd = PsdPlaceMode.merge,
    this.inFrame = 0,
    this.outFrame,
  });

  final ImportFileMode mode;

  /// Whether the placed layer is BAKED into cels instead of drawing from the
  /// file — the layer's question, asked only where something is placed.
  ///
  /// Baking still registers the file: the material of every placement is a
  /// pool entry (user 2026-09-11: 「구워도 풀에 남음」).
  final bool bake;

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
    bool? bake,
    ImportDestination? into,
    MediaFitMode? fit,
    PsdPlaceMode? psd,
    int? inFrame,
    int? outFrame,
    bool clearOut = false,
  }) => ImportFileSettings(
    mode: mode ?? this.mode,
    bake: bake ?? this.bake,
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
      other.bake == bake &&
      other.into == into &&
      other.fit == fit &&
      other.psd == psd &&
      other.inFrame == inFrame &&
      other.outFrame == outFrame;

  @override
  int get hashCode =>
      Object.hash(mode, bake, into, fit, psd, inFrame, outFrame);
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

/// Whether [mode] may be answered. Every kind may be carried — the kind
/// still decides what a file answers by DEFAULT, and a person who wants a
/// three-second take inside the project file gets to say so, with the size
/// warning naming the cost before it lands.
///
/// ⏳A trim keeps only part of the source and a pointer is refused for it.
/// The user decided on 2026-09-11 to lift this (「구간 잘라도 참조 그대로:
/// 푼다 … 빈틈없이」) — it goes when every reader of a layer's reference
/// honours its start frame, not before.
bool importModeAllowed({
  required ImportFileMode mode,
  required bool trimmed,
}) => switch (mode) {
  ImportFileMode.keepInside => true,
  ImportFileMode.reference => !trimmed,
};

/// Whether the BAKE question is asked of a file of [kind] at all: only where
/// something is placed, and only of pictures. Sound has no pixels, and a
/// movie is not baked by this window until video placement brings its
/// decode-to-cels.
bool importBakeAllowed({required MediaAssetKind? kind, required bool placing}) =>
    placing && (kind == MediaAssetKind.image || kind == MediaAssetKind.pdf);

/// Whether the bake question has one answer: frames dropped on a row are
/// that row's own pixels (08-14 「셀에 떨어뜨리면 항상 굽기」), and an
/// expanded PSD IS its pixels — 「one of them baked means all of them are」
/// (the user's rule).
bool importBakeLocked({
  required bool isPsd,
  required bool placing,
  required PsdPlaceMode psd,
  ImportLayerSpot? spot,
}) =>
    spot is RowFramesSpot ||
    (isPsd && placing && psd == PsdPlaceMode.expand);

/// Whether the PSD question has one answer: a row's frames take the merged
/// picture — expanding makes layers, and a row takes frames.
bool importPsdLocked(ImportLayerSpot? spot) => spot is RowFramesSpot;

/// Whether the fit has one answer: a NEW cut is made at the file's own size,
/// so 1:1 is the only fit that means anything there (user 2026-09-11:
/// 「넣을곳이 새 컷이면 맞춤 1:1외의 항목이 불필요해보임. 그러니 1:1로
/// 고정시켜서 노출시키도록. 비활성화된상태로」).
bool importFitLocked(ImportFileSettings settings, {required bool placing}) =>
    placing && settings.into == ImportDestination.newCut;

/// [settings] with every answer this file can actually give.
///
/// The window never has to remember which combinations are impossible: it
/// stores what the user pressed and asks here what that MEANS for this
/// file. A trimmed file set to Link comes back Keep, and the row says
/// Keep — the same answer the save would have reached anyway, arrived at
/// before the user is surprised by it.
ImportFileSettings resolvedImportSettings(
  ImportFileSettings settings, {
  required MediaAssetKind? kind,
  required bool isPsd,
  required bool placing,
  ImportLayerSpot? spot,
}) {
  final psd = importPsdLocked(spot) ? PsdPlaceMode.merge : settings.psd;
  final bake =
      importBakeAllowed(kind: kind, placing: placing) &&
      (settings.bake ||
          importBakeLocked(
            isPsd: isPsd,
            placing: placing,
            psd: psd,
            spot: spot,
          ));
  final mode = importModeAllowed(
    mode: settings.mode,
    trimmed: settings.isTrimmed,
  )
      ? settings.mode
      // Carrying is never refused, so a refused pointer lands there.
      : ImportFileMode.keepInside;
  final fit = importFitLocked(settings, placing: placing)
      ? MediaFitMode.none
      : settings.fit;
  return settings.copyWith(mode: mode, bake: bake, fit: fit, psd: psd);
}

/// The words the file table's cells show — the app's strings, so the window
/// speaks the language it is opened in.
String importModeLabel(ImportFileMode mode) => switch (mode) {
  ImportFileMode.reference => AppText.strings.imModeReference,
  ImportFileMode.keepInside => AppText.strings.imModeKeep,
};

/// ⛔ONE spelling of the fit, for the file table and the cut-folder column
/// alike. The column used to write its own ('Keep aspect') while the table
/// wrote 'Keep' — the very word the file column used for carrying.
String importFitLabel(MediaFitMode fit) => switch (fit) {
  MediaFitMode.stretch => AppText.strings.imFitStretch,
  MediaFitMode.contain => AppText.strings.imFitContain,
  MediaFitMode.none => '1:1',
};

/// 「새 레이어」 · 「새 컷」 — the pair the user named (2026-09-11: 「넣을곳 뉴
/// 컷에 맞춰서 레이어도 뉴 레이어가 맞을듯」).
String importIntoLabel(ImportDestination into) => switch (into) {
  ImportDestination.activeCutLayer => AppText.strings.imIntoNewLayer,
  ImportDestination.newCut => AppText.strings.imIntoNewCut,
};

String importPsdLabel(PsdPlaceMode mode) => switch (mode) {
  PsdPlaceMode.merge => AppText.strings.imPsdMerge,
  PsdPlaceMode.expand => AppText.strings.imPsdExpand,
};

String importBakeLabel(bool bake) =>
    bake ? AppText.strings.commonOn : AppText.strings.commonOff;
