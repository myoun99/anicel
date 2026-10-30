import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show
        DeviceGestureSettings,
        PointerDeviceKind,
        computeHitSlop,
        kPrimaryButton,
        kPrimaryStylusButton,
        kSecondaryStylusButton;

import '../../native/qa_pen_ledger.dart';
import 'pen_lean.dart';
import 'pencil_interaction_service.dart';
import 'platform_pen_channel_service.dart';
import 'raw_pen_input_service.dart';
import 'wintab_pen_service.dart';

/// The pen program's sidecar FACADE (PEN-4): one question — "does a
/// driver-side stream know the pen's pressure right now?" — answered
/// across every platform's sidecar:
///
/// - Windows: the Wintab service (user-switched, PEN-2). Consulted
///   FIRST and unconditionally (it self-gates on its setting).
/// - macOS: the platform channel service (PEN-4), started unconditionally
///   there by [bind] — it only restores data the embedder drops today.
/// - Linux: none. ↩️It had a channel too, from a GTK hook in the runner, until
///   the embedder carried the pen itself (3.47, flutter/flutter#186831: a
///   stylus's kind and its 0..1 pressure on the pointer event). A pressure on
///   its own event cannot arrive late; the channel's could, and stood over it
///   for 150ms (mac-linux-pen-sidecar-opening).
///
/// The brush canvas asks [freshReading] per pointer sample; the
/// input inspector lists [channelServices] readouts beside the Wintab
/// line.
abstract final class PenSidecars {
  static final List<PlatformPenChannelService> channelServices =
      <PlatformPenChannelService>[];

  static bool _bound = false;

  /// One-time wiring from main(); FLUTTER_TEST-inert by construction
  /// (tests never call it — they drive services directly).
  static void bind() {
    if (_bound) {
      return;
    }
    _bound = true;
    WintabPenService.instance.bind();
    RawPenInputService.instance.bind();
    PencilInteractionService.instance.bind();
    // The per-event record comes first where the platform keeps one (H43);
    // started here so the very first stroke is on it.
    QaPenLedger.start();
    if (Platform.isMacOS) {
      channelServices.add(PlatformPenChannelService.macos()..start());
    }
  }

  /// The freshest driver-side pressure READING across every live sidecar,
  /// and whether the pen was TOUCHING when it was taken; null = no sidecar
  /// speaks for this moment (use the pointer event's own pressure).
  ///
  /// ⚠️TOUCHING IS THE DRIVER'S WORD, not the pointer's. At the pen's down
  /// the newest Wintab packet can still be one from the hover just before
  /// it (pressure 0, tip up): a reading of the pen, but not of this
  /// contact (H43). The tip bit says so outright; pressure above zero
  /// answers the same for a driver that leaves the bit clear — and is the
  /// only answer the channel sidecars have, which carry no buttons.
  static ({double pressure, bool touching})? freshReading() {
    final packet = WintabPenService.instance.freshPacket();
    if (packet != null) {
      return _reading(packet.pressure, tip: packet.buttons & _wintabTip != 0);
    }
    for (final service in channelServices) {
      final pressure = service.freshContactPressure();
      if (pressure != null) {
        return _reading(pressure, tip: false);
      }
    }
    return null;
  }

  static ({double pressure, bool touching}) _reading(
    double pressure, {
    required bool tip,
  }) => (pressure: pressure.clamp(0.0, 1.0), touching: tip || pressure > 0);

  /// Whether a driver-side stream says the PEN is touching right now — its
  /// tip switch ([freshButtons]) or a reading that touches ([freshReading])
  /// — whatever kind the pointer event calls itself.
  ///
  /// 🗣️THE PEN LAW (tool-settings-panel-tidy, 유저 2026-10-10): 「필압이
  /// 있다도 하나의 판단기준일거같은데 … 윈탭골라도 필압은 먹히니까
  /// 감지가능하단거아냐」 → 「우선 1번 제일 확실한방법 좋아. 앞으로의 펜 작동
  /// 기준으로 삼으면 좋을거같고」. A pen the OS hands over as a MOUSE (Wintab
  /// chosen, Windows Ink off) is still the pen while its driver says it is
  /// down. ⛔Not the pointer event's own pressure: a pen handed over as a
  /// mouse carries none.
  static bool penTouching() {
    final buttons = freshButtons();
    if (buttons != null && buttons & kPrimaryButton != 0) {
      return true;
    }
    return freshReading()?.touching ?? false;
  }

  /// [kind] as the pen law reads it ([penTouching]): a MOUSE while its
  /// driver says the pen is down is the pen. Every answer the app gives by
  /// the kind of a pointer — how far a press may wobble and stay a press
  /// (`computeHitSlop`), whether a pen is near — asks it through this.
  static PointerDeviceKind kindOf(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.mouse && penTouching()
      ? PointerDeviceKind.stylus
      : kind;

  /// How far a press of [kind] may wobble and stay a press — Flutter's
  /// slop for the pen law's kind ([kindOf]). I-124: four recognisers each
  /// wrote this out.
  static double hitSlopOf(
    PointerDeviceKind kind,
    DeviceGestureSettings? settings,
  ) => computeHitSlop(kindOf(kind), settings);

  /// Whether [kind] is either end of a pen — of whichever kind the caller
  /// holds. I-124: three places spelled the two ends out.
  static bool isPenKind(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;

  /// How the pen leans as the freshest driver-side stream says — null when
  /// none speaks for this moment or the one that does reports no lean (a
  /// pen without a tilt sensor). Windows only: the lean Flutter's embedder
  /// drops (desktop-pen-tilt).
  ///
  /// Raw Input first, as for buttons: HID declares the tilt with its own
  /// unit and reach. Wintab's orientation is the driver's own account, and
  /// the one left when the HID report has none.
  ///
  /// ⚠️A hovering pen's lean is still its lean — unlike pressure, whose
  /// hover packet reads 0 (see [freshReading]) — so a fresh report answers
  /// whether or not the tip is down.
  static PenLean? freshLean({DateTime? now}) {
    final tilt = RawPenInputService.instance.freshTilt(now: now);
    if (tilt != null) {
      return penLeanFromPlaneTilt(x: tilt.x, y: tilt.y);
    }
    final orientation = WintabPenService.instance
        .freshPacket(now: now)
        ?.orientation;
    if (orientation != null) {
      return penLeanFromWintab(
        bearing: orientation.bearing,
        altitude: orientation.altitude,
      );
    }
    return null;
  }

  /// How far the pen is turned about its own barrel as the freshest
  /// driver-side stream says, in degrees 0..360 clockwise — null when none
  /// speaks for this moment or the device declares no twist. Windows only
  /// (F-176-Q9): Flutter's embedder reads POINTER_PEN_INFO's rotation and
  /// leaves it off the pointer event.
  ///
  /// Raw Input first, as for the lean; both speak clockwise degrees.
  static double? freshTwist({DateTime? now}) {
    final twist =
        RawPenInputService.instance.freshTwist(now: now) ??
        WintabPenService.instance.freshPacket(now: now)?.twistDegrees;
    return twist == null ? null : twist % 360.0;
  }

  /// The freshest driver-side BUTTON state, as FLUTTER button bits; null =
  /// no sidecar speaks for this moment (use the pointer event's own).
  ///
  /// Only Wintab answers: the macOS channel sidecar restores pressure the
  /// embedder drops, not buttons.
  ///
  /// Wintab's bits are positional per cursor — bit 0 is the TIP, bit 1 the
  /// lower barrel switch, bit 2 the upper one — and Flutter spells the
  /// same three as primary / primary-stylus / secondary-stylus. The
  /// translation is written out rather than passed through because the
  /// numeric agreement between the two is a coincidence, not a contract.
  static int? freshButtons({DateTime? now}) {
    // Raw Input first: HID states each switch outright, where Wintab's
    // button word is a positional convention we have to translate.
    final raw = RawPenInputService.instance.freshButtons(now: now);
    if (raw != null) {
      return raw;
    }
    final wintab = WintabPenService.instance.freshButtons(now: now);
    if (wintab == null) {
      return null;
    }
    var bits = 0;
    if (wintab & _wintabTip != 0) {
      bits |= kPrimaryButton;
    }
    if (wintab & _wintabLowerBarrel != 0) {
      bits |= kPrimaryStylusButton;
    }
    if (wintab & _wintabUpperBarrel != 0) {
      bits |= kSecondaryStylusButton;
    }
    return bits;
  }

  static const int _wintabTip = 0x01;
  static const int _wintabLowerBarrel = 0x02;
  static const int _wintabUpperBarrel = 0x04;

  /// Whether the pen is turned TAIL-DOWN right now — null when no sidecar
  /// speaks for this moment (which includes every platform but Windows).
  ///
  /// Only Raw Input answers. Windows Ink loses the tail before Flutter
  /// sees it, and Wintab has no portable eraser test; HID declares it.
  static bool? freshInverted({DateTime? now}) =>
      RawPenInputService.instance.freshInverted(now: now);

  @visibleForTesting
  static void debugReset() {
    for (final service in channelServices) {
      service.stop();
    }
    channelServices.clear();
    // Only the observer is stood down here; a test that installed hooks
    // on it resets those through its own debugReset.
    RawPenInputService.instance.stop();
    _bound = false;
  }
}
