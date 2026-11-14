//! Reading a plugin's text past its comments: where a body's `{` lies, so
//! count.rs can put a charge just inside it.

/// The offset just past the first `{` at or after `from` that is outside
/// comments and parentheses — the body of the loop or function whose text
/// starts at `from`. WGSL has no strings, and no expression holds a brace.
pub(crate) fn body_open(source: &str, from: usize) -> Option<usize> {
    let bytes = source.as_bytes();
    let mut at = from;
    let mut depth = 0i32;
    while at < bytes.len() {
        if let Some(past) = comment_end(bytes, at) {
            at = past;
            continue;
        }
        match bytes[at] {
            b'(' | b'[' => depth += 1,
            b')' | b']' => depth -= 1,
            b'{' if depth == 0 => return Some(at + 1),
            _ => {}
        }
        at += 1;
    }
    None
}

/// Where the `fn` that declares `name` begins, outside comments.
pub(crate) fn function_at(source: &str, name: &str) -> Option<usize> {
    let words = words(source);
    words.windows(2).find(|pair| pair[0].1 == "fn" && pair[1].1 == name).map(|pair| pair[0].0)
}

/// Every identifier-like word outside comments, with where it starts.
pub(crate) fn words(source: &str) -> Vec<(usize, &str)> {
    let bytes = source.as_bytes();
    let mut found = Vec::new();
    let mut at = 0;
    while at < bytes.len() {
        if let Some(past) = comment_end(bytes, at) {
            at = past;
            continue;
        }
        if is_word(bytes[at]) {
            let start = at;
            while at < bytes.len() && is_word(bytes[at]) {
                at += 1;
            }
            found.push((start, &source[start..at]));
            continue;
        }
        at += 1;
    }
    found
}

/// The first byte at or after `from` that is neither blank nor in a
/// comment — what the text says next.
pub(crate) fn next_byte(source: &str, from: usize) -> Option<u8> {
    let bytes = source.as_bytes();
    let mut at = from;
    while at < bytes.len() {
        if let Some(past) = comment_end(bytes, at) {
            at = past;
        } else if bytes[at].is_ascii_whitespace() {
            at += 1;
        } else {
            return Some(bytes[at]);
        }
    }
    None
}

fn is_word(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || byte == b'_'
}

/// Past the comment that starts at `at`, if one does. WGSL's block
/// comments nest.
fn comment_end(bytes: &[u8], at: usize) -> Option<usize> {
    match (bytes.get(at), bytes.get(at + 1)) {
        (Some(b'/'), Some(b'/')) => {
            let mut past = at + 2;
            while past < bytes.len() && bytes[past] != b'\n' {
                past += 1;
            }
            Some(past)
        }
        (Some(b'/'), Some(b'*')) => {
            let mut past = at + 2;
            let mut open = 1;
            while past < bytes.len() && open > 0 {
                match (bytes[past], bytes.get(past + 1)) {
                    (b'/', Some(b'*')) => {
                        open += 1;
                        past += 2;
                    }
                    (b'*', Some(b'/')) => {
                        open -= 1;
                        past += 2;
                    }
                    _ => past += 1,
                }
            }
            Some(past)
        }
        _ => None,
    }
}

/// Where the first float literal outside comments begins, if one does: a
/// decimal number with a `.`, an exponent or an `f` · `h` suffix, or a hex
/// one with a `.` or a `p` exponent (WGSL's literal grammar).
pub(crate) fn first_float_literal(source: &str) -> Option<usize> {
    let bytes = source.as_bytes();
    let mut at = 0;
    while at < bytes.len() {
        if let Some(past) = comment_end(bytes, at) {
            at = past;
            continue;
        }
        if is_word(bytes[at]) && !bytes[at].is_ascii_digit() {
            while at < bytes.len() && is_word(bytes[at]) {
                at += 1;
            }
            continue;
        }
        let starts_number = bytes[at].is_ascii_digit()
            || (bytes[at] == b'.' && bytes.get(at + 1).is_some_and(u8::is_ascii_digit));
        if !starts_number {
            at += 1;
            continue;
        }
        let start = at;
        let hex = bytes[at] == b'0' && matches!(bytes.get(at + 1), Some(b'x' | b'X'));
        if hex {
            at += 2;
        }
        let mut float = false;
        while at < bytes.len() {
            let byte = bytes[at];
            let exponent = if hex { matches!(byte, b'p' | b'P') } else { matches!(byte, b'e' | b'E') };
            if exponent {
                float = true;
                at += 1;
                if matches!(bytes.get(at), Some(b'+' | b'-')) {
                    at += 1;
                }
            } else if byte == b'.' {
                float = true;
                at += 1;
            } else if is_word(byte) {
                if !hex && matches!(byte, b'f' | b'h') {
                    float = true;
                }
                at += 1;
            } else {
                break;
            }
        }
        if float {
            return Some(start);
        }
    }
    None
}
