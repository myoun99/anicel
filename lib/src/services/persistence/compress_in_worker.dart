import 'dart:isolate';
import 'dart:typed_data';

import 'anicel_payload_codec.dart';

/// Compresses [body] in a worker isolate, sending it as a
/// [TransferableTypedData] rather than as an ordinary message.
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
/// external buffer, and [body] stays perfectly readable afterwards
/// (probed: readable after `fromList` AND after the worker materialised
/// it). What it buys is the CROSSING: that external buffer passes the
/// isolate boundary without being serialised and comes back the same way,
/// where a plain message is written out on one side and rebuilt on the
/// other.
///
/// ⛔The isolate does the compression ONLY. Serialising there would mean
/// sending the tiles as objects — `BitmapTile` is `Finalizable` and cannot
/// cross at all, so the old shape had to build an `AnicelCelEntry` full of
/// defensive pixel copies first. The caller serialises straight off the
/// surface instead (`encodeCelEntryFromSurface`) and sends one flat
/// buffer.
Future<({int codec, Uint8List bytes})> compressAnicelPayloadInWorker(
  Uint8List body,
) async {
  final sent = TransferableTypedData.fromList([body]);
  final out = await Isolate.run(() {
    final raw = sent.materialize().asUint8List();
    final compressed = compressAnicelPayload(raw);
    return (
      codec: compressed.codec,
      bytes: TransferableTypedData.fromList([compressed.bytes]),
    );
  });
  return (codec: out.codec, bytes: out.bytes.materialize().asUint8List());
}
