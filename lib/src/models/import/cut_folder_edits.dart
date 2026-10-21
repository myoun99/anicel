import '../layer_kind.dart';
import '../layer_mark.dart';
import '../media_asset.dart';
import 'cut_folder_parse.dart';

/// What the import window changed of a parsed cut folder before it comes
/// in — the cut's name, and each row's colour label, kind and fit, kept by
/// the row's key ([ParsedCelLayer.rowKey] · [ParsedPicture.rowKey]).
///
/// 🗣️F-429 (유저 2026-10-21): 「컷 이름 읽어오는 거 등 규칙에 맞춰서 입력은
/// 해두되 그거 사용자가 변경할수있게」 · 「기존 규칙 따라 자동적용되지만
/// 변경가능하게」. What the rules give is answered HERE, once: the window
/// shows it and the plan lands it from the same answer.
class CutFolderEdits {
  const CutFolderEdits({
    this.cutName,
    this.marks = const {},
    this.kinds = const {},
    this.fits = const {},
  });

  /// The name typed for the cut; null keeps the one the folder gives
  /// ([nameOf]).
  final String? cutName;
  final Map<String, LayerMark> marks;
  final Map<String, LayerKind> kinds;
  final Map<String, MediaFitMode> fits;

  /// The fit a row comes in with until someone picks another — the one the
  /// folder import always laid its scans with.
  static const MediaFitMode bornFit = MediaFitMode.contain;

  /// The cut's name: as typed, or the folder's cut number, or the folder's
  /// own name when it holds none.
  String nameOf(CutFolderParseResult parsed) =>
      cutName ?? parsed.cutNumber ?? parsed.folderName;

  /// [layer]'s colour label — the folder's stage and its letters'
  /// correction ([CutFolderParseResult.markOf]) until someone picks
  /// another.
  LayerMark markOfLayer(CutFolderParseResult parsed, ParsedCelLayer layer) =>
      marks[layer.rowKey] ?? parsed.markOf(layer);

  /// [layer]'s kind: an animation layer until someone picks another that
  /// can hold its cels ([holds]). A correction riding its symbol's own
  /// layer is that layer's kind, as an attach row made in the timeline is
  /// (`addAttachedLayer`).
  LayerKind kindOfLayer(CutFolderParseResult parsed, ParsedCelLayer layer) {
    final base = parsed.baseOf(layer);
    if (base != null) {
      return kindOfLayer(parsed, base);
    }
    final picked = kinds[layer.rowKey];
    return picked != null && holds(picked, layer.cells.length)
        ? picked
        : LayerKind.animation;
  }

  /// Whether a row of [cels] cels can come in as [kind]: an image layer
  /// holds ONE cel a cut by definition ([LayerKind.holdsSingleCel]).
  static bool holds(LayerKind kind, int cels) =>
      !kind.holdsSingleCel || cels == 1;

  /// [picture]'s kind. 🗣️F-429: 「1장짜리 그림을 기본 이미지레이어로
  /// 자동지정해두지만 같은창에서 애니메이션레이어로 변경가능」.
  LayerKind kindOfPicture(ParsedPicture picture) =>
      kinds[picture.rowKey] ?? LayerKind.image;

  /// [picture]'s colour label: what a new layer of its kind is born with,
  /// until someone picks another.
  LayerMark markOfPicture(ParsedPicture picture) =>
      marks[picture.rowKey] ?? LayerMark.bornOfKind(kindOfPicture(picture));

  /// The fit the row keyed [rowKey] is laid with.
  MediaFitMode fitOf(String rowKey) => fits[rowKey] ?? bornFit;

  /// These edits with the cut named [name] — null for the folder's own.
  CutFolderEdits withCutName(String? name) =>
      CutFolderEdits(cutName: name, marks: marks, kinds: kinds, fits: fits);

  CutFolderEdits copyWith({
    Map<String, LayerMark>? marks,
    Map<String, LayerKind>? kinds,
    Map<String, MediaFitMode>? fits,
  }) => CutFolderEdits(
    cutName: cutName,
    marks: marks ?? this.marks,
    kinds: kinds ?? this.kinds,
    fits: fits ?? this.fits,
  );
}
