import 'dart:ui';

/// Fits [content] inside [slot] without distorting it — a stamp is a
/// stamp, not a stretched one.
///
/// ⚠️Aspect ratio is PRESERVED (`BoxFit.contain`) — 정본: 「늘어난 도장은
/// 도장이 아니다」 (the decision is written out at
/// `timesheet_info_dialog.dart`'s staff stamp cell); this is the law that
/// decision names, and the envelope stamp, the conte page picture and the
/// conte PDF picture all draw through it.
///
/// The result is centred in [slot] on both axes. A slot with no area is
/// the caller's question, not this one's: it answers with an empty rect at
/// the slot's own origin.
Rect containRect(Size content, Rect slot) {
  if (content.width <= 0 || content.height <= 0) {
    return Rect.fromLTWH(slot.left, slot.top, 0, 0);
  }
  final widthScale = slot.width / content.width;
  final heightScale = slot.height / content.height;
  final scale = widthScale < heightScale ? widthScale : heightScale;
  final width = content.width * scale;
  final height = content.height * scale;
  return Rect.fromLTWH(
    slot.left + (slot.width - width) / 2,
    slot.top + (slot.height - height) / 2,
    width,
    height,
  );
}
