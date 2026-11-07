import '../core/collection_equality.dart';
import 'attached_layer_resolve.dart';
import 'folder_band_rows.dart';
import 'layer.dart';

/// The first frame at which a row drawn from [a] and a row drawn from [b]
/// may show different cells — null when they show the same cells
/// everywhere.
///
/// 🚨F-244 (유저 2026-09-30: 「타임라인 블록 관련 조작이 너무 느림 … 무거운
/// 컷일수록 심해짐」): a comma drag makes a new layer at every step, and the
/// timeline's tiles, keyed on the instance, baked the whole visible row
/// again — and its attach mirror's — for an edit that moved the blocks from
/// one edge on. This is where the two instances can first disagree, so what
/// lies before it can stay.
///
/// Why every cell before the answer is drawn alike from either layer:
/// * everything but the timeline agrees ([Layer.sameBesideTimeline]) — else
///   the answer is 0. The row's folds are not asked: no cell reads them
///   ([Layer.foldsLike]);
/// * timeline entries cannot overlap, so the entries before the first key
///   the two timelines part at cover every frame before that key alike —
///   and neither of them can reach past it;
/// * a cell reads its two neighbours, and the one AT that key cannot hold
///   the block before it in either layer (that block ends by the key), so
///   the cell before it still reads «the block ends here» in both;
/// * a block's word walks its room only within its block, and the blocks
///   before the key end by it;
/// * a SYNCED attach mirror prints its BASE's cel names, so the bases' cels
///   must agree too ([attachedDisplayBaseOf]);
/// * a FOLDER's band paints what its rows hold, grey where none holds a
///   picture at that frame (R28 #11), so its rows must hold alike too
///   ([firstCellTheBandRowsMayDiffer]). ↩️Its own timeline alone was asked,
///   and a row's block that ended elsewhere inside the folder's kept the
///   tile painted before (F-561 ②, 서피스 실기 2026-11-07).
///
/// ⚠️What a row reads from outside its layer is not in here — the cels'
/// pixels (their own revision) and the camera row's track (its cells are
/// not its timeline's). A reader asks this beside those, never instead.
int? firstCellThatMayDiffer(Layer a, Layer b) {
  if (identical(a, b)) {
    return null;
  }
  if (!a.sameBesideTimeline(b) || !_sameCelNames(a, b)) {
    return 0;
  }
  return _earlier(
    _firstKeyTheTimelinesPartAt(a, b),
    firstCellTheBandRowsMayDiffer(
      folderBandRowsOf(a) ?? const [],
      folderBandRowsOf(b) ?? const [],
    ),
  );
}

/// The first key at which the timelines of [a] and [b] part — null when
/// they are alike.
int? _firstKeyTheTimelinesPartAt(Layer a, Layer b) {
  final left = a.timeline.entries.iterator;
  final right = b.timeline.entries.iterator;
  while (true) {
    final hasLeft = left.moveNext();
    final hasRight = right.moveNext();
    if (!hasLeft || !hasRight) {
      return hasLeft
          ? left.current.key
          : hasRight
          ? right.current.key
          : null;
    }
    final (l, r) = (left.current, right.current);
    if (l.key != r.key) {
      return l.key < r.key ? l.key : r.key;
    }
    if (l.value != r.value) {
      return l.key;
    }
  }
}

/// Where a FOLDER's band drawn from the rows [a] and one drawn from the rows
/// [b] may first paint apart — null where they hold alike.
///
/// A band reads two things of its rows. Their timelines: its blocks and
/// ghosts are made of them (`folderBandOf`), and its grey asks which cel
/// each stands at a frame (R28 #11). And their kinds: the grey asks first
/// whether a row holds cels at all (`celHasContentForLayer`). The cels'
/// pixels are a fact of their own (the tint revision). So a row changed
/// beside those — its eye, an opacity drag — moves no cell of the band, and
/// the band made for it stays (`FolderBands`).
int? firstCellTheBandRowsMayDiffer(List<Layer> a, List<Layer> b) {
  if (a.length != b.length) {
    return 0;
  }
  int? first;
  for (var i = 0; i < a.length; i += 1) {
    final (was, now) = (a[i], b[i]);
    if (was.id != now.id || was.kind != now.kind) {
      return 0;
    }
    first = _earlier(first, _firstKeyTheTimelinesPartAt(was, now));
  }
  return first;
}

/// The earlier of two frames, either of which may be none.
int? _earlier(int? a, int? b) => a == null ? b : (b == null || a <= b ? a : b);

/// Whether both rows print the same cel names: a mirror's come from the
/// cels of the base it mirrors, every other row's from its own frames
/// (which [Layer.sameBesideTimeline] already compared).
bool _sameCelNames(Layer a, Layer b) {
  final baseOfA = attachedDisplayBaseOf(a);
  final baseOfB = attachedDisplayBaseOf(b);
  return identical(baseOfA, baseOfB) ||
      baseOfA != null &&
          baseOfB != null &&
          listEquals(baseOfA.frames, baseOfB.frames);
}
