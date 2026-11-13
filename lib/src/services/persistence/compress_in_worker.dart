import 'dart:isolate';
import 'dart:typed_data';

import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import 'anicel_payload_codec.dart';
import 'brush_drawing_binary_codec.dart';

/// [key]'s stream of the hot cel [surface], serialised and compressed on a
/// worker ([onAWorkerWithCelStream]) and handed back as a
/// [TransferableTypedData] rather than as an ordinary message: what a
/// cooling and an undo snapshot's park write.
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
Future<({int codec, Uint8List bytes})> compressCelOnAWorker(
  BrushFrameKey key,
  BitmapSurface surface,
) async {
  final out = await onAWorkerWithCelStream(key, surface, _compressedToCross);
  return (codec: out.codec, bytes: out.bytes.materialize().asUint8List());
}

({int codec, TransferableTypedData bytes}) _compressedToCross(
  Uint8List stream,
) {
  final compressed = compressAnicelPayload(stream);
  return (
    codec: compressed.codec,
    bytes: TransferableTypedData.fromList([compressed.bytes]),
  );
}
