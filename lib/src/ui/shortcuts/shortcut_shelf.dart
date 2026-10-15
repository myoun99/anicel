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
/// panel's, under the tool library; and a panel's own buttons (media ·
/// timesheet · conte sheet · cut envelope) stand in a fifth place,
/// 「패널 안」 — the answer's four have none for them.
///
/// ★AN ACTION NAMES ITS SHELF AND NOTHING ELSE: every heading above it is
/// the shelf's [parent]s, so a shelf added here arrives in the window, in
/// the guide's page and in the search at once.
enum ShortcutShelf {
  canvas('Canvas'),
  tools('Tools', canvas),
  toolTiles('Sub tools', canvas),
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

  toolLibrary('Tool library'),
  brushLibrary('Brush Library', toolLibrary),
  brushToolBrushes('Brush Tool Brushes', toolLibrary),
  eraserToolBrushes('Eraser Tool Brushes', toolLibrary),
  guides('Guides', toolLibrary),
  texts('Texts', toolLibrary),

  topStrip('Top strip'),
  file('File', topStrip),
  settings('Settings', topStrip),
  panels('Panels', topStrip),
  debug('Debug', topStrip),

  inAPanel('In a panel'),
  media('Media', inAPanel),
  timesheet('Timesheet', inAPanel),
  conteSheet('Conte Sheet', inAPanel),
  envelope('Cut envelope', inAPanel);

  const ShortcutShelf(this.label, [this.parent]);

  /// Its English name — the English row, as an action's label is
  /// (`AppStrings.shortcutShelfName` holds the other languages).
  final String label;

  /// The shelf it stands on, or null for a place.
  final ShortcutShelf? parent;

  /// The shelves from its place down to itself.
  List<ShortcutShelf> get path => [...?parent?.path, this];

  /// The shelves that stand on this one, in the order they are listed.
  Iterable<ShortcutShelf> get shelves =>
      values.where((shelf) => shelf.parent == this);

  /// The places — the shelves that stand on none.
  static Iterable<ShortcutShelf> get places =>
      values.where((shelf) => shelf.parent == null);
}
