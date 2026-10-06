import '../../core/collection_equality.dart';
import '../../models/bitmap_tile.dart';
import '../../models/brush_frame_key.dart';
import '../../models/cel_text.dart';
import '../../models/tile_coord.dart';
import '../brush_frame_editing_coordinator.dart';
import '../cache_invalidation_executor.dart';
import '../command.dart';
import '../undo_surface_snapshot.dart';
import 'cel_snapshot_step.dart';

/// ONE EDIT OF THE TEXTS A CEL CARRIES, as one undoable step (R9-rest, the
/// text tool): a text set on the cel — a new one, or one it already carries
/// set differently — or a text taken off it.
///
/// The text tool writes NOTHING while a text is being typed or dragged: it
/// shows the cel with the edit laid in, held by the panel, the way a move
/// shows its hole (`BrushLiftMoveHistoryCommand`). The first execute is the
/// first time the cel hears of it — and it is laid into the cel AS IT
/// STANDS THEN, texts alone, so anything drawn on the cel meanwhile stays.
///
/// A text is a value of the cel's picture (`BitmapSurface.texts`), so the
/// step is the picture before and after ([CelSnapshotStep]) and one Ctrl+Z
/// puts the letters, their settings and their pixels back together.
class CelTextEditCommand with CelSnapshotStep implements Command {
  /// Sets a text on [frameKey]'s cel: [content], with [plate] — the pixels
  /// it was baked to (`bakeCelTextPlate`).
  ///
  /// [id] names the text it replaces, which keeps its place among the
  /// others. Null is a NEW text: it goes on top (유저 2026-10-02: 그림 /
  /// 텍스트 / 텍스트 — the newest above) under an id minted when the step
  /// lands ([textId]).
  CelTextEditCommand.put({
    required this.coordinator,
    required this.frameKey,
    required CelTextContent content,
    required Map<TileCoord, BitmapTile> plate,
    int? id,
    this.cacheInvalidationSink,
    this.description = 'Set text',
  }) : _textId = id,
       _put = (content: content, plate: plate);

  /// Takes the text [id] off [frameKey]'s cel.
  CelTextEditCommand.remove({
    required this.coordinator,
    required this.frameKey,
    required int id,
    this.cacheInvalidationSink,
    this.description = 'Delete text',
  }) : _textId = id,
       _put = null;

  @override
  final BrushFrameEditingCoordinator coordinator;
  final BrushFrameKey frameKey;
  @override
  final CacheInvalidationSink? cacheInvalidationSink;

  @override
  final String description;

  /// The id the text wears on the cel — the one named, or for a new text
  /// the one minted when the step landed (null until then).
  int? get textId => _textId;
  int? _textId;

  /// What a `put` sets — held until the landing and no longer: the plate
  /// is pixels, and from then on the pair holds them where the budget can
  /// weigh and park them. Null for a `remove`.
  ({CelTextContent content, Map<TileCoord, BitmapTile> plate})? _put;

  /// Diagnostic for the accumulation guard, as
  /// `BrushStrokeHistoryCommand.retainsCommitPayload` is.
  bool get retainsPutPayload => _put != null;

  UndoSurfacePair? _surfaces;
  bool _landed = false;

  /// Null until the landing, and for an edit that changed nothing — a text
  /// set exactly as it was, or one taken off a cel that no longer has it.
  @override
  UndoSurfacePair? get surfaces => _surfaces;

  @override
  void execute() {
    if (_landed) {
      restoreAfter();
      return;
    }
    _landed = true;
    final before = coordinator.currentSurfaceOf(frameKey);
    final texts = _edited(before.texts);
    _put = null;
    if (listEquals(texts, before.texts)) {
      return;
    }
    coordinator.restoreSurfaceSnapshot(
      frameKey,
      before.withTexts(texts),
      cacheInvalidationSink: cacheInvalidationSink,
    );
    _surfaces = UndoSurfacePair(
      key: frameKey,
      before: before,
      after: coordinator.currentSurfaceOf(frameKey),
    );
  }

  /// [texts] as this edit leaves them.
  List<CelText> _edited(List<CelText> texts) {
    final put = _put;
    if (put == null) {
      return [
        for (final text in texts)
          if (text.id != _textId) text,
      ];
    }
    final id = _textId ??= nextCelTextId(texts);
    final set = CelText(id: id, content: put.content, plate: put.plate);
    return texts.any((text) => text.id == id)
        ? [
            for (final text in texts)
              if (text.id == id) set else text,
          ]
        : [...texts, set];
  }

  @override
  void undo() => restoreBefore();
}
