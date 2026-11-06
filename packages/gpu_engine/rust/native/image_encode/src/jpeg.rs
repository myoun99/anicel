//! Baseline JPEG of three channels, as stb_image_write v1.16 writes one —
//! its JPEG writer, after Jon Olick's public-domain jo_jpeg — byte for
//! byte (native-to-rust: the C is the answer key until the connection
//! round deletes it).
//!
//! The floats are stb's, in stb's order: f32 and no fused multiply-add
//! here, nor in the C the engine builds (clang `-ffp-contract=off`, MSVC
//! contracts nothing unless told), so each step rounds as the C's does.
//!
//! ⛔What stb has and this does not: other channel counts, a flipped
//! write, and quality 0 meaning 90 — the engine's one caller passes three
//! channels top-down with its quality clamped to 1..=100 first
//! (qa_image_encode.c).

/// Where each of a block's 64 coefficients goes, in row order.
const ZIGZAG: [usize; 64] = [
    0, 1, 5, 6, 14, 15, 27, 28, 2, 4, 7, 13, 16, 26, 29, 42, 3, 8, 12, 17, 25, 30, 41, 43, 9, 11,
    18, 24, 31, 40, 44, 53, 10, 19, 23, 32, 39, 45, 52, 54, 20, 22, 33, 38, 46, 51, 55, 60, 21, 34,
    37, 47, 50, 56, 59, 61, 35, 36, 48, 49, 57, 58, 62, 63,
];

/// A code: its bits, then how many.
type Code = [u16; 2];

const DC_LUMINANCE_COUNTS: [u8; 16] = [0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0];
const DC_LUMINANCE_VALUES: [u8; 12] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
const AC_LUMINANCE_COUNTS: [u8; 16] = [0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7d];
const AC_LUMINANCE_VALUES: [u8; 162] = [
    0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07,
    0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xa1, 0x08, 0x23, 0x42, 0xb1, 0xc1, 0x15, 0x52, 0xd1, 0xf0,
    0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0a, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x25, 0x26, 0x27, 0x28,
    0x29, 0x2a, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
    0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69,
    0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
    0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7,
    0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3, 0xc4, 0xc5,
    0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xe1, 0xe2,
    0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8,
    0xf9, 0xfa,
];
const DC_CHROMINANCE_COUNTS: [u8; 16] = [0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0];
const DC_CHROMINANCE_VALUES: [u8; 12] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
const AC_CHROMINANCE_COUNTS: [u8; 16] = [0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0x77];
const AC_CHROMINANCE_VALUES: [u8; 162] = [
    0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71,
    0x13, 0x22, 0x32, 0x81, 0x08, 0x14, 0x42, 0x91, 0xa1, 0xb1, 0xc1, 0x09, 0x23, 0x33, 0x52, 0xf0,
    0x15, 0x62, 0x72, 0xd1, 0x0a, 0x16, 0x24, 0x34, 0xe1, 0x25, 0xf1, 0x17, 0x18, 0x19, 0x1a, 0x26,
    0x27, 0x28, 0x29, 0x2a, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48,
    0x49, 0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68,
    0x69, 0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
    0x88, 0x89, 0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5,
    0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3,
    0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda,
    0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8,
    0xf9, 0xfa,
];

/// The codes of a DC difference's length.
const Y_DC: [Code; 12] = [
    [0, 2], [2, 3], [3, 3], [4, 3], [5, 3], [6, 3], [14, 4], [30, 5], [62, 6], [126, 7], [254, 8],
    [510, 9],
];
const UV_DC: [Code; 12] = [
    [0, 2], [1, 2], [2, 2], [6, 3], [14, 4], [30, 5], [62, 6], [126, 7], [254, 8], [510, 9],
    [1022, 10], [2046, 11],
];

/// The codes of a run of zeros (high nibble) and the length after it.
const Y_AC: [Code; 256] = codes(&[
    [10, 4], [0, 2], [1, 2], [4, 3], [11, 4], [26, 5], [120, 7], [248, 8], [1014, 10], [65410, 16],
    [65411, 16], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [12, 4], [27, 5], [121, 7],
    [502, 9], [2038, 11], [65412, 16], [65413, 16], [65414, 16], [65415, 16], [65416, 16], [0, 0],
    [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [28, 5], [249, 8], [1015, 10], [4084, 12], [65417, 16],
    [65418, 16], [65419, 16], [65420, 16], [65421, 16], [65422, 16], [0, 0], [0, 0], [0, 0],
    [0, 0], [0, 0], [0, 0], [58, 6], [503, 9], [4085, 12], [65423, 16], [65424, 16], [65425, 16],
    [65426, 16], [65427, 16], [65428, 16], [65429, 16], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0],
    [0, 0], [59, 6], [1016, 10], [65430, 16], [65431, 16], [65432, 16], [65433, 16], [65434, 16],
    [65435, 16], [65436, 16], [65437, 16], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0],
    [122, 7], [2039, 11], [65438, 16], [65439, 16], [65440, 16], [65441, 16], [65442, 16],
    [65443, 16], [65444, 16], [65445, 16], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0],
    [123, 7], [4086, 12], [65446, 16], [65447, 16], [65448, 16], [65449, 16], [65450, 16],
    [65451, 16], [65452, 16], [65453, 16], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0],
    [250, 8], [4087, 12], [65454, 16], [65455, 16], [65456, 16], [65457, 16], [65458, 16],
    [65459, 16], [65460, 16], [65461, 16], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0],
    [504, 9], [32704, 15], [65462, 16], [65463, 16], [65464, 16], [65465, 16], [65466, 16],
    [65467, 16], [65468, 16], [65469, 16], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0],
    [505, 9], [65470, 16], [65471, 16], [65472, 16], [65473, 16], [65474, 16], [65475, 16],
    [65476, 16], [65477, 16], [65478, 16], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0],
    [506, 9], [65479, 16], [65480, 16], [65481, 16], [65482, 16], [65483, 16], [65484, 16],
    [65485, 16], [65486, 16], [65487, 16], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0],
    [1017, 10], [65488, 16], [65489, 16], [65490, 16], [65491, 16], [65492, 16], [65493, 16],
    [65494, 16], [65495, 16], [65496, 16], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0],
    [1018, 10], [65497, 16], [65498, 16], [65499, 16], [65500, 16], [65501, 16], [65502, 16],
    [65503, 16], [65504, 16], [65505, 16], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0],
    [2040, 11], [65506, 16], [65507, 16], [65508, 16], [65509, 16], [65510, 16], [65511, 16],
    [65512, 16], [65513, 16], [65514, 16], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0],
    [65515, 16], [65516, 16], [65517, 16], [65518, 16], [65519, 16], [65520, 16], [65521, 16],
    [65522, 16], [65523, 16], [65524, 16], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [2041, 11],
    [65525, 16], [65526, 16], [65527, 16], [65528, 16], [65529, 16], [65530, 16], [65531, 16],
    [65532, 16], [65533, 16], [65534, 16], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0],
]);
const UV_AC: [Code; 256] = codes(&[
    [0, 2], [1, 2], [4, 3], [10, 4], [24, 5], [25, 5], [56, 6], [120, 7], [500, 9], [1014, 10],
    [4084, 12], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [11, 4], [57, 6], [246, 8],
    [501, 9], [2038, 11], [4085, 12], [65416, 16], [65417, 16], [65418, 16], [65419, 16], [0, 0],
    [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [26, 5], [247, 8], [1015, 10], [4086, 12],
    [32706, 15], [65420, 16], [65421, 16], [65422, 16], [65423, 16], [65424, 16], [0, 0], [0, 0],
    [0, 0], [0, 0], [0, 0], [0, 0], [27, 5], [248, 8], [1016, 10], [4087, 12], [65425, 16],
    [65426, 16], [65427, 16], [65428, 16], [65429, 16], [65430, 16], [0, 0], [0, 0], [0, 0],
    [0, 0], [0, 0], [0, 0], [58, 6], [502, 9], [65431, 16], [65432, 16], [65433, 16], [65434, 16],
    [65435, 16], [65436, 16], [65437, 16], [65438, 16], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0],
    [0, 0], [59, 6], [1017, 10], [65439, 16], [65440, 16], [65441, 16], [65442, 16], [65443, 16],
    [65444, 16], [65445, 16], [65446, 16], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0],
    [121, 7], [2039, 11], [65447, 16], [65448, 16], [65449, 16], [65450, 16], [65451, 16],
    [65452, 16], [65453, 16], [65454, 16], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0],
    [122, 7], [2040, 11], [65455, 16], [65456, 16], [65457, 16], [65458, 16], [65459, 16],
    [65460, 16], [65461, 16], [65462, 16], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0],
    [249, 8], [65463, 16], [65464, 16], [65465, 16], [65466, 16], [65467, 16], [65468, 16],
    [65469, 16], [65470, 16], [65471, 16], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0],
    [503, 9], [65472, 16], [65473, 16], [65474, 16], [65475, 16], [65476, 16], [65477, 16],
    [65478, 16], [65479, 16], [65480, 16], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0],
    [504, 9], [65481, 16], [65482, 16], [65483, 16], [65484, 16], [65485, 16], [65486, 16],
    [65487, 16], [65488, 16], [65489, 16], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0],
    [505, 9], [65490, 16], [65491, 16], [65492, 16], [65493, 16], [65494, 16], [65495, 16],
    [65496, 16], [65497, 16], [65498, 16], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0],
    [506, 9], [65499, 16], [65500, 16], [65501, 16], [65502, 16], [65503, 16], [65504, 16],
    [65505, 16], [65506, 16], [65507, 16], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0],
    [2041, 11], [65508, 16], [65509, 16], [65510, 16], [65511, 16], [65512, 16], [65513, 16],
    [65514, 16], [65515, 16], [65516, 16], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0],
    [16352, 14], [65517, 16], [65518, 16], [65519, 16], [65520, 16], [65521, 16], [65522, 16],
    [65523, 16], [65524, 16], [65525, 16], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [1018, 10],
    [32707, 15], [65526, 16], [65527, 16], [65528, 16], [65529, 16], [65530, 16], [65531, 16],
    [65532, 16], [65533, 16], [65534, 16], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0],
]);

/// stb's `[256][2]` tables from their initialisers: what they list, then
/// zeros, as C fills a partly initialised array.
const fn codes(listed: &[Code]) -> [Code; 256] {
    let mut table = [[0; 2]; 256];
    let mut i = 0;
    while i < listed.len() {
        table[i] = listed[i];
        i += 1;
    }
    table
}

const Y_QUANT: [i32; 64] = [
    16, 11, 10, 16, 24, 40, 51, 61, 12, 12, 14, 19, 26, 58, 60, 55, 14, 13, 16, 24, 40, 57, 69,
    56, 14, 17, 22, 29, 51, 87, 80, 62, 18, 22, 37, 56, 68, 109, 103, 77, 24, 35, 55, 64, 81, 104,
    113, 92, 49, 64, 78, 87, 103, 121, 120, 101, 72, 92, 95, 98, 112, 100, 103, 99,
];
const UV_QUANT: [i32; 64] = [
    17, 18, 24, 47, 99, 99, 99, 99, 18, 21, 26, 66, 99, 99, 99, 99, 24, 26, 56, 99, 99, 99, 99,
    99, 47, 66, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99,
];

/// The AAN scale of each row and column, stb's `aasf`.
const SCALES: [f32; 8] = [
    1.0 * 2.828427125,
    1.387039845 * 2.828427125,
    1.306562965 * 2.828427125,
    1.175875602 * 2.828427125,
    1.0 * 2.828427125,
    0.785694958 * 2.828427125,
    0.541196100 * 2.828427125,
    0.275899379 * 2.828427125,
];

/// The entropy-coded bytes as they are put: stb's `bitBuf` · `bitCnt`.
struct Bits {
    out: Vec<u8>,
    buffer: u32,
    count: u32,
}

impl Bits {
    fn put(&mut self, code: Code) {
        self.count += u32::from(code[1]);
        self.buffer |= u32::from(code[0]) << (24 - self.count);
        while self.count >= 8 {
            let byte = (self.buffer >> 16) as u8;
            self.out.push(byte);
            if byte == 255 {
                self.out.push(0);
            }
            self.buffer <<= 8;
            self.count -= 8;
        }
    }
}

/// `value`'s bits as JPEG codes a coefficient, and how many (stb's
/// `calcBits`).
fn bits_of(value: i32) -> Code {
    let mut magnitude = value.unsigned_abs();
    let value = if value < 0 { value - 1 } else { value };
    let mut length = 1;
    loop {
        magnitude >>= 1;
        if magnitude == 0 {
            break;
        }
        length += 1;
    }
    [(value & ((1 << length) - 1)) as u16, length]
}

/// The AAN forward DCT of the eight values `step` apart from `at`.
fn dct(d: &mut [f32], at: usize, step: usize) {
    let [d0, d1, d2, d3, d4, d5, d6, d7] = std::array::from_fn(|k| d[at + k * step]);

    let tmp0 = d0 + d7;
    let tmp7 = d0 - d7;
    let tmp1 = d1 + d6;
    let tmp6 = d1 - d6;
    let tmp2 = d2 + d5;
    let tmp5 = d2 - d5;
    let tmp3 = d3 + d4;
    let tmp4 = d3 - d4;

    // Even part.
    let tmp10 = tmp0 + tmp3;
    let tmp13 = tmp0 - tmp3;
    let tmp11 = tmp1 + tmp2;
    let tmp12 = tmp1 - tmp2;

    let z1 = (tmp12 + tmp13) * 0.707106781;
    d[at] = tmp10 + tmp11;
    d[at + 4 * step] = tmp10 - tmp11;
    d[at + 2 * step] = tmp13 + z1;
    d[at + 6 * step] = tmp13 - z1;

    // Odd part.
    let tmp10 = tmp4 + tmp5;
    let tmp11 = tmp5 + tmp6;
    let tmp12 = tmp6 + tmp7;

    let z5 = (tmp10 - tmp12) * 0.382683433;
    let z2 = tmp10 * 0.541196100 + z5;
    let z4 = tmp12 * 1.306562965 + z5;
    let z3 = tmp11 * 0.707106781;

    let z11 = tmp7 + z3;
    let z13 = tmp7 - z3;

    d[at + 5 * step] = z13 + z2;
    d[at + 3 * step] = z13 - z2;
    d[at + step] = z11 + z4;
    d[at + 7 * step] = z11 - z4;
}

/// One component's tables: how each coefficient divides, and its codes.
struct Component<'a> {
    divisors: &'a [f32; 64],
    dc: &'a [Code],
    ac: &'a [Code; 256],
}

/// The 8 x 8 block at the start of `block`, rows `stride` apart: its DCT,
/// quantised, put after `dc`, the block before's DC; returns its own.
fn put_block(bits: &mut Bits, block: &mut [f32], stride: usize, of: &Component, dc: i32) -> i32 {
    for row in (0..stride * 8).step_by(stride) {
        dct(block, row, 1);
    }
    for column in 0..8 {
        dct(block, column, stride);
    }
    let mut du = [0i32; 64];
    for (j, &divisor) in of.divisors.iter().enumerate() {
        let v = block[(j / 8) * stride + j % 8] * divisor;
        du[ZIGZAG[j]] = (if v < 0.0 { v - 0.5 } else { v + 0.5 }) as i32;
    }

    let diff = du[0] - dc;
    if diff == 0 {
        bits.put(of.dc[0]);
    } else {
        let code = bits_of(diff);
        bits.put(of.dc[usize::from(code[1])]);
        bits.put(code);
    }
    let end = (1..64).rev().find(|&i| du[i] != 0).unwrap_or(0);
    let mut i = 1;
    while i <= end {
        let start = i;
        while du[i] == 0 {
            i += 1;
        }
        let mut zeros = i - start;
        for _ in 0..zeros >> 4 {
            bits.put(of.ac[0xF0]);
        }
        zeros &= 15;
        let code = bits_of(du[i]);
        bits.put(of.ac[(zeros << 4) + usize::from(code[1])]);
        bits.put(code);
        i += 1;
    }
    if end != 63 {
        bits.put(of.ac[0x00]);
    }
    du[0]
}

/// A picture's pixels as stb samples them: its edge repeated past it.
struct Pixels<'a> {
    rgb: &'a [u8],
    width: usize,
    height: usize,
}

impl Pixels<'_> {
    /// Y, Cb and Cr of pixel (x, y), each centred on 0.
    fn ycc(&self, x: usize, y: usize) -> [f32; 3] {
        let p = (y.min(self.height - 1) * self.width + x.min(self.width - 1)) * 3;
        let [r, g, b] = [0, 1, 2].map(|c| f32::from(self.rgb[p + c]));
        [
            0.29900 * r + 0.58700 * g + 0.11400 * b - 128.0,
            -0.16874 * r - 0.33126 * g + 0.50000 * b,
            0.50000 * r - 0.41869 * g - 0.08131 * b,
        ]
    }

    /// The `side` x `side` square from (x, y): its Y, Cb and Cr planes.
    fn square(&self, x: usize, y: usize, side: usize) -> [Vec<f32>; 3] {
        let mut planes = [(); 3].map(|()| Vec::with_capacity(side * side));
        for row in y..y + side {
            for column in x..x + side {
                for (plane, value) in planes.iter_mut().zip(self.ycc(column, row)) {
                    plane.push(value);
                }
            }
        }
        planes
    }
}

/// The two tables a quality gives: luminance and chrominance divisors,
/// each in row order, as their bytes go in the header (zigzag order).
fn tables(quality: i32) -> ([u8; 64], [u8; 64]) {
    let scale = if quality < 50 { 5000 / quality } else { 200 - quality * 2 };
    let mut luminance = [0; 64];
    let mut chrominance = [0; 64];
    for i in 0..64 {
        luminance[ZIGZAG[i]] = ((Y_QUANT[i] * scale + 50) / 100).clamp(1, 255) as u8;
        chrominance[ZIGZAG[i]] = ((UV_QUANT[i] * scale + 50) / 100).clamp(1, 255) as u8;
    }
    (luminance, chrominance)
}

/// What each coefficient of a block is multiplied by: one over its table
/// entry and its row's and column's scales.
fn divisors(table: &[u8; 64]) -> [f32; 64] {
    std::array::from_fn(|k| {
        1.0 / (f32::from(table[ZIGZAG[k]]) * SCALES[k / 8] * SCALES[k % 8])
    })
}

/// The headers before the scan: JFIF, the two tables, the frame, the four
/// code tables and the scan's own.
fn headers(out: &mut Vec<u8>, picture: &Pixels, subsample: bool, tables: &([u8; 64], [u8; 64])) {
    let (width, height) = (picture.width, picture.height);
    out.extend_from_slice(&[
        0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10, b'J', b'F', b'I', b'F', 0, 1, 1, 0, 0, 1, 0, 1, 0, 0,
        0xFF, 0xDB, 0, 0x84, 0,
    ]);
    out.extend_from_slice(&tables.0);
    out.push(1);
    out.extend_from_slice(&tables.1);
    out.extend_from_slice(&[
        0xFF,
        0xC0,
        0,
        0x11,
        8,
        (height >> 8) as u8,
        height as u8,
        (width >> 8) as u8,
        width as u8,
        3,
        1,
        if subsample { 0x22 } else { 0x11 },
        0,
        2,
        0x11,
        1,
        3,
        0x11,
        1,
        0xFF,
        0xC4,
        0x01,
        0xA2,
        0,
    ]);
    out.extend_from_slice(&DC_LUMINANCE_COUNTS);
    out.extend_from_slice(&DC_LUMINANCE_VALUES);
    out.push(0x10);
    out.extend_from_slice(&AC_LUMINANCE_COUNTS);
    out.extend_from_slice(&AC_LUMINANCE_VALUES);
    out.push(1);
    out.extend_from_slice(&DC_CHROMINANCE_COUNTS);
    out.extend_from_slice(&DC_CHROMINANCE_VALUES);
    out.push(0x11);
    out.extend_from_slice(&AC_CHROMINANCE_COUNTS);
    out.extend_from_slice(&AC_CHROMINANCE_VALUES);
    out.extend_from_slice(&[0xFF, 0xDA, 0, 0xC, 3, 1, 0, 2, 0x11, 3, 0x11, 0, 0x3F, 0]);
}

/// `rgb` — `width` x `height` pixels of three bytes, top row first, at
/// least that many bytes — as a baseline JPEG at `quality`, clamped to
/// 1..=100. Above 90 the chroma keeps every pixel; at 90 and under, one
/// for each 2 x 2.
pub fn encode(rgb: &[u8], width: usize, height: usize, quality: i32) -> Vec<u8> {
    let quality = quality.clamp(1, 100);
    let subsample = quality <= 90;
    let tables = tables(quality);
    let (y_divisors, uv_divisors) = (divisors(&tables.0), divisors(&tables.1));
    let luma = Component { divisors: &y_divisors, dc: &Y_DC, ac: &Y_AC };
    let chroma = Component { divisors: &uv_divisors, dc: &UV_DC, ac: &UV_AC };
    let picture = Pixels { rgb, width, height };

    let mut bits = Bits { out: Vec::new(), buffer: 0, count: 0 };
    headers(&mut bits.out, &picture, subsample, &tables);
    let mut dc = [0i32; 3];
    let side = if subsample { 16 } else { 8 };
    for y in (0..height).step_by(side) {
        for x in (0..width).step_by(side) {
            let [mut lum, mut cb, mut cr] = picture.square(x, y, side);
            if subsample {
                for at in [0, 8, 128, 136] {
                    dc[0] = put_block(&mut bits, &mut lum[at..], 16, &luma, dc[0]);
                }
                let (mut cb, mut cr) = (quartered(&cb), quartered(&cr));
                dc[1] = put_block(&mut bits, &mut cb, 8, &chroma, dc[1]);
                dc[2] = put_block(&mut bits, &mut cr, 8, &chroma, dc[2]);
            } else {
                dc[0] = put_block(&mut bits, &mut lum, 8, &luma, dc[0]);
                dc[1] = put_block(&mut bits, &mut cb, 8, &chroma, dc[1]);
                dc[2] = put_block(&mut bits, &mut cr, 8, &chroma, dc[2]);
            }
        }
    }
    bits.put([0x7F, 7]);
    bits.out.extend_from_slice(&[0xFF, 0xD9]);
    bits.out
}

/// A 16 x 16 chroma square as one 8 x 8 block: each 2 x 2 averaged.
fn quartered(plane: &[f32]) -> [f32; 64] {
    std::array::from_fn(|pos| {
        let j = (pos / 8) * 32 + (pos % 8) * 2;
        (plane[j] + plane[j + 1] + plane[j + 16] + plane[j + 17]) * 0.25
    })
}
