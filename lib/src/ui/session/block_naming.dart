import '../../models/attached_layer_resolve.dart' show isSyncedAttachedLayer;
import '../../models/layer.dart';

/// Whether [layer]'s drawings are what 자동 이름 지정 numbers (I-18): its
/// kind's answer ([LayerKind.numbersItsDrawings]), on a row whose drawings
/// carry names of their own.
///
/// ⛔A SYNCED attach row's do not. Its cels are mirrors whose name follows
/// the base's — the row PRINTS its base's names (UI-R24 #2) — so numbering
/// the base is what numbers what the mirror shows, and a number of the
/// mirror's own would be written where nothing reads it.
bool rowNumbersItsDrawings(Layer layer) =>
    layer.kind.numbersItsDrawings && !isSyncedAttachedLayer(layer);
