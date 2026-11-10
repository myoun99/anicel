import '../brush/brush_tool_state.dart' show CanvasTool;

/// Where an action's button stands on the screen — the shortcut window's
/// tree: a PLACE first, then the bar, pill or menu in it, and on the
/// timeline the pills one level further in.
///
/// 🗣️shortcut-presets-anicel-and-clip-studio-Q1 (유저 2026-10-09), the
/// answer picked: 「버튼이 있는 자리로」 = 「큰항목 = 화면의 자리.
/// 「캔버스」(도구 · 세부 도구 · 합성 모드 · 선택 · 편집 · 보기 알약) ·
/// 「타임라인 · 콘티」(이동 · 재생 · 컷/레이어/프레임/FX 알약 · 레이어 머리) ·
/// 「도구 라이브러리」(브러시 라이브러리 · 브러시 도구의 브러시 · 지우개 도구의
/// 브러시) · 「맨 위 띠」(파일 · 설정 · 패널 · 디버그). 셋째 단 = 알약 · 메뉴
/// 하나하나 … 버튼이 없는 키(위 레이어 · 다음 프레임 등)는 그 키가 움직이는
/// 곳에 선다」.
/// ⚠️MY READINGS, each by where the button is: the clipboard rows and the
/// colour edit list are the timeline's shared pill's, so the canvas's 편집
/// keeps the rail's undo and redo; the onion and the solo are the rail's
/// too, beside the view; the guide ＋ and the text 🗑 are their tool's
/// panel's, so they stand under their tool. ↩️A panel's own buttons (media
/// · timesheet · conte sheet · cut envelope · palette) stood in a fifth
/// place, 「패널 안」, until F-580 took them off the list.
///
/// 🗣️F-560 (유저 2026-11-04): 「도구 라이브러리 단축키들, 브러시 도구의
/// 브러시같은거나 해당 항목 전부. 캔버스-세부도구랑 사실상 겹치니까 그
/// 세부도구쪽에 싹 다 이전해서 알기쉽게. 브러시랑 세부도구랑 사실상
/// 같은거니까」 — the tool library's shelves stand under 세부 도구 now, and
/// the place they made is gone. ↩️「도구 라이브러리」 was a place of the
/// answer above.
///
/// 🗣️F-580 (유저 2026-11-10): 「캔버스-도구에 도구 있고, 그 밑에 해당 도구의
/// 세부도구 … 도구-세부도구-도구-세부도구 순으로 있는게 알기쉬움. 그리고 브러시
/// 가져오기 버튼등이 있는 브러시 라이브러리, 단축키로 있을 필요없어보이니 해당
/// 항목 깔끔하게 삭제 … 패널 안의 미디어-임포트 이런식으로 패널 안 항목도
/// 깔끔하게 삭제」 — under 도구 each tool's row stands with its own under it:
/// its tiles (`subToolTilesOf`) and the shelf that names it ([tool]). The
/// brush library's rows and 「패널 안」 went, with their place. ↩️세부 도구
/// was a shelf of every tool's tiles and the tool library's shelves (F-560).
///
/// ★AN ACTION NAMES ITS SHELF AND NOTHING ELSE: every heading above it is
/// the shelf's [parent]s, so a shelf added here arrives in the window, in
/// the guide's page and in the search at once. A tile names its tool by its
/// press, as the tool library's tile does.
enum ShortcutShelf {
  canvas('Canvas'),
  tools('Tools', canvas),
  brushToolBrushes('Brush Tool Brushes', tools, CanvasTool.brush),
  eraserToolBrushes('Eraser Tool Brushes', tools, CanvasTool.eraser),
  texts('Texts', tools, CanvasTool.text),
  guides('Guides', tools, CanvasTool.guide),
  blendModes('Blend modes', canvas),
  selection('Selection', canvas),
  edit('Edit', canvas),
  view('View', canvas),

  timeline('Timeline · Conte'),
  moves('Navigation', timeline),
  playback('Playback', timeline),
  pills('Pills', timeline),
  cutPill('Cut pill', pills),
  layerPill('Layer pill', pills),
  framePill('Frame pill', pills),
  fxPill('FX pill', pills),
  sharedPill('Shared pill', pills),
  colourEdit('Color Edit', pills),
  layerHeader('Layer Header', timeline),
  timelineBar('Timeline bar', timeline),

  topStrip('Top strip'),
  file('File', topStrip),
  settings('Settings', topStrip),
  panels('Panels', topStrip),
  debug('Debug', topStrip);

  const ShortcutShelf(this.label, [this.parent, this.tool]);

  /// Its English name — the English row, as an action's label is
  /// (`AppStrings.shortcutShelfName` holds the other languages).
  final String label;

  /// The shelf it stands on, or null for a place.
  final ShortcutShelf? parent;

  /// The rail tool whose row it stands under, among its [parent]'s rows —
  /// a tool's own shelf; null for a shelf after its parent's rows.
  final CanvasTool? tool;

  /// The shelves from its place down to itself.
  List<ShortcutShelf> get path => [...?parent?.path, this];

  /// The shelves that stand on this one, in the order they are listed.
  Iterable<ShortcutShelf> get shelves =>
      values.where((shelf) => shelf.parent == this);

  /// The places — the shelves that stand on none.
  static Iterable<ShortcutShelf> get places =>
      values.where((shelf) => shelf.parent == null);
}
