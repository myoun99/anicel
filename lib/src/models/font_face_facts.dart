/// WHAT A FONT FILE SAYS OF ITSELF — the little of it this app reads: the
/// family it belongs to, which of the family's faces it is, and what its
/// maker wrote about putting it inside documents (R9-rest, the text tool's
/// faces).
class FontFaceFacts {
  const FontFaceFacts({
    required this.family,
    required this.weight,
    required this.italic,
    required this.fsType,
  });

  factory FontFaceFacts.fromJson(Map<String, dynamic> json) => FontFaceFacts(
    family: json['family'] as String,
    weight: json['weight'] as int,
    italic: json['italic'] as bool,
    fsType: json['fsType'] as int?,
  );

  /// The family's name as the file gives it (its English one, where it has
  /// one) — what a letter's style is written with
  /// (`TextLetterStyle.fontFamily`), so the same word on every machine that
  /// reads the same file.
  final String family;

  /// The face's weight class, 1–1000: 400 is a regular, 700 a bold.
  final int weight;
  final bool italic;

  /// The maker's word on embedding — the `fsType` of the file's OS/2 table —
  /// or null when the file carries no such table and so says nothing.
  final int? fsType;

  /// Whether the file may ride INSIDE A DOCUMENT THAT IS STILL EDITED, which
  /// is what a project is.
  ///
  /// 🗣️유저 2026-10-06 (R9-rest-Q1, of three answers — put every imported
  /// font in the project / refuse the ones that forbid it / keep those on
  /// this device alone): 「그럼 a로 가자. 폰트별로 그런게 있는건 처음알았네.
  /// 프로들이 하는 방식대로하자고」 — a font whose maker forbids it is
  /// registered on this device and never written into a project.
  ///
  /// The font format's own rule (OpenType, OS/2 `fsType`): the low four bits
  /// are the licence — none set is INSTALLABLE, 8 is EDITABLE, 4 is preview
  /// and print only (a document nobody edits), 2 is restricted — and where a
  /// file sets several, the least restrictive holds. 0x0200 allows bitmaps
  /// of the font alone, which a project that carries the file would not be.
  ///
  /// ⚠️The lowest bit is RESERVED in that format, and a file that sets it
  /// alone (this machine's `TTSNOTE.TTF` says 1) has said something the
  /// format gives no meaning to. It is read as no permission, not as none
  /// needed.
  ///
  /// ⚠️A file with NO OS/2 table gives no permission, and is read as having
  /// given none (measured 2026-10-06 on this machine's 414 font files: every
  /// one carried the table, so this is a rule for files nobody has shown
  /// yet — it errs towards the maker).
  bool get ridesInEditedDocuments {
    final said = fsType;
    if (said == null || said & _bitmapsOnly != 0) {
      return false;
    }
    final licence = said & _licenceBits;
    return licence == 0 || licence & _editable != 0;
  }

  static const int _licenceBits = 0x000F;
  static const int _editable = 0x0008;
  static const int _bitmapsOnly = 0x0200;

  /// Whether [other] is this face of this family — the same seat in it, so
  /// a file of it brought again takes the place of the one that was there.
  bool isSameFaceAs(FontFaceFacts other) =>
      family == other.family &&
      weight == other.weight &&
      italic == other.italic;

  Map<String, dynamic> toJson() => {
    'family': family,
    'weight': weight,
    'italic': italic,
    'fsType': fsType,
  };

  @override
  bool operator ==(Object other) =>
      other is FontFaceFacts &&
      isSameFaceAs(other) &&
      fsType == other.fsType;

  @override
  int get hashCode => Object.hash(family, weight, italic, fsType);

  @override
  String toString() =>
      'FontFaceFacts($family, $weight${italic ? ' italic' : ''}, '
      'fsType: $fsType)';
}
