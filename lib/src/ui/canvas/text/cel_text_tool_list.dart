part of 'cel_text_tool.dart';

/// One text of the cel under the tool, as the settings LIST it: which one
/// it is — null for the one in hand that is not on its cel yet — what it
/// says now, and whether it is the one in hand.
typedef CelTextListed = ({int? id, String text, bool inHand});

/// THE TEXTS OF THE CEL UNDER THE HAND, AS THE SETTINGS LIST THEM (R9-rest).
///
/// 🗣️유저 2026-10-06: 「도구설정에 선택된 텍스트라는 항목이 있었으면 좋겠음.
/// 거기서 다른 텍스트 선택할수있게 리스트 고르는. 팝오버로 리스트
/// 고를수있게하고. 텍스트의 이름은 그냥 텍스트 글자대로. 그리고 옆에
/// 삭제버튼 있고」.
///
/// The hand's own collaborator ([CelTextTool.list]), in its library: what
/// it lists is what the hand holds and what the cel under it carries, and
/// picking or deleting from it is the hand taking hold or letting go.
class CelTextList {
  CelTextList._(this._tool);

  final CelTextTool _tool;

  /// The text the hand holds on [cel], if it holds one there.
  CelTextSession? _inHandOn(CelTextCel cel) {
    final held = _tool._held?.session;
    return held != null && held.key == cel.key ? held : null;
  }

  /// The texts, from the top of the stack down (유저 2026-10-02: 「새로운
  /// 텍스트일수록 위에 쌓임」), each by the letters it says now: the one in
  /// hand by what is typed into it, landed or not.
  List<CelTextListed> get texts {
    final cel = _tool.host.cel;
    if (cel == null) {
      return const [];
    }
    final inHand = _inHandOn(cel);
    final typed = inHand == null ? null : _tool._contentInHand(inHand);
    return [
      // A text that is not on its cel yet will be the topmost when it is.
      if (inHand != null && inHand.standing == null && !typed!.isEmpty)
        (id: null, text: typed.text, inHand: true),
      for (final text in _inReach(cel).reversed)
        if (inHand != null && text.id == inHand.textId)
          (id: text.id, text: typed!.text, inHand: true)
        else
          (id: text.id, text: text.content.text, inHand: false),
    ];
  }

  /// Takes the listed text [id] in hand, by its box — what picking it in
  /// the list does. Whatever else was in hand lands first; the one already
  /// in hand stays, its letters let go of ([CelTextTool.takeText]).
  void take(int? id) {
    final cel = _tool.host.cel;
    if (cel == null) {
      return;
    }
    if (_holds(cel, id)) {
      _tool.stopTyping();
      return;
    }
    final text = _inReach(cel).where((text) => text.id == id).firstOrNull;
    if (text != null) {
      _tool.takeText(cel, text);
    }
  }

  /// Takes the listed text [id] off its cel — one step — what its delete in
  /// the list does. The one in hand is let go of ([CelTextTool.deleteText]);
  /// another goes beside whatever is in hand, which stays.
  void delete(int? id) {
    final cel = _tool.host.cel;
    if (cel == null) {
      return;
    }
    if (_holds(cel, id)) {
      _tool.deleteText();
    } else if (id != null) {
      _takeOff(cel, id);
    }
  }

  /// The texts of [cel] the tool can reach now, bottom to top
  /// ([celTextsInReach]).
  static List<CelText> _inReach(CelTextCel cel) =>
      celTextsInReach(cel.coordinator.currentSurfaceOf(cel.key)).toList();

  /// Whether the listed text [id] of [cel] is the one in hand — a new text
  /// that is not on its cel yet is listed with no id, and has none.
  bool _holds(CelTextCel cel, int? id) {
    final inHand = _inHandOn(cel);
    return inHand != null && inHand.textId == id;
  }

  /// Takes the text [id], which is not in hand, off [cel].
  void _takeOff(CelTextCel cel, int id) {
    // A text let go of that still owed a landing does not come back with
    // it: what it owed goes with the text.
    _tool._leaving.removeWhere((leaving) {
      final gone =
          leaving.session.key == cel.key && leaving.session.textId == id;
      if (gone) {
        _tool._retire(leaving.session);
      }
      return gone;
    });
    _tool.host.run(
      CelTextEditCommand.remove(
        coordinator: cel.coordinator,
        frameKey: cel.key,
        id: id,
        cacheInvalidationSink: cel.cacheInvalidationSink,
      ),
    );
    _tool._changed();
  }
}
