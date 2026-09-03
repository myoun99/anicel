import 'dart:ui';

/// The program accent (UI-R22 #5).
///
/// One highlight, used sparingly: selection, playhead, active toggles — the
/// historical teal. It is customizable and persisted.
///
/// There used to be a second accent here, the automatic complement of the
/// first, for "states that must read differently from plain selection". It
/// had exactly one production consumer (the selection-repeat pattern span)
/// and the second purpose its docs promised — the selected key-union
/// diamonds — was never wired, so the app carried a persisted, translated,
/// user-facing setting that told half a truth. The span now says what it is
/// with a dashed edge, which is a better sign than a hue nobody could name.
class AppAccentSettings {
  const AppAccentSettings({this.accent = defaultAccent});

  /// The historical program teal.
  static const Color defaultAccent = Color(0xFF4FA8A0);

  final Color accent;

  /// 🪦**색 라벨의 톤과 글자 굵기가 여기 있었다. 둘 다 골랐고, 끝났다.**
  ///
  /// 실기에서 고르려고 설정에 낸 값들이었다(유저 2026-08-28: 「설정에 그냥
  /// 넣어줄수있어? 보면서 확인하게」). 답이 나왔으므로 상수로 굳히고 칸을
  /// 걷었다 — 「색도 크림으로 정했으니까 나머지 유물 없애도되」.
  ///
  /// - **톤 = 크림.** 색은 [resolveLayerMarkColor] 가 갖는다.
  /// - **굵기 = w400.** 유저: 「일단 정했어. 얇은거. 400으로 가고싶어」.
  ///   🧪실기 실측(유저): **100~500 은 얇고, 600~800 은 굵고, 900 은 엄청
  ///   굵다** — 번들 폰트에 Regular 와 Bold 뿐이라 두 단계일 것이라던 내
  ///   예측은 틀렸다. 900 에서 Skia 가 **합성 볼드**를 얹는다.
  ///
  /// 🪦그리고 그 전에 **2치화**가 있었다. 들어온 이유는 「색라벨 텍스트 뭔가
  /// 좀 읽기힘든데 … **쌩2치화** 된 텍스트로 할수있나?」였고, 그때 앱은 OS 가
  /// 주는 아무 폰트를 쓰고 있었다. ⛔**AA 를 끄는 API 는 없다** —
  /// `Paint()..isAntiAlias = false` 를 물려도 출력이 픽셀 단위로 동일했다
  /// (직접 재봤다). 방법은 그려진 뒤 알파를 계단으로 만드는 것뿐이었다.
  /// 나간 이유는 폰트가 **BIZ UDPGothic** 으로 바뀌어 원인이 치워졌고,
  /// 반대로 계단이 획을 먹었기 때문이다 — 판이 14px 에 두 열이라 한 열이
  /// 7px, 거기 눌러 넣은 세로획이 1px 아래로 내려가면 알파가 경계를 못 넘어
  /// **획째로 사라졌다**(「글자가 1px같은게 사라졌어」). 판마다 있던
  /// `saveLayer` 도 함께 사라졌다.
  AppAccentSettings copyWith({Color? accent}) =>
      AppAccentSettings(accent: accent ?? this.accent);

  Map<String, dynamic> toJson() => {'accent': accent.toARGB32()};

  /// A stored `accent2` from an older build is simply not read: the key stays
  /// on disk and is dropped on the next save, and nothing crashes. The same
  /// goes for the label keys the rounds above wrote and retired.
  static AppAccentSettings fromJson(Map<String, dynamic> json) =>
      AppAccentSettings(
        accent: Color(json['accent'] as int? ?? defaultAccent.toARGB32()),
      );

  @override
  bool operator ==(Object other) =>
      other is AppAccentSettings && other.accent == accent;

  @override
  int get hashCode => accent.hashCode;
}
