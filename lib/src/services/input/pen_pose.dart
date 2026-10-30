import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

import '../../native/qa_pen_ledger.dart';
import 'pen_lean.dart';
import 'pen_sidecars.dart';

/// HOW THE PEN IS HELD at one pointer event: its lean and its twist about
/// the barrel, each null where nothing measured it.
typedef PenPose = ({PenLean? lean, double? twist});

/// [event]'s pose, read from whoever carries each half on this platform.
///
/// ONE reader for everyone who asks (F-176-Q7, 유저 2026-10-21 「펜을
/// 따라 바뀐다」): a stroke reads the pose per sample and the brush cursor
/// per hover, so the outline a hovering pen shows is the tip it lays down.
PenPose penPoseOf(PointerEvent event) =>
    (lean: penLeanOf(event), twist: penTwistOf(event));

/// How the pen leans at [event], as the pair a dab carries ([PenLean]) — or
/// null where nothing measured one. Every sample's lean is a reading; where
/// the ledger holds UIKit's measurement of the Pencil's altitude, that is
/// the altitude ([recordedPenLean]).
///
/// ★FROM WHOEVER CARRIES THE LEAN FOR THIS EVENT (desktop-pen-tilt,
/// 2026-09-28): the pointer on iOS and Android; on a desktop, whose
/// pointer carries none ([_pointerCarriesLean]), the platform's own
/// record — the NSEvent's, through the pen ledger, on macOS, and the
/// driver's, through the sidecars, on Windows. Each speaks its own
/// convention, and `pen_lean.dart` is the one place they become one.
/// ↩️This used to read the pointer alone, 「deliberately, and unlike
/// pressure」, because no defect in tilt was known: the defect was that a
/// desktop pointer has no tilt to read.
///
/// 🚨NULL WHEN THE DEVICE REPORTED NONE — it used to answer "upright pen"
/// (altitude 1.0), which is a reading a mouse never made. 유저 2026-09-09,
/// `brush-tilt-no-device-Q1` 답 1: 「기울기 못 재는 기기에서는 傾き 소스를
/// 건너뛴다」 (「1번이 구조적으로 맞아보여서」). With the invented value, an
/// imported brush whose tilt minimum is 0% drew nothing at all on a mouse
/// and nothing on screen could say why.
///
/// ↩️An altitude UIKit called an estimate used to WAIT, as its force did
/// (H43 round two). Build 1065 showed UIKit calling nearly every sample's
/// force an estimate, and the lean crosses the same Bluetooth link: a tilt
/// brush would have waited the whole patience on every stroke. The
/// estimate is UIKit's best value, so it is read — pressure's law, which
/// holds only the press repeated.
PenLean? penLeanOf(PointerEvent event) {
  final carried = _carriedLean(event);
  if (carried == null) {
    return null;
  }
  return recordedPenLean(event.timeStamp, carried.azimuthDegrees) ?? carried;
}

/// The lean the platform has by now MEASURED for the sample stamped [at] —
/// UIKit's altitude sent after the fact, with the sample's own
/// [azimuthDegrees] — or null when the ledger holds no measurement of it.
PenLean? recordedPenLean(Duration at, double azimuthDegrees) {
  final recorded = QaPenLedger.altitudeAt(at);
  if (recorded == null || recorded.state != PenLedgerState.measured) {
    return null;
  }
  return (
    azimuthDegrees: azimuthDegrees,
    // UIKit's altitude is radians up from the surface; a dab's is 0..1.
    altitude: (recorded.value / (math.pi / 2.0)).clamp(0.0, 1.0),
  );
}

/// How far the pen is turned about its own barrel at [event], in degrees
/// 0..360 clockwise — null where nothing measured one (F-176-Q9, Clip
/// Studio's ペン軸の回転).
///
/// Only Windows' driver-side streams carry it ([PenSidecars.freshTwist]).
/// Flutter's pointer has no field for it on any platform — the Windows
/// embedder reads POINTER_PEN_INFO's rotation into a pan-zoom field that a
/// pen's event never shows — and the macOS pen ledger records no rotation
/// yet, so everywhere else this is null: the twist base turns nothing
/// there, as 없음 does.
double? penTwistOf(PointerEvent event) =>
    _pointerCarriesLean ? null : PenSidecars.freshTwist();

/// The lean as [event]'s carrier states it, before the ledger's later
/// measurement ([penLeanOf]).
PenLean? _carriedLean(PointerEvent event) {
  if (!_pointerCarriesLean) {
    final appKit = QaPenLedger.tiltAt(event.timeStamp);
    if (appKit != null) {
      return penLeanFromAppKitTilt(x: appKit.x, y: appKit.y);
    }
    return PenSidecars.freshLean();
  }
  if (!PenSidecars.isPenKind(event.kind)) {
    return null;
  }
  final tilt = event.tilt;
  if (!tilt.isFinite) {
    return null;
  }
  return penLeanFromPointer(tilt: tilt, orientation: event.orientation);
}

/// 🚨WHERE THE POINTER CARRIES NO LEAN AT ALL (checked 2026-09-27 on
/// 3.47). Flutter's desktop embedder API has no tilt field: Windows reads
/// POINTER_PEN_INFO's pressure and rotation and drops tiltX/tiltY, Linux's
/// carries the same two (flutter/flutter#186831), and macOS never sees a pen.
/// There a 0 is the field's default, not a pen held upright — the invented
/// reading `brush-tilt-no-device-Q1` ruled out. Only iOS (UITouch's altitude)
/// and Android (AXIS_TILT) carry the lean; everywhere else [_carriedLean] asks
/// the platform's own record.
bool get _pointerCarriesLean =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.android;
