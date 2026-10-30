/// How much of the conte sheet a cell whose camera moves takes (🗣️I-82, 유저
/// 2026-10-06: 「콘티용지패널의 카메라 실루엣, 얼마나 카메라 이동하던
/// 픽쳐칸 안에서만 표현(그림이나 카메라를 작게해서)하는 옵션이랑 지금처럼
/// se칸까지 크게 키운다거나 세로로 키운다거나 가능하게 하는거 옵션으로」) —
/// the format window's for the whole sheet (`TimesheetInfo.conteCameraRoom`)
/// and a cut's own over it (`CutMetadata.conteCameraRoom`): I-82-Q1 (유저
/// 2026-10-30) 「서식 전체 + 컷마다 덮어쓰기」.
enum ConteCameraRoom {
  /// The picture grows down the rows and into the columns beside it as far
  /// as the sweep asks (`conteCameraPlan`) — the sheet's first way.
  grows,

  /// The picture keeps its cell: its box is a still cell's, always, and the
  /// sweep is laid small enough to stand whole in the cell's own window, as
  /// Storyboard Pro's Fit Camera Path lays it.
  ///
  /// 🗣️유저 2026-10-30: 「칸 안에 라는건 픽쳐칸의 사각형은 항상 고정크기고,
  /// 카메라 움직임에 맞춰서 내부를 필요시 비율 줄여서 카메라 움직임 사각형 다
  /// 들어가게하는것. 지금 좌우로 움직임있을때 픽쳐 칸 실루엣이 좌우로 길어지거나
  /// 줄거나 함」. ↩️The box hugged the sweep, as the room that grows lays it.
  inCell;

  /// What a sheet takes that does not say — 🗣️유저 2026-10-30: 「그리고
  /// 기본값은 칸 안에가 되도록」. ↩️[grows], the sheet's first way.
  static const standard = inCell;

  /// The room [name] names in a file — null for none, and for a name this
  /// build does not know.
  static ConteCameraRoom? named(Object? name) {
    for (final room in values) {
      if (room.name == name) {
        return room;
      }
    }
    return null;
  }
}
