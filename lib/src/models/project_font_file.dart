import 'font_face_facts.dart';

/// ONE FONT FILE A PROJECT CARRIES (R9-rest, the text tool's faces): what
/// the file said of itself when it was registered, and the name its bytes
/// are kept under inside the project file.
///
/// 🗣️유저 2026-10-06, of whether a font the project carries should leave it
/// when no text is written in it any more: 「뺄때까지 두는게 맞지않나
/// 싶은데. 글꼴을 사실상 등록하는거잖아. 프리미어프로처럼」 — a font is
/// REGISTERED with a project, and stays until a person takes it out. So the
/// list of them is the project's own (`Project.fonts`), changed by a
/// person's edit and by nothing else.
///
/// ⚠️Only a font that may ride in a document that is edited is ever one of
/// these ([FontFaceFacts.ridesInEditedDocuments], R9-rest-Q1 ⓐ) — whoever
/// registers asks; this is the record, and records whatever it is handed.
class ProjectFontFile {
  const ProjectFontFile({required this.carriedAs, required this.facts});

  factory ProjectFontFile.fromJson(Map<String, dynamic> json) =>
      ProjectFontFile(
        carriedAs: json['carriedAs'] as String,
        facts: FontFaceFacts.fromJson(json),
      );

  /// The name the file's bytes are stored under in the project file, after
  /// the fonts' own prefix — minted when the font was registered
  /// (`mintMediaCarry`), as a carried medium's is: a name means ONE set of
  /// bytes for good, so the same family registered again as other bytes is
  /// kept under another.
  final String carriedAs;

  /// The family the file is a face of, which face, and its maker's word on
  /// embedding — as the file said when it was registered.
  final FontFaceFacts facts;

  Map<String, dynamic> toJson() => {'carriedAs': carriedAs, ...facts.toJson()};

  @override
  bool operator ==(Object other) =>
      other is ProjectFontFile &&
      carriedAs == other.carriedAs &&
      facts == other.facts;

  @override
  int get hashCode => Object.hash(carriedAs, facts);

  @override
  String toString() => 'ProjectFontFile($carriedAs, $facts)';
}
