import 'dart:collection';

import '../core/collection_equality.dart';
import 'exposure_instruction.dart';
import 'frame.dart' show writtenDrawingName;

/// Camera-work instruction vocabulary and events for instruction rows.
///
/// A [CameraInstructionDef] is one entry of the project's instruction
/// vocabulary — FI, FO, PAN, T.U … — pairing a display name with a symbolic
/// [iconKey] (the UI maps keys to actual icons; the model stays pure) and an
/// optional accent color. The default set seeds the standard 撮影 terms; the
/// user extends/edits it freely, which is the whole point of the registry.
///
/// An [InstructionEvent] is one span on an instruction row: it starts at its
/// map key on the layer, holds for [length] frames and can carry the sheet's
/// A → B endpoint values as free text (e.g. a PAN's start/end positions).
///
/// How a def's spans render on rows and sheets: [bar] is the paper sheet's
/// straight duration line (A ⊢───⊣ B — no arrowheads, user-confirmed), [fi]
/// the fade-in hatched wedge (full width at the span start narrowing to a
/// point — the screen starts covered and clears), [fo] its mirror and [ol]
/// the translucent bowtie the sheets draw for O.L / cross-dissolve spans.
/// Lives on the def (not the event) so a term always looks the same and
/// external formats (TDTS) can map it per term.
///
/// [wi] and [wo] are W.I and W.O: the fade wedges again, clearing from and
/// closing to a WHITE screen where [fi] and [fo] use a black one. 🗣️F-192
/// (유저 2026-09-27): 「컷의 페이드인은 애초에 쌩 검은화면에서 바뀐단거였음.
/// 화이트인은 쌩 흰화면에서 바뀌는거고」 — so the screen is part of what the
/// term IS, and the mark is where the term says what it is
/// (`transitionScreenColorOf`).
enum CameraInstructionMarkType {
  bar('bar'),
  fi('fi'),
  fo('fo'),
  wi('wi'),
  wo('wo'),
  ol('ol');

  const CameraInstructionMarkType(this.jsonValue);

  final String jsonValue;

  String toJson() => jsonValue;

  /// Unknown or absent values decode to [bar] so files stay open-able
  /// across versions.
  static CameraInstructionMarkType fromJson(Object? json) {
    for (final value in values) {
      if (value.jsonValue == json) {
        return value;
      }
    }
    return bar;
  }
}

/// Whether [def] belongs on the TRANSITION row rather than a cut's own
/// direction row — the 場面転換 terms: F.I, F.O, W.I, W.O and O.L.
///
/// These are the instructions that replace the WHOLE screen rather than
/// move the camera inside it, and that line is what decides which row of
/// the camera section a term may be dropped on.
///
/// ⚠️ Implemented as "carries a non-bar mark" because today the two sets
/// coincide exactly — the wedge/bowtie glyphs are worn by precisely those
/// five. They are different questions though (the mark says how a span is
/// PAINTED, this says what it MEANS), so if a term ever wants a wedge
/// without being a transition, or the reverse, this grows a stored flag on
/// the def instead of reading [CameraInstructionDef.markType].
bool cameraInstructionIsTransition(CameraInstructionDef def) =>
    def.markType != CameraInstructionMarkType.bar;

class CameraInstructionDef {
  const CameraInstructionDef({
    required this.id,
    required this.name,
    required this.iconKey,
    this.colorValue,
    this.markType = CameraInstructionMarkType.bar,
  });

  /// Stable id events reference; never renamed (the [name] is the label).
  final String id;

  /// The sheet label — 'FI', 'PAN', a custom term.
  final String name;

  /// Symbolic icon key resolved by the UI's curated palette; unknown keys
  /// fall back to a generic glyph so files stay open-able across versions.
  final String iconKey;

  /// Optional accent (ARGB), null = theme default.
  final int? colorValue;

  /// How this term's spans render; [CameraInstructionMarkType.bar] unless
  /// the def opts into the O.L bowtie.
  final CameraInstructionMarkType markType;

  CameraInstructionDef copyWith({
    String? name,
    String? iconKey,
    int? Function()? colorValue,
    CameraInstructionMarkType? markType,
  }) {
    return CameraInstructionDef(
      id: id,
      name: name ?? this.name,
      iconKey: iconKey ?? this.iconKey,
      colorValue: colorValue == null ? this.colorValue : colorValue(),
      markType: markType ?? this.markType,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'iconKey': iconKey,
    if (colorValue != null) 'color': colorValue,
    if (markType != CameraInstructionMarkType.bar)
      'markType': markType.toJson(),
  };

  factory CameraInstructionDef.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    return CameraInstructionDef(
      id: id,
      name: json['name'] as String,
      iconKey: json['iconKey'] as String,
      colorValue: json['color'] as int?,
      markType: _theWhiteWedgeOf(
        id,
        CameraInstructionMarkType.fromJson(json['markType']),
      ),
    );
  }

  /// F-192: the standard W.I and W.O were stored wearing the BLACK wedges
  /// ([CameraInstructionMarkType.fi]/[CameraInstructionMarkType.fo]) until
  /// they had marks of their own, and a vocabulary is stored with the
  /// project — so a file from before reads its W terms as the white ones
  /// they always meant.
  static CameraInstructionMarkType _theWhiteWedgeOf(
    String id,
    CameraInstructionMarkType stored,
  ) => switch ((id, stored)) {
    ('wi', CameraInstructionMarkType.fi) => CameraInstructionMarkType.wi,
    ('wo', CameraInstructionMarkType.fo) => CameraInstructionMarkType.wo,
    _ => stored,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraInstructionDef &&
          other.id == id &&
          other.name == name &&
          other.iconKey == iconKey &&
          other.colorValue == colorValue &&
          other.markType == markType;

  @override
  int get hashCode => Object.hash(id, name, iconKey, colorValue, markType);

  @override
  String toString() =>
      'CameraInstructionDef(id: $id, name: $name, iconKey: $iconKey, '
      'color: $colorValue, markType: $markType)';
}

/// The project-level instruction vocabulary, in display order.
class CameraInstructionSet {
  CameraInstructionSet({required List<CameraInstructionDef> defs})
    : defs = List.unmodifiable(defs) {
    final ids = <String>{};
    for (final def in this.defs) {
      if (!ids.add(def.id)) {
        throw ArgumentError.value(
          def.id,
          'defs',
          'Instruction ids must be unique.',
        );
      }
    }
  }

  final List<CameraInstructionDef> defs;

  /// Every term of this vocabulary, by id.
  CameraInstructionDef? defById(String id) {
    for (final def in defs) {
      if (def.id == id) {
        return def;
      }
    }
    return null;
  }

  /// The first `custom-<n>` id none of [defs] holds — how a term the user
  /// adds is named, and how a term arriving from another project (I-7) is
  /// renamed when this vocabulary already spells that id differently.
  String freeCustomId() {
    final used = {for (final def in defs) def.id};
    var index = 1;
    while (used.contains('custom-$index')) {
      index += 1;
    }
    return 'custom-$index';
  }

  /// The standard 撮影 vocabulary (撮ま! chapters): camera work, transitions
  /// and filter effects. Projects without a stored set open with this.
  static final CameraInstructionSet standard = CameraInstructionSet(
    defs: const [
      // Camera work.
      CameraInstructionDef(id: 'fix', name: 'FIX', iconKey: 'fix'),
      CameraInstructionDef(id: 'pan', name: 'PAN', iconKey: 'pan'),
      CameraInstructionDef(id: 'pan-up', name: 'PAN UP', iconKey: 'pan-up'),
      CameraInstructionDef(
        id: 'pan-down',
        name: 'PAN DOWN',
        iconKey: 'pan-down',
      ),
      CameraInstructionDef(id: 'sl', name: 'SL', iconKey: 'slide'),
      CameraInstructionDef(id: 'follow', name: 'Follow', iconKey: 'follow'),
      CameraInstructionDef(id: 'tu', name: 'T.U', iconKey: 'track-up'),
      CameraInstructionDef(id: 'tb', name: 'T.B', iconKey: 'track-back'),
      CameraInstructionDef(id: 'qtu', name: 'Q T.U', iconKey: 'track-up'),
      CameraInstructionDef(id: 'qtb', name: 'Q T.B', iconKey: 'track-back'),
      // 🗣️I-89 (유저 2026-10-10): 「회전은 모아트기준대로」 — the turn's
      // own word, which a camera move names (`cameraMoves`).
      CameraInstructionDef(id: 'rotate', name: '回転', iconKey: 'rotate'),
      // Transitions. Fades seed the sheet's wedge marks: the wedge is wide
      // where the screen is covered (FI/WI clear it, FO/WO close it).
      CameraInstructionDef(
        id: 'fi',
        name: 'FI',
        iconKey: 'fade-in',
        markType: CameraInstructionMarkType.fi,
      ),
      CameraInstructionDef(
        id: 'fo',
        name: 'FO',
        iconKey: 'fade-out',
        markType: CameraInstructionMarkType.fo,
      ),
      CameraInstructionDef(
        id: 'wi',
        name: 'WI',
        iconKey: 'white-in',
        markType: CameraInstructionMarkType.wi,
      ),
      CameraInstructionDef(
        id: 'wo',
        name: 'WO',
        iconKey: 'white-out',
        markType: CameraInstructionMarkType.wo,
      ),
      CameraInstructionDef(
        id: 'ol',
        name: 'O.L',
        iconKey: 'overlap',
        markType: CameraInstructionMarkType.ol,
      ),
      CameraInstructionDef(id: 'wipe', name: 'WIPE', iconKey: 'wipe'),
      // Filter effects.
      CameraInstructionDef(id: 'si', name: 'S.I', iconKey: 'super-impose'),
      CameraInstructionDef(id: 'df', name: 'DF', iconKey: 'diffusion'),
      CameraInstructionDef(id: 'fog', name: 'FOG', iconKey: 'fog'),
    ],
  );

  Map<String, dynamic> toJson() => {
    'defs': defs.map((def) => def.toJson()).toList(),
  };

  factory CameraInstructionSet.fromJson(Map<String, dynamic> json) {
    return CameraInstructionSet(
      defs: (json['defs'] as List<dynamic>)
          .map(
            (def) => CameraInstructionDef.fromJson(def as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraInstructionSet && listEquals(other.defs, defs);

  @override
  int get hashCode => Object.hashAll(defs);

  @override
  String toString() => 'CameraInstructionSet(defs: $defs)';
}

/// One span on an instruction row; keyed by its start frame on the layer.
///
/// On a DIRECTION row it is read off a block ([of]) rather than stored: the
/// block holds the [writing] and answers the length (R27 —
/// [ExposureInstruction] says why).
class InstructionEvent {
  const InstructionEvent({
    required this.instructionId,
    required this.length,
    this.text,
    this.valueA,
    this.valueB,
  });

  /// The span [writing] makes on a block [length] frames long — a block that
  /// says nothing is a span of nothing.
  InstructionEvent.of(ExposureInstruction? writing, {required this.length})
    : instructionId = writing?.instructionId,
      text = writing?.text,
      valueA = writing?.valueA,
      valueB = writing?.valueB;

  /// What this span says, without the length a block answers — null when it
  /// says nothing, so a block holds no writing of nothing beside none.
  ExposureInstruction? get writing =>
      instructionId == null && text == null && valueA == null && valueB == null
      ? null
      : ExposureInstruction(
          instructionId: instructionId,
          text: text,
          valueA: valueA,
          valueB: valueB,
        );

  /// References a [CameraInstructionDef.id]; a dangling reference (its def
  /// was deleted) renders with the fallback glyph and the raw id.
  ///
  /// 🗣️Null is a span with NO mark — 「(없음)」 (I-72-block-without-
  /// instruction, 유저 2026-10-05: 「디렉션 블록 지시(기호) 없는상태
  /// 존재가능하도록. 없으면 아무 표시도 안함. se블록에 아무것도 없는 상태랑
  /// 똑같음」 · 10-08: 「(없음) 이런식? 그리고 생성시 기본값 없음」): no glyph,
  /// no line, no term name; what the span still writes ([text], [valueA],
  /// [valueB]) shows as it does beside a mark. ⛔Not a dangling id: that one
  /// still draws the fallback ([markIn]).
  final String? instructionId;

  /// Covered frames — [start, start + length).
  final int length;

  /// Free per-event text (the mark and the writing are independent, like on
  /// paper): when set it is what displays and prints; the vocabulary name is
  /// only the fallback.
  final String? text;

  /// The sheet's A → B endpoint values, free text ('A', '1.5倍', …).
  final String? valueA;
  final String? valueB;

  /// What displays/prints for this event given its vocabulary [def] — with
  /// no mark and no text, nothing.
  String displayLabel(CameraInstructionDef? def) =>
      labelOfWriting(writing, def);

  /// The vocabulary entry this span's mark names in [defById] — null with no
  /// mark, as with a dangling one or no vocabulary at hand.
  CameraInstructionDef? defIn(
    CameraInstructionDef? Function(String instructionId)? defById,
  ) => switch ((instructionId, defById)) {
    (final id?, final find?) => find(id),
    _ => null,
  };

  /// The mark this span draws: its entry's, the plain line for a dangling
  /// mark, and NONE without one — the one place that tells the two apart.
  CameraInstructionMarkType? markIn(
    CameraInstructionDef? Function(String instructionId)? defById,
  ) => instructionId == null
      ? null
      : defIn(defById)?.markType ?? CameraInstructionMarkType.bar;

  InstructionEvent copyWith({
    String? instructionId,
    int? length,
    String? Function()? text,
    String? Function()? valueA,
    String? Function()? valueB,
  }) {
    return InstructionEvent(
      instructionId: instructionId ?? this.instructionId,
      length: length ?? this.length,
      text: text == null ? this.text : text(),
      valueA: valueA == null ? this.valueA : valueA(),
      valueB: valueB == null ? this.valueB : valueB(),
    );
  }

  /// The [writing]'s keys with the length beside them — one spelling of the
  /// keys, shared with a block's ([ExposureInstruction.toJson]).
  Map<String, dynamic> toJson() {
    final json = writing?.toJson() ?? {};
    return {
      'instructionId': ?json.remove('instructionId'),
      'length': length,
      ...json,
    };
  }

  factory InstructionEvent.fromJson(Map<String, dynamic> json) =>
      InstructionEvent.of(
        ExposureInstruction.fromJson(json),
        length: json['length'] as int,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InstructionEvent &&
          other.instructionId == instructionId &&
          other.length == length &&
          other.text == text &&
          other.valueA == valueA &&
          other.valueB == valueB;

  @override
  int get hashCode => Object.hash(instructionId, length, text, valueA, valueB);

  @override
  String toString() =>
      'InstructionEvent(instructionId: $instructionId, length: $length, '
      'text: $text, valueA: $valueA, valueB: $valueB)';
}

/// Validates an instruction map: non-negative starts, positive lengths and
/// no overlapping spans (simultaneous instructions belong on additional
/// direction rows, like the sheet's DIR 1 · DIR 2 columns).
void validateInstructionCoverage(
  SplayTreeMap<int, InstructionEvent> instructions,
) {
  int? previousEndExclusive;
  for (final entry in instructions.entries) {
    if (entry.key < 0) {
      throw ArgumentError.value(
        entry.key,
        'instructions',
        'Instruction start frames must be non-negative.',
      );
    }
    if (entry.value.length < 1) {
      throw ArgumentError.value(
        entry.value.length,
        'instructions',
        'Instruction lengths must be at least 1.',
      );
    }
    if (previousEndExclusive != null && entry.key < previousEndExclusive) {
      throw ArgumentError.value(
        entry.key,
        'instructions',
        'Instruction spans must not overlap.',
      );
    }
    previousEndExclusive = entry.key + entry.value.length;
  }
}

/// Immutable sorted copy of [instructions], validated.
SplayTreeMap<int, InstructionEvent> immutableInstructionMap(
  Map<int, InstructionEvent> instructions,
) {
  final result = SplayTreeMap<int, InstructionEvent>.of(instructions);
  validateInstructionCoverage(result);
  return result;
}

/// Decodes the layer JSON list form: `[{index, instructionId, length, …}]`.
SplayTreeMap<int, InstructionEvent> instructionMapFromJson(Object? json) {
  final result = SplayTreeMap<int, InstructionEvent>();
  if (json == null) {
    return result;
  }
  for (final item in json as List<dynamic>) {
    final map = item as Map<String, dynamic>;
    result[map['index'] as int] = InstructionEvent.fromJson(map);
  }
  validateInstructionCoverage(result);
  return result;
}

List<Map<String, dynamic>> instructionMapToJson(
  Map<int, InstructionEvent> instructions,
) {
  return [
    for (final entry in instructions.entries)
      {'index': entry.key, ...entry.value.toJson()},
  ];
}
/// What a term is written as: its [def]'s name in the vocabulary, or the
/// raw [id] where the vocabulary has none (a term since deleted) — an
/// instruction span's fallback ([labelOfWriting]) and the
/// camera's moves' only name (I-73 ⑤).
String instructionTermName(String id, CameraInstructionDef? def) =>
    def?.name ?? id;

/// What [writing] says, given its mark's [def]: its own words, else its
/// mark's term name — nothing with neither.
String labelOfWriting(ExposureInstruction? writing, CameraInstructionDef? def) {
  final text = writing?.text;
  if (text != null && text.isNotEmpty) {
    return text;
  }
  return switch (writing?.instructionId) {
    final id? => instructionTermName(id, def),
    null => '',
  };
}

/// The name a direction block's drawing LINKS by: the two ends [writing]
/// names and what it says ([labelOfWriting]), written
/// ([writtenDrawingName]) — so blocks saying the same show one drawing, as
/// two blocks of one name do on a drawing row. Null when it names neither
/// end: the drawing is its own, whatever the block says.
///
/// 🗣️I-72-direction-link (유저 2026-10-08): 「같은이름이라는 규칙을
/// 시작이름,끝이름,지시 세개 같으면 같은 링크로서 작동하도록 … 이름이 비우면
/// 기호이름이란 시스템이잖아? 그거의 결과를 지시 라는 항목으로」, and Q1's
/// note (10-25): 「독립붙여넣기나 복제는 프레임블록은 링크발동안되게 이름
/// 없음으로 태어나니 디렉션도 시작이름 끝이름만 없음으로 태어나게」 — the
/// ends are the name, and a block without them links to none.
String? linkNameOfWriting(
  ExposureInstruction? writing,
  CameraInstructionDef? def,
) {
  final from = writing?.valueA?.trim() ?? '';
  final to = writing?.valueB?.trim() ?? '';
  if (from.isEmpty && to.isEmpty) {
    return null;
  }
  return writtenDrawingName([from, to, labelOfWriting(writing, def).trim()]);
}
