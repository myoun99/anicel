//! XXH64, the hash a zstd frame's checksum is the low 32 bits of.

const P1: u64 = 0x9E37_79B1_85EB_CA87;
const P2: u64 = 0xC2B2_AE3D_27D4_EB4F;
const P3: u64 = 0x1656_67B1_9E37_79F9;
const P4: u64 = 0x85EB_CA77_C2B2_AE63;
const P5: u64 = 0x27D4_EB2F_1656_67C5;

fn le64(bytes: &[u8]) -> u64 {
    u64::from_le_bytes(bytes[..8].try_into().expect("8 bytes"))
}

fn round(acc: u64, input: u64) -> u64 {
    acc.wrapping_add(input.wrapping_mul(P2)).rotate_left(31).wrapping_mul(P1)
}

fn merge(acc: u64, value: u64) -> u64 {
    (acc ^ round(0, value)).wrapping_mul(P1).wrapping_add(P4)
}

pub(crate) fn xxh64(data: &[u8], seed: u64) -> u64 {
    let mut rest = data;
    let mut hash = if data.len() >= 32 {
        let mut lanes =
            [seed.wrapping_add(P1).wrapping_add(P2), seed.wrapping_add(P2), seed, seed.wrapping_sub(P1)];
        while rest.len() >= 32 {
            for (k, lane) in lanes.iter_mut().enumerate() {
                *lane = round(*lane, le64(&rest[8 * k..]));
            }
            rest = &rest[32..];
        }
        let [a, b, c, d] = lanes;
        let hash = a.rotate_left(1).wrapping_add(b.rotate_left(7)).wrapping_add(c.rotate_left(12)).wrapping_add(d.rotate_left(18));
        lanes.iter().fold(hash, |hash, &lane| merge(hash, lane))
    } else {
        seed.wrapping_add(P5)
    };
    hash = hash.wrapping_add(data.len() as u64);
    while rest.len() >= 8 {
        hash = (hash ^ round(0, le64(rest))).rotate_left(27).wrapping_mul(P1).wrapping_add(P4);
        rest = &rest[8..];
    }
    if rest.len() >= 4 {
        let word = u64::from(u32::from_le_bytes(rest[..4].try_into().expect("4 bytes")));
        hash = (hash ^ word.wrapping_mul(P1)).rotate_left(23).wrapping_mul(P2).wrapping_add(P3);
        rest = &rest[4..];
    }
    for &byte in rest {
        hash = (hash ^ u64::from(byte).wrapping_mul(P5)).rotate_left(11).wrapping_mul(P1);
    }
    hash ^= hash >> 33;
    hash = hash.wrapping_mul(P2);
    hash ^= hash >> 29;
    hash = hash.wrapping_mul(P3);
    hash ^ (hash >> 32)
}
