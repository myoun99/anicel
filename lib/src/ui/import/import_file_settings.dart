import '../../models/media_asset.dart';
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
/// The kind decides no answer about keeping: it was a ceiling until
/// 2026-08-14 and a default until 2026-09-16, and now every file starts
/// where the settings start and can be kept or linked at any size — the
/// decisions are on [seedImportSettings].
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
    this.sound = true,
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

  /// Whether a MOVIE brings its sound onto the SE rows (the 「소리」
  /// column, 라운드 6) — asked only of a movie that has one
  /// ([importSoundAllowed]).
  final bool sound;

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
    bool? sound,
  }) => ImportFileSettings(
    mode: mode ?? this.mode,
    bake: bake ?? this.bake,
    into: into ?? this.into,
    fit: fit ?? this.fit,
    psd: psd ?? this.psd,
    inFrame: inFrame ?? this.inFrame,
    outFrame: clearOut ? null : (outFrame ?? this.outFrame),
    sound: sound ?? this.sound,
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
      other.outFrame == outFrame &&
      other.sound == sound;

  @override
  int get hashCode =>
      Object.hash(mode, bake, into, fit, psd, inFrame, outFrame, sound);
}

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

/// Whether [mode] may be answered. Every kind may be carried, at any size
/// ([seedImportSettings] has the decisions).
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
/// something is placed, and only of what has pictures. Sound has none; a
/// movie does, and for a movie the answer is whether it stays a reference
/// (「참조 여부 = 배치 창의 굽기 열」, 라운드 6).
bool importBakeAllowed({required MediaAssetKind? kind, required bool placing}) =>
    placing &&
    (kind == MediaAssetKind.image ||
        kind == MediaAssetKind.pdf ||
        kind == MediaAssetKind.video);

/// Whether the 「소리」 question is asked: of a MOVIE being placed, and only
/// one that has a sound (라운드 6 확인: 「소리열: 추천대로」 — 소리가 있는
/// 동영상 행에만).
bool importSoundAllowed({
  required MediaAssetKind? kind,
  required bool placing,
  required bool hasSound,
}) => placing && kind == MediaAssetKind.video && hasSound;

/// Whether the 「소리」 answer is the PLACE's: a movie let go on an SE row's
/// empty cell IS its sound (「SE 행 드롭은 켬으로 잠김」).
bool importSoundLocked(ImportLayerSpot? spot) => spot is SeCellSpot;

/// What a row answers before anyone has answered for it — the settings' own
/// starting answers, and its PLACE's: a movie dropped on a picture row's
/// frames starts without its sound, which can be turned on (「프레임 영역
/// 드롭은 끔(켤 수 있음)」).
///
/// 🚨THE KIND HAS NO SAY in how a file is kept, and neither has its size:
/// every file starts on Keep inside, the settings' own default (유저
/// 2026-09-16: 「파일 크기 어떻든 품기/참조가능으로 바꿨으니 기본값이든
/// 경고줄이든 싹 다 삭제 잔존제거」). How it got here, so nobody re-derives
/// the old rules:
///  * 2026-08-13 — Blender's rule as a CEILING (user decision): images and
///    sounds pack, video does not; a reference movie can be three gigabytes,
///    while a sound the project does not carry goes missing the first time
///    someone moves a folder.
///  * 2026-08-14 — a DEFAULT only (user decision, same round as the video
///    decoder): *"비디오도 그냥 유저가 선택하게 하면 좋을거같은데. 참조만
///    강요하는게아니라."* A movie someone deliberately wanted inside the
///    file had been refused by a rule that could not hear them. What the
///    ceiling protected against moved into a 100 MB size warning in the
///    import window — a WARNING and never a refusal (user direction: their
///    file, their disk).
///  * 2026-09-16 — the movie default and the size warning both went, by the
///    answer above.
ImportFileSettings seedImportSettings({ImportLayerSpot? spot}) =>
    ImportFileSettings(sound: spot is! RowFramesSpot);

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
  required bool hasActiveCut,
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
  // The destination the settings hold is ONE answer: the drop's, when it
  // answered the cut (a row it was let go on is in the active cut, whatever
  // was pressed before); a new cut when there is no cut to put a layer in
  // (유저 2026-09-12: 「액티브 컷이 없는 상태에서 캔버스 떨구면 새 컷
  // 고정」); else what the row was answered.
  final into =
      spot?.answeredDestination ??
      (hasActiveCut ? settings.into : ImportDestination.newCut);
  final fit = importFitLocked(settings.copyWith(into: into), placing: placing)
      ? MediaFitMode.none
      : settings.fit;
  return settings.copyWith(
    mode: mode,
    bake: bake,
    into: into,
    fit: fit,
    psd: psd,
    sound: importSoundLocked(spot) || settings.sound,
  );
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

String importOnOffLabel(bool on) =>
    on ? AppText.strings.commonOn : AppText.strings.commonOff;
