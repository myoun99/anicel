/// WHAT A PRESS ON THE CANVAS IS — the buttons to believe, the mapping
/// they drive, whether the press pans and whether it draws — read before
/// anything acts on it.
///
/// 🗣️I-15 follow-up (유저 2026-09-11): 「스페이스바 하고 클릭하면 이거는
/// 드로잉로직이 아니라 프레임이 존재하지 않는다는 메시지 안뜨도록. 다른 툴도
/// 마찬가지로 옛날부터 있던건데, 브러시로 그리는 로직이 발생하는 상황이
/// 아닌데 프레임 존재하지 않는다는 메시지뜨니 … 근본적/구조적으로 해결」.
///
/// A press is read in an order: does the pan take it, does a mapped button
/// claim it, is the primary contact down — and only a press that gets past
/// all three draws. The gesture layer asks the first to pan, the drawing
/// view the other two to draw. The two places that ask for a block on an
/// EMPTY cel — the view standing down on it, and the shell's listener where
/// no view is built — each kept a copy of the last question alone, so a
/// press that pans, picks or undoes heard 「no frame here」 and, with the
/// auto-frame on, made a block nothing drew into. Both ask
/// [canvasPressDraws] now: the same three, in the same order.
library;

import 'package:flutter/gestures.dart';

import '../../models/app_input_settings.dart';
import '../../services/input/pen_sidecars.dart';
import 'canvas_pan_hold.dart';

/// The buttons to BELIEVE for [event].
///
/// A driver sidecar that speaks for this moment WINS — the same contract
/// the pen's pressure reading already follows, and for the same reason:
/// the OS path can be lying about what the pen just did.
///
/// The lie this catches: Windows Ink hands a Wacom barrel press to a
/// legacy window (Flutter never asks for WM_POINTER) as a PHANTOM PEN
/// TAP — kind stylus, pressure exactly 0.0, the PRIMARY button down,
/// on its own pointer id, while the pen is still hovering. Taken
/// literally that is a drawing contact, so the barrel never reached
/// its mapping AND the phantom opened a real stroke on top of it.
///
/// Note this is a truth source, not a fingerprint: nothing here
/// guesses from pressure being 0. A device with no pressure at all
/// reports 0 for every honest contact it ever makes, so reading the
/// zero as "must be a barrel press" would turn every stroke on such a
/// tablet into a button press.
int canvasPressButtons(PointerEvent event) =>
    PenSidecars.freshButtons() ?? event.buttons;

/// R28: whether the primary contact is down — a MASK test, not equality.
/// A barrel button held while the tip touches down reports
/// `primary | barrel`, and the old `== primary` test read that as "not
/// drawing" — so on a driver that does ride the barrel bit into contact,
/// the pen went dead instead of picking. The mapping is read FIRST and
/// claims those pointers, so a primary bit still down after it is a real
/// stroke.
bool canvasPrimaryDown(int buttons) => (buttons & kPrimaryButton) != 0;

/// Every bit of [buttons] that is NOT the primary contact (R27 #17 / R28);
/// zero when only the primary (or nothing) is down.
///
/// The mapping used to recognise EXACTLY `kSecondaryButton` and
/// `kTertiaryButton`. A stylus barrel that a driver reports on any other
/// bit — Windows Ink and the Wacom driver have several configurations —
/// then fell through every branch in silence, which is the shape of the
/// "와콤 펜은 우클릭버튼인거 확인했는데 툴이 아예 안 바뀜" report. Treating
/// any non-primary bit as the secondary mapping costs nothing (the
/// primary contact is the only one that draws) and stops the behaviour
/// depending on which bit a driver happens to pick.
int canvasMappedButtonBits(int buttons) => buttons & ~kPrimaryButton;

/// The canvas mapping (PEN-7a) a set of non-primary [bits] drives: the
/// wheel click owns the tertiary bit, and everything else reads as the
/// secondary — the barrel button, whichever bit the driver puts it on.
/// Null when none is down.
///
/// [penTailActive]: a live tail hold owns the tool. The two mappings share
/// one hold slot, and whichever engaged first keeps it. Letting a barrel
/// press take the tool mid-flip would leave the tail with nothing to
/// spring back to when the pen is finally turned upright.
CanvasPointerMapping? canvasMappingForButtons(
  int bits, {
  required bool penTailActive,
}) {
  if (bits == 0 || penTailActive) {
    return null;
  }
  final settings = AppInput.settings.value;
  if ((bits & kTertiaryButton) != 0) {
    return settings.canvasWheelClick;
  }
  return settings.canvasRightClick;
}

/// The canvas mapping row [event]'s buttons drive (PEN-7a); null = not a
/// mapped press (primary drawing input, or touch).
CanvasPointerMapping? canvasMappingFor(
  PointerEvent event, {
  required bool penTailActive,
}) {
  if (event.kind == PointerDeviceKind.touch) {
    return null;
  }
  return canvasMappingForButtons(
    canvasMappedButtonBits(canvasPressButtons(event)),
    penTailActive: penTailActive,
  );
}

/// Whether a press a mapped button claims for [action] still DRAWS: the
/// eraser hold's is a stroke — it follows with the erase settings — while
/// the pan, the pick, the history verbs and 「none」 eat the press.
bool canvasMappedActionDraws(CanvasPointerAction action) =>
    action == CanvasPointerAction.eraser;

/// Whether a press with [buttons] PANS the canvas: a pressed secondary bit
/// whose canvas mapping says pan (PEN-7a — the wheel/middle bit or the
/// right bit, when assigned), or the primary bit while the 「이동」 key is
/// held (I-15). The pen tip's contact bit rides along on stylus presses,
/// so the check is per bit, not equality.
bool canvasPressPans(int buttons) {
  if (CanvasPanHold.held.value && canvasPrimaryDown(buttons)) {
    return true;
  }
  final settings = AppInput.settings.value;
  if ((buttons & kTertiaryButton) != 0 &&
      settings.canvasWheelClick.action == CanvasPointerAction.pan) {
    return true;
  }
  if ((buttons & kSecondaryButton) != 0 &&
      settings.canvasRightClick.action == CanvasPointerAction.pan) {
    return true;
  }
  return false;
}

/// Whether [event] DRAWS with the armed tool — asked by an empty cel
/// before it asks the shell for a block, and answered with the readings
/// the press path makes, in its order, before anything acts.
///
/// A finger draws when its one-finger slot says draw (R27 #15: one that
/// flips, navigates or does nothing is not drawing — telling it 「no frame
/// here」 was noise on every page flip). Past that: a press the pan takes
/// draws nothing, a press a mapped button claims draws only when that
/// mapping does, and anything else draws with the primary contact down.
///
/// Whether the TOOL draws is not asked here: that is the shell's question
/// (`canvasToolMarksCel`), asked once for every press that reaches it.
bool canvasPressDraws(
  PointerDownEvent event, {
  required bool penTailActive,
}) {
  if (event.kind == PointerDeviceKind.touch) {
    return AppInput.touchDraws;
  }
  final buttons = canvasPressButtons(event);
  if (canvasPressPans(buttons)) {
    return false;
  }
  final mapping = canvasMappingFor(event, penTailActive: penTailActive);
  if (mapping != null) {
    return canvasMappedActionDraws(mapping.action);
  }
  return canvasPrimaryDown(buttons);
}
