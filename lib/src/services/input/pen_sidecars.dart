import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show kPrimaryButton, kPrimaryStylusButton, kSecondaryStylusButton;

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
/// - macOS / Linux: the platform channel services (PEN-4), started
///   unconditionally on their platform by [bind] — they only restore
///   data the embedder drops today.
///
/// The brush canvas asks [freshContactPressure] per pointer sample; the
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
    if (Platform.isMacOS) {
      channelServices.add(PlatformPenChannelService.macos()..start());
    } else if (Platform.isLinux) {
      channelServices.add(PlatformPenChannelService.linux()..start());
    }
  }

  /// The freshest driver-side contact pressure across every live
  /// sidecar; null = no sidecar speaks for this moment (use the pointer
  /// event's own pressure).
  static double? freshContactPressure() {
    final wintab = WintabPenService.instance.freshContactPressure();
    if (wintab != null) {
      return wintab;
    }
    for (final service in channelServices) {
      final pressure = service.freshContactPressure();
      if (pressure != null) {
        return pressure;
      }
    }
    return null;
  }

  /// The freshest driver-side BUTTON state, as FLUTTER button bits; null =
  /// no sidecar speaks for this moment (use the pointer event's own).
  ///
  /// Only Wintab answers: the macOS/Linux channel sidecars restore
  /// pressure the embedder drops, not buttons.
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
