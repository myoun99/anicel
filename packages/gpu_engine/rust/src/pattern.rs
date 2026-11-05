//! The CPU side of `fill.wgsl`'s formula: the oracle the GPU's bytes are
//! checked against, so "the same on every device" is also "the right
//! bytes", not only agreement between devices.

/// Texel byte order in memory.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Order {
    Bgra,
    Rgba,
}

/// lowbias32 — `mix32` in `fill.wgsl`.
pub fn mix32(v: u32) -> u32 {
    let mut h = v;
    h ^= h >> 16;
    h = h.wrapping_mul(0x7feb_352d);
    h ^= h >> 15;
    h = h.wrapping_mul(0x846c_a68b);
    h ^= h >> 16;
    h
}

/// The packed texel `fill.wgsl` writes: byte i is channel i (R, G, B, A).
pub fn texel(x: u32, y: u32, seed: u32) -> u32 {
    (mix32(x ^ mix32(y ^ mix32(seed))) & 0x00ff_ffff) | 0xff00_0000
}

/// The texel's four bytes as they sit in a texture of `order`.
pub fn texel_bytes(packed: u32, order: Order) -> [u8; 4] {
    let [r, g, b, a] = packed.to_le_bytes();
    match order {
        Order::Bgra => [b, g, r, a],
        Order::Rgba => [r, g, b, a],
    }
}

/// FNV-1a, 64-bit: the fingerprint compared across devices.
pub struct Fnv1a64(u64);

impl Fnv1a64 {
    pub fn new() -> Self {
        Self(0xcbf2_9ce4_8422_2325)
    }

    pub fn write(&mut self, bytes: &[u8]) {
        for &byte in bytes {
            self.0 ^= u64::from(byte);
            self.0 = self.0.wrapping_mul(0x0000_0100_0000_01b3);
        }
    }

    pub fn finish(&self) -> u64 {
        self.0
    }
}

/// The hash of the whole texture, rows top to bottom, as the CPU says it
/// should be.
pub fn expected_hash(width: u32, height: u32, seed: u32, order: Order) -> u64 {
    let mut hash = Fnv1a64::new();
    for y in 0..height {
        for x in 0..width {
            hash.write(&texel_bytes(texel(x, y, seed), order));
        }
    }
    hash.finish()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fnv_of_nothing_is_its_offset_basis() {
        assert_eq!(Fnv1a64::new().finish(), 0xcbf2_9ce4_8422_2325);
    }

    #[test]
    fn fnv_matches_the_published_vector_for_a() {
        let mut hash = Fnv1a64::new();
        hash.write(b"a");
        assert_eq!(hash.finish(), 0xaf63_dc4c_8601_ec8c);
    }

    #[test]
    fn every_texel_is_opaque() {
        for (x, y) in [(0, 0), (1, 0), (0, 1), (4095, 4095)] {
            assert_eq!(texel(x, y, 7) >> 24, 0xff);
        }
    }

    #[test]
    fn the_orders_swap_only_red_and_blue() {
        let packed = 0xff33_2211;
        assert_eq!(texel_bytes(packed, Order::Rgba), [0x11, 0x22, 0x33, 0xff]);
        assert_eq!(texel_bytes(packed, Order::Bgra), [0x33, 0x22, 0x11, 0xff]);
    }
}
