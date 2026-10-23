/// The bytes a hand-built QuickTime movie is made of — one copy for every
/// helper that writes one (`pcmMovie`, `mpeg4VisualMovie`).
library;

/// A box: its size, its type, its body.
List<int> box(String type, List<int> body) =>
    [...u32(8 + body.length), ...tag(type), ...body];

/// A handler reference box of [type] for [subtype], with an empty name.
List<int> handlerBox(String type, String subtype) => box('hdlr', [
      ...u32(0),
      ...tag(type),
      ...tag(subtype),
      ...u32(0), ...u32(0), ...u32(0), // manufacturer, flags, mask
      0, // an empty name
    ]);

List<int> tag(String fourCharacters) => fourCharacters.codeUnits;

List<int> u64(int value) => [...u32(value >> 32), ...u32(value)];

List<int> u32(int value) => [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];

List<int> u16(int value) => [(value >> 8) & 0xFF, value & 0xFF];
