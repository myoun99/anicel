part of 'cel_text_tool.dart';

/// THE WAY OUT OF THE HAND (R9-rest): the landing of every text the hand
/// lets go of — at once where what is on screen is what was wanted, and
/// once it is where the engine still owes its last want — and, for one let
/// go of to become drawing, its turning ([CelTextTool.turnIntoDrawing]).
///
/// The hand's own collaborator ([CelTextTool._wayOut]), in its library, as
/// the list is ([CelTextList]): what it lands is what the hand held, and
/// letting go is the hand's own field going empty.
///
/// ↩️These were the hand's own methods until 2026-10-07, when the turning
/// took its class over six hundred lines. They moved as they were.
class _CelTextWayOut {
  _CelTextWayOut(this._tool);

  final CelTextTool _tool;

  /// Texts let go of whose last want was still being set: shown until it
  /// is, landed then, and gone.
  final List<_Holding> leaving = [];

  /// Lands everything the hand holds AS IT IS SHOWN and keeps in hand what
  /// is in hand ([CelTextTool.landShown]). Whether anything landed.
  bool landShown() {
    var landed = false;
    for (final holding in [...leaving, ?_tool._held]) {
      landed = land(holding) || landed;
    }
    return landed;
  }

  /// Lands everything the hand holds AS IT IS SHOWN, and lets go of it all
  /// ([CelTextTool.landNow]).
  void landAll() {
    _tool._dropLetters();
    final held = _tool._held;
    _tool._held = null;
    // In the order they were let go of, the one in hand last — and each
    // out of [leaving] before it lands, as [_landOut] asks.
    if (held != null) {
      leaving.add(held);
    }
    while (leaving.isNotEmpty) {
      _landOut(leaving.removeAt(0));
    }
  }

  /// Lands the text in hand — now, or once its last want is set — and lets
  /// go of it where [thenLetGo] says so, or it has no letters left.
  void landHeld({required bool thenLetGo}) {
    final held = _tool._held;
    if (held == null) {
      return;
    }
    // A text with no letters is nothing to go on holding: landing takes it
    // off its cel ([CelTextSession.landing]).
    final letGo = thenLetGo || held.session.content.isEmpty;
    if (letGo) {
      _tool._held = null;
    }
    if (held.session.settled) {
      if (letGo) {
        _landOut(held);
      } else {
        land(held);
      }
      return;
    }
    // Its last want is still being set: it stays on screen until that is,
    // and lands then — a step holds a whole text.
    if (letGo) {
      leaving.add(held);
    }
    unawaited(_landOnceSettled(held));
  }

  Future<void> _landOnceSettled(_Holding held) async {
    await held.session.whenSettled();
    if (_tool._disposed) {
      return;
    }
    final stillHeld = identical(_tool._held, held);
    final owed = leaving.indexOf(held);
    if (!stillHeld && owed < 0) {
      // Landed already by [landNow], or deleted.
      return;
    }
    if (stillHeld && _tool._letters != null) {
      // The letters were taken up again before it settled: this visit goes
      // on, and lands when it ends.
      return;
    }
    if (owed >= 0) {
      leaving.removeAt(owed);
      _landOut(held);
    } else {
      land(held);
    }
    _tool._changed();
  }

  /// Lands [holding] — let go of, and out of [leaving] — as it is shown,
  /// turns it into its cel's drawing where it was let go of for that
  /// ([CelTextTool.turnIntoDrawing]), and is done with it.
  void _landOut(_Holding holding) {
    land(holding);
    if (holding.becomesDrawing) {
      _turnIntoDrawing(holding);
    }
    _tool._retire(holding.session);
  }

  /// Turns [holding]'s text — landed, so on its cel as it was shown — into
  /// the cel's drawing, as one step.
  ///
  /// That text and no other (유저 2026-10-07, `R9-rest-Q5`: 「고른 텍스트만
  /// 굳힌다」): whatever else the hand holds or still owes a landing — a text
  /// under this one too — is none of this step's, and lands in its own
  /// time as it would have.
  void _turnIntoDrawing(_Holding holding) {
    final _Holding(:session, :cel) = holding;
    final standing = session.standing;
    if (standing == null) {
      // No letters: its landing took it off the cel, or it never was on it.
      return;
    }
    _tool.host.run(
      CelTextEditCommand.intoDrawing(
        coordinator: cel.coordinator,
        frameKey: cel.key,
        id: standing.id,
        cacheInvalidationSink: cel.cacheInvalidationSink,
      ),
    );
  }

  /// Puts [holding]'s text on its cel as it is shown, as one step, and
  /// stands the session on what the cel then carries. Whether there was
  /// anything to put.
  bool land(_Holding holding) {
    final _Holding(:session, :cel) = holding;
    final command = session.landing(
      coordinator: cel.coordinator,
      cacheInvalidationSink: cel.cacheInvalidationSink,
    );
    if (command == null) {
      return false;
    }
    // The first landing of a text whose press made its cel takes the cel
    // with it; every later one is a step of its own.
    final celMadeSince = holding.celMadeSince;
    holding.celMadeSince = null;
    _tool.host.run(
      command,
      withCelMadeSince: celMadeSince,
      // What is shown is what lands ([CelTextSession.landing]) — and a
      // text with no letters is in no face.
      setIn: {
        for (final span in session.shown.content.spans) ?span.style.fontFamily,
      },
    );
    final id = command.textId;
    final texts = cel.coordinator.currentSurfaceOf(cel.key).texts;
    session.standOn(
      id == null ? null : texts.where((text) => text.id == id).firstOrNull,
    );
    return true;
  }
}
