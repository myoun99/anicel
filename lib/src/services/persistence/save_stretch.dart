/// What a save is doing while it reports how far it is, in the order a
/// save runs them — the wait window's line names the one under way.
///
/// 🗣️F-494 (유저 2026-10-28): 「저장같은것도 저장중 말고 어차피 창의 제목에
/// 저장이라고 있으니까 셀을 저장? … 하고있는 과정을 보여주는식으로」. The
/// stretches are what the writers DO, one each: what a save writes is said
/// by the entry kind it is writing, not by a guess at where the time goes.
enum SaveStretch {
  /// The media the save takes out of the file, copied into this run's room
  /// before the file moves over them (`MediaStagingStore.keepLeftBehind`).
  keepingLeftBehind,

  /// The cels, each written or carried across.
  cels,

  /// An append reading what it streams once to checksum it before the file
  /// is touched (`appendAnicelEntries`).
  checking,

  /// The media the project carries.
  media,

  /// The sounds converted for playback that ride beside them.
  conforms,

  /// The fonts the project carries.
  fonts,

  /// The live bytes pushed down over what the save left dead
  /// (`compactAnicelInPlace`).
  compacting,

  /// The whole file handed back to the document it was opened from
  /// (`ProviderDocuments.publish`).
  handingBack,
}
