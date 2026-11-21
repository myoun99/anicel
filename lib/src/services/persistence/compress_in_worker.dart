import 'dart:isolate';
import 'dart:typed_data';

import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import 'brush_drawing_binary_codec.dart';

/// [key]'s blob of the hot cel [surface] — its stream serialised and
/// pressed on a worker ([onAWorkerWithCelStream], [AnicelCelBlob.ofPayload])
/// — handed back as a [TransferableTypedData] rather than as an ordinary
/// message: what a cooling's park, an undo snapshot's park and a save
/// write ([blobPressedOnAWorker] where the blob is wanted here).
///
/// 🚨**PRESSED ON THE WORKER, FOR THE SAVE TOO** (card
/// incremental-save-holds-every-dirty-cel-at-once, 2026-11-21). The save
/// handed each edited cel across as its stream unpressed and pressed it
/// in its isolate — after it held every edited cel's work at once, the
/// stream as large as the cel's tiles. 🔬An imported copy's 220 cels
/// (7751×4396 line art, m.tvpp) made edited and saved onto the same file
/// raised the process 2.0–2.3 GiB over the save (main PC, two runs).
/// Pressed here, what a save holds of them is their size in the file.
/// ↩️The parks made the compressed body here and the blob around it on
/// their own side, its head handed in from the surface; the save's road
/// made it the third, and one.
///
/// 🧪**MEASURED, 2026-09-10** — one park, end to end:
/// | payload | plain message | transferable |
/// |---|---|---|
/// | 64 KB | 3.84 ms | **1.94** |
/// | 256 KB | 9.05 ms | **8.06** |
/// | 1 MB | 20.56 ms | **14.60** |
/// | 4 MB | 48.65 ms | **26.52** |
///
/// ⚠️**AND THE REASON IS NOT THE ONE THE NAME SUGGESTS.** I wrote "the
/// buffer MOVES, the caller cannot read it after" here first, and it is
/// false — `TransferableTypedData.fromList` COPIES its lists into one
/// external buffer, and the list it was given stays perfectly readable
/// afterwards (probed: readable after `fromList` AND after the worker
/// materialised it). What it buys is the CROSSING: that external buffer
/// passes the isolate boundary without being serialised and comes back the
/// same way, where a plain message is written out on one side and rebuilt
/// on the other.
///
/// ↩️⛔「The isolate does the compression ONLY. Serialising there would
/// mean sending the tiles as objects — `BitmapTile` is `Finalizable` and
/// cannot cross at all, so the old shape had to build an `AnicelCelEntry`
/// full of defensive pixel copies first.」 True of a tile's object, not of
/// its bytes: a worker is handed those a batch at a time now
/// ([onAWorkerWithCelCopy]) and serialises a copy of its own, the save's
/// road — and this isolate holds a batch where it held the whole stream
/// (card `the-cooling-serialises-each-hot-cel-on-the-ui-isolate`,
/// 2026-11-13).
Future<TransferableTypedData> pressedBlobOnAWorker(
  BrushFrameKey key,
  BitmapSurface surface,
) => onAWorkerWithCelStream(
  key,
  surface,
  _pressedToCross(surface.showsSomething),
);

/// [pressedBlobOnAWorker]'s blob, here.
Future<AnicelCelBlob> blobPressedOnAWorker(
  BrushFrameKey key,
  BitmapSurface surface,
) async => AnicelCelBlob(
  (await pressedBlobOnAWorker(key, surface)).materialize().asUint8List(),
);

/// ⚠️Made HERE, of a bool alone, so the closure crosses with nothing of the
/// surface ([onAWorkerWithCelStream]). Whether the picture shows anything
/// rides in: the blob's head says it, and the stream holds no copy of it
/// ([AnicelCelBlob.ofPayload]).
TransferableTypedData Function(Uint8List stream) _pressedToCross(
  bool showsSomething,
) => (stream) => TransferableTypedData.fromList([
  AnicelCelBlob.ofPayload(stream, showsSomething: showsSomething).bytes,
]);
