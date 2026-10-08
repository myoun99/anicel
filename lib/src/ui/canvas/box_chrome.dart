import 'package:flutter/material.dart';

/// The Ctrl+T box chrome in viewport space: the transformed box outline,
/// the scale handles, and the anchor cross.
///
/// ↩️A rotate KNOB used to hang off the top edge on a lever, and both are
/// gone — 유저 2026-09-22: 「**사각형 밖 조작은 회전으로 통하도록.** 지금
/// 있는 **회전 꼭짓점은 잔재 싹 삭제**하고」. A whole half-plane is a
/// bigger target than a five-pixel circle and needs no aiming.
///
/// ⚠️[anchor] is its own field and not a ninth handle: it is drawn as a
/// CROSS and the handles are drawn as squares, so folding it into that
/// list would only make the painter ask which index it was.
typedef SelectionTransformChrome = ({
  List<Offset> box,
  List<Offset> handles,
  Offset? anchor,
});

/// A handle's square, its outline stroked on the square's own edge.
const double _handleSide = 9;
const double _chromeStroke = 1.5;

/// The cross's arm, from its centre to a tip.
const double _crossArm = 7;

Rect _handleSquare(Offset at) =>
    Rect.fromCenter(center: at, width: _handleSide, height: _handleSide);

/// 🚨★★★**WHAT A HANDLE AT [at] COVERS ON SCREEN — AND SO WHAT A PRESS HAS
/// TO LAND ON TO TAKE IT.**
///
/// 🗣️유저 2026-10-02 (F-262): 「변형도구의 사각형 공통ui, 꼭짓점이나 십자가
/// 등 작동박스가 보이는것보다 큰거같음. 박스 외 부분 조작하는데도 크기가
/// 줄어든다거나 십자가가 움직인다거나. **보이는 만큼 존재하도록.** 십자가는
/// 물론 복잡한 모양이니 **십자가크기의 박스**」.
///
/// ↩️A press took a handle, or the cross, anywhere within 16px of its centre
/// (`boxHandleHitRadius`, 「≥ touch-friendly」) — a disc 32px across round a
/// square drawn 9px wide. So a press well clear of everything drawn still
/// scaled the box or carried the cross off, where the user meant the move
/// or the turn that lives there.
///
/// ⛔ONE SIZE, read by the painter below and by the press ([boxPressAt])
/// alike: what is drawn and what is grabbed cannot drift apart, because
/// there is nothing for either to drift from.
Rect boxHandleFootprint(Offset at) =>
    _handleSquare(at).inflate(_chromeStroke / 2);

/// What the cross at [at] covers: the box its two arms span — 「십자가크기의
/// 박스」. A cross is too thin a shape to be the target itself.
Rect boxCrossFootprint(Offset at) =>
    Rect.fromCenter(center: at, width: _crossArm * 2, height: _crossArm * 2);

/// Paints [chrome] in [color] — the ONE look every transform box on the
/// canvas wears.
///
/// 🗣️F-222 (유저 2026-09-28): 「변형툴,카메라레이어,트랜스폼등fx … 변형
/// 사각형 ui? 이거 전부 다 다르니까, 싹 하나로 통일하면서 ui개선. 포인트
/// ui는 변형툴의 십자가? 해당 ui나 로직 그대로 사용하면서」. The colour is
/// the box's own question: the transform tool's says whether its session
/// has changed anything, a row's box wears the accent (F-222-box-Q5 「지금의
/// 강조색」). An empty [SelectionTransformChrome.box] draws no outline — the
/// camera's frame is its own line.
void paintBoxChrome(
  Canvas canvas,
  SelectionTransformChrome chrome, {
  required Color color,
}) {
  final stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = _chromeStroke
    ..color = color;

  if (chrome.box.isNotEmpty) {
    canvas.drawPath(Path()..addPolygon(chrome.box, true), stroke);
  }
  for (final handle in chrome.handles) {
    canvas.drawRect(_handleSquare(handle), Paint()..color = Colors.white);
    canvas.drawRect(_handleSquare(handle), stroke);
  }
  final anchor = chrome.anchor;
  if (anchor != null) {
    _paintAnchorCross(canvas, anchor, color);
  }
}

/// The rotation centre: a cross, drawn LAST so it reads over the box.
///
/// 🗣️유저 2026-09-20 handed CLIP's own as the reference — 「디자인은 별도
/// 스샷 확인해줘. **중앙에 십자가**가 있어」.
///
/// ⛔A cross rather than a dot, and the reason is the job: the user is
/// placing a CENTRE, so the thing has to say exactly which pixel it is
/// on. A filled dot hides that pixel under itself.
void _paintAnchorCross(Canvas canvas, Offset at, Color color) {
  const arm = _crossArm;
  final white = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..color = Colors.white;
  final ink = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = _chromeStroke
    ..color = color;
  // White underneath for the same reason the ants carry it: the artwork
  // beneath can be any colour, and only the pair reads on both.
  for (final paint in [white, ink]) {
    canvas.drawLine(at - const Offset(arm, 0), at + const Offset(arm, 0),
        paint);
    canvas.drawLine(at - const Offset(0, arm), at + const Offset(0, arm),
        paint);
  }
}
