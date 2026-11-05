// Puts `word` at `index` of the page this pass bound as its k-th; nowhere
// for any other k, as for NO_PAGE. Only a kernel that binds its pages to
// read and write has it (pages.rs's `Pages::writable`).
fn page_put(k: u32, index: u32, word: u32) {
  switch (k) {
    //__PUTS__
    default: {}
  }
}
