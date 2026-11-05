// The pool's pages a pass binds, as many as the device lets it past the
// kernel's own buffers — pages.rs fills them in.
//__PAGES__

// A word of the page this pass bound as its k-th; 0 for any other k, as
// for NO_PAGE, a page of the pool the pass binds none of.
fn page_word(k: u32, index: u32) -> u32 {
  switch (k) {
    //__READS__
    default: {
      return 0u;
    }
  }
}
