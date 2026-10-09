import 'dart:typed_data';

/// [m4a]'s AAC frames, each behind an ADTS header — the same sound as a bare
/// `.aac` stream, which has no box to say where its sound starts.
///
/// Reads the first sound track: its AudioSpecificConfig (profile, rate,
/// channels) out of `esds`, and its frames out of `stsz` · `stsc` · `stco`.
Uint8List adtsFromM4a(Uint8List m4a) {
  final view = ByteData.sublistView(m4a);
  ({int body, int end})? find(int start, int end, String type) {
    var at = start;
    while (at + 8 <= end) {
      final size = view.getUint32(at);
      if (size < 8 || at + size > end) {
        return null;
      }
      if (String.fromCharCodes(m4a, at + 4, at + 8) == type) {
        return (body: at + 8, end: at + size);
      }
      at += size;
    }
    return null;
  }

  ({int body, int end}) path(List<String> types) {
    var box = (body: 0, end: m4a.length);
    for (final type in types) {
      box = find(box.body, box.end, type) ??
          (throw StateError('no $type in the m4a'));
    }
    return box;
  }

  const table = ['moov', 'trak', 'mdia', 'minf', 'stbl'];
  // The entries follow the version and the count; a sound entry's own
  // fields are 28 bytes, and `esds` is the box after them.
  final stsd = path([...table, 'stsd']);
  final mp4a = find(stsd.body + 8, stsd.end, 'mp4a')!;
  final esds = find(mp4a.body + 28, mp4a.end, 'esds')!;
  // Past the version: the ES descriptor (3) holds the decoder config (4),
  // which holds the decoder-specific info (5) — whose first two bytes are
  // the AudioSpecificConfig this needs.
  var at = esds.body + 4;
  void enter(int tag) {
    if (m4a[at] != tag) {
      throw StateError('esds: descriptor $tag expected, ${m4a[at]} found');
    }
    at += 1;
    while (m4a[at] & 0x80 != 0) {
      at += 1; // the descriptor's length, in 7-bit bytes
    }
    at += 1;
  }

  enter(3);
  final flags = m4a[at + 2];
  at += 3; // ES_ID, flags
  if (flags & 0x80 != 0) at += 2; // depends on another stream
  if (flags & 0x40 != 0) at += 1 + m4a[at]; // a URL
  if (flags & 0x20 != 0) at += 2; // an OCR stream
  enter(4);
  at += 13; // object type, stream type, buffer size, max and mean bit rate
  enter(5);
  final objectType = m4a[at] >> 3;
  final rateIndex = ((m4a[at] & 0x07) << 1) | (m4a[at + 1] >> 7);
  final channels = (m4a[at + 1] >> 3) & 0x0F;

  final stsz = path([...table, 'stsz']);
  final fixedSize = view.getUint32(stsz.body + 4);
  final count = view.getUint32(stsz.body + 8);
  int sizeOf(int sample) =>
      fixedSize != 0 ? fixedSize : view.getUint32(stsz.body + 12 + sample * 4);
  final stsc = path([...table, 'stsc']);
  final runs = view.getUint32(stsc.body + 4);
  final stco = path([...table, 'stco']);
  final chunks = view.getUint32(stco.body + 4);

  final out = BytesBuilder();
  var sample = 0;
  for (var chunk = 0; chunk < chunks; chunk += 1) {
    // How many samples this chunk holds: the last run that starts at or
    // before it.
    var perChunk = 0;
    for (var run = 0; run < runs; run += 1) {
      if (view.getUint32(stsc.body + 8 + run * 12) - 1 <= chunk) {
        perChunk = view.getUint32(stsc.body + 8 + run * 12 + 4);
      }
    }
    var offset = view.getUint32(stco.body + 8 + chunk * 4);
    for (var index = 0; index < perChunk && sample < count; index += 1) {
      final size = sizeOf(sample);
      final length = size + 7;
      out.add([
        0xFF,
        0xF1, // MPEG-4, layer 00, no CRC
        ((objectType - 1) << 6) | (rateIndex << 2) | (channels >> 2),
        ((channels & 0x03) << 6) | (length >> 11),
        (length >> 3) & 0xFF,
        ((length & 0x07) << 5) | 0x1F, // buffer fullness 0x7FF ...
        0xFC, // ... and one raw block
      ]);
      out.add(Uint8List.sublistView(m4a, offset, offset + size));
      offset += size;
      sample += 1;
    }
  }
  return out.toBytes();
}
