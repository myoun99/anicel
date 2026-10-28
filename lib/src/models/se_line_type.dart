import '../core/collection_equality.dart' show mapEquals;
import 'cut_id.dart';

/// An SE block's DELIVERY (I-20): the speaker on screen, off it, or inside
/// their own head.
///
/// 🗣️유저 2026-09-30 (I-20): 「se 블록의 타입으로서 on off mono 타입 추가.
/// 업계용언데 on은 화면에서 캐릭터가 말할때. off는 화면밖의 캐릭터 대사,
/// mono는 속마음 대사」 · I-20-Q1: 「타입이 없는 상태는 존재하지않음.
/// 기본값은 ON」 — so there is no "none", and a block that never chose is ON.
enum SeLineType {
  on('ON'),
  off('OFF'),
  mono('MONO');

  const SeLineType(this.label);

  /// What every surface prints — the trade's own words, in every language.
  final String label;

  /// Whether it is written out where ON goes without saying — the
  /// timesheet over the name, the conte sheet's dialogue column and an SE
  /// block's name on the timeline, the X-sheet and the conte panel.
  ///
  /// 🗣️유저 (I-20-Q2 덧말): 「ON일때는 타임시트 이름위랑 콘티용지에는
  /// 표시하지않음. 캔버스에는 표시. 즉 OFF거나 MONO일때만 타임시트/콘티에
  /// 표시」. ONE answer for every such place; the canvas prints every type.
  /// 🗣️F-496 (유저 2026-10-28): 「타임라인패널도 … 동일하게 ON은
  /// 표시안하고 OFF랑 MONO도 se블록에 표시」.
  bool get writtenOut => this != SeLineType.on;

  /// Read back from a file; anything unknown — and an absent field — is ON,
  /// the delivery a block that never chose has.
  static SeLineType fromJson(Object? value) => values.firstWhere(
    (type) => type.name == value,
    orElse: () => SeLineType.on,
  );
}

/// An SE block's delivery in each cut it plays in (F-386).
///
/// 🗣️유저 2026-10-17 (F-386): 「se트랙은 글로벌이기에 여러 컷에 걸칠수있음.
/// 그래서 컷마다 같은 대사를 이어가고있는데 어떤 컷에선 ON이지만 다음컷에선
/// OFF일수도있음. 그러니 타입 정하는곳에서 컷을 팝오버로 골라서 컷마다 타입
/// 다르게 선택할수있도록 … 블록 움직이던 어떻게하던 그런상황 어떻게할지는
/// 알아서」 — whether the speaker is on screen is the CUT's picture's to say,
/// so a delivery belongs to the block in a cut.
///
/// [own] is what every cut without an answer of its own reads — the one the
/// cut the block's head plays in has ([shownIn]), so a block moved or
/// stretched into a new cut carries on as it began. [byCut] holds only the
/// cuts that differ from it. A move never rewrites a delivery: a cut the
/// block left keeps its answer and gives it back when the block returns,
/// and only the SE window writes them again, as it showed them.
final class SeLineTypes {
  factory SeLineTypes({
    SeLineType own = SeLineType.on,
    Map<CutId, SeLineType> byCut = const {},
  }) => SeLineTypes._(
    own,
    Map.unmodifiable({
      for (final MapEntry(:key, :value) in byCut.entries)
        if (value != own) key: value,
    }),
  );

  const SeLineTypes._(this.own, this.byCut);

  /// A block that never chose: ON in every cut (I-20-Q1).
  static const allOn = SeLineTypes._(SeLineType.on, {});

  final SeLineType own;
  final Map<CutId, SeLineType> byCut;

  /// The delivery in [cutId]; [own] for a cut with no answer of its own —
  /// and for null, a block that plays in no cut.
  SeLineType inCut(CutId? cutId) => byCut[cutId] ?? own;

  /// [type] in [cutId] — in null, the block's [own].
  SeLineTypes withCut(CutId? cutId, SeLineType type) => cutId == null
      ? SeLineTypes(own: type, byCut: byCut)
      : SeLineTypes(own: own, byCut: {...byCut, cutId: type});

  /// The deliveries as the SE window shows them, for the cuts the block
  /// plays in, head first: the head's is the block's [own], and an answer
  /// for a cut the window did not show is let go. A block that plays in no
  /// cut keeps what it has.
  SeLineTypes shownIn(List<CutId> cuts) => cuts.isEmpty
      ? this
      : SeLineTypes(
          own: inCut(cuts.first),
          byCut: {for (final cut in cuts) cut: inCut(cut)},
        );

  /// The fields a drawing writes — none for a block that is ON everywhere,
  /// the absent fields every drawing reads back as.
  Map<String, Object> toJson() => {
    if (own != SeLineType.on) 'seType': own.name,
    if (byCut.isNotEmpty)
      'seTypeByCut': {
        for (final MapEntry(:key, :value) in byCut.entries)
          key.value: value.name,
      },
  };

  static SeLineTypes fromJson(Map<String, dynamic> json) {
    final byCut = json['seTypeByCut'] as Map<String, dynamic>? ?? const {};
    return SeLineTypes(
      own: SeLineType.fromJson(json['seType']),
      byCut: {
        for (final MapEntry(:key, :value) in byCut.entries)
          CutId(key): SeLineType.fromJson(value),
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SeLineTypes &&
          other.own == own &&
          mapEquals(other.byCut, byCut);

  @override
  int get hashCode => Object.hash(
    own,
    Object.hashAllUnordered([
      for (final MapEntry(:key, :value) in byCut.entries)
        Object.hash(key, value),
    ]),
  );

  @override
  String toString() => 'SeLineTypes(${own.name}, $byCut)';
}

/// An SE block's own fields besides its dialogue — the speaker's name and
/// the delivery in each cut — written together with the dialogue, as one
/// edit.
typedef SeEntryFields = ({String? seName, SeLineTypes seTypes});
