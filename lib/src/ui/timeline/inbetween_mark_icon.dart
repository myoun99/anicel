import 'package:flutter/material.dart';

import '../../models/frame.dart' show InbetweenMark;

/// A mark's face where it is pressed or picked — its toggle button, the
/// mark-every window's pick and the setting of the mark a block with no name
/// wears — so the three read as one mark.
///
/// 🗣️F-497 (유저 2026-10-28): 「이름없는 블록 마크 버튼 텍스트가 아니라 마크
/// 그대로사용 … 텍스트면 뭔지 알기힘드니」. ↩️The setting read the toggle's
/// name in words; the face stood in the toolbar's file, the other two's.
IconData inbetweenMarkIcon(InbetweenMark mark) => switch (mark) {
  InbetweenMark.one => Icons.circle_outlined,
  InbetweenMark.two => Icons.circle,
};
