//! A JPEG decoded whole by zune-jpeg, its rows handed out as they show: a
//! row at a time, straight RGBA8, turned by the file's EXIF orientation.

use zune_core::bytestream::ZCursor;
use zune_core::colorspace::ColorSpace;
use zune_core::options::DecoderOptions;
use zune_jpeg::JpegDecoder;

/// A JPEG's pixels as the file holds them: RGB, `width` × `height` as
/// they were coded, row after row — and the orientation its EXIF names
/// them shown in.
pub struct Decoded {
    rgb: Vec<u8>,
    width: usize,
    height: usize,
    orientation: u16,
}

impl Decoded {
    /// `bytes`, a JPEG file, decoded — or why not. Any side a JPEG can
    /// say (65,535): ⚠️zune's own ceiling is 16,384, and a picture past
    /// that is what the app reads itself for (`cel_picture.dart`).
    pub fn of(bytes: &[u8]) -> Result<Self, String> {
        let options = DecoderOptions::default()
            .jpeg_set_out_colorspace(ColorSpace::RGB)
            .set_max_width(usize::from(u16::MAX))
            .set_max_height(usize::from(u16::MAX));
        let mut decoder = JpegDecoder::new_with_options(ZCursor::new(bytes), options);
        let rgb = decoder.decode().map_err(|why| format!("JPEG: {why:?}"))?;
        let info = decoder.info().ok_or("JPEG: no header")?;
        let (width, height) = (usize::from(info.width), usize::from(info.height));
        if rgb.len() != width * height * 3 {
            return Err(format!("JPEG: {} bytes for {width}x{height} RGB", rgb.len()));
        }
        let orientation = decoder.exif().map_or(1, |exif| orientation_of(exif));
        Ok(Self { rgb, width, height, orientation })
    }

    /// The picture's size as it shows: its sides swapped where the
    /// orientation turns it a quarter (EXIF 5 to 8).
    pub fn shown(&self) -> (usize, usize) {
        if (5..=8).contains(&self.orientation) {
            (self.height, self.width)
        } else {
            (self.width, self.height)
        }
    }

    /// Row `y` of the picture as it shows into `rgba`, straight RGBA8 and
    /// opaque: what the image package's JPEG decoder laid there
    /// (`getImageFromJpeg` — the pixel it moves each coded one to, read
    /// back the other way). False where `y` is past it or `rgba` is not a
    /// row of it.
    pub fn row(&self, y: usize, rgba: &mut [u8]) -> bool {
        let (shown_width, shown_height) = self.shown();
        if y >= shown_height || rgba.len() != shown_width * 4 {
            return false;
        }
        if !(2..=8).contains(&self.orientation) {
            let coded = &self.rgb[y * self.width * 3..][..self.width * 3];
            for (to, from) in rgba.chunks_exact_mut(4).zip(coded.chunks_exact(3)) {
                to.copy_from_slice(&[from[0], from[1], from[2], 255]);
            }
            return true;
        }
        for (x, to) in rgba.chunks_exact_mut(4).enumerate() {
            let (from_x, from_y) = self.coded_at(x, y);
            let from = &self.rgb[(from_y * self.width + from_x) * 3..][..3];
            to.copy_from_slice(&[from[0], from[1], from[2], 255]);
        }
        true
    }

    /// The coded pixel that shows at (`x`, `y`).
    fn coded_at(&self, x: usize, y: usize) -> (usize, usize) {
        let (last_x, last_y) = (self.width - 1, self.height - 1);
        match self.orientation {
            2 => (last_x - x, y),
            3 => (last_x - x, last_y - y),
            4 => (x, last_y - y),
            5 => (y, x),
            6 => (y, last_y - x),
            7 => (last_x - y, last_y - x),
            8 => (last_x - y, x),
            _ => (x, y),
        }
    }
}

/// The orientation EXIF `exif` names — its first IFD's tag 0x0112 — or
/// 1 (as coded) where it names none it can be read as. The TIFF header
/// first, `Exif\0\0` before it or not.
pub(crate) fn orientation_of(exif: &[u8]) -> u16 {
    let tiff = exif.strip_prefix(b"Exif\0\0").unwrap_or(exif);
    let big = match tiff.get(..4) {
        Some(b"MM\0*") => true,
        Some(b"II*\0") => false,
        _ => return 1,
    };
    let u16_at = |at: usize| {
        let bytes: [u8; 2] = tiff.get(at..at + 2)?.try_into().ok()?;
        Some(if big { u16::from_be_bytes(bytes) } else { u16::from_le_bytes(bytes) })
    };
    let u32_at = |at: usize| {
        let bytes: [u8; 4] = tiff.get(at..at + 4)?.try_into().ok()?;
        Some(if big { u32::from_be_bytes(bytes) } else { u32::from_le_bytes(bytes) })
    };
    let Some(ifd) = u32_at(4).map(|at| at as usize) else {
        return 1;
    };
    let entries = u16_at(ifd).unwrap_or(0);
    (0..usize::from(entries))
        .map(|entry| ifd + 2 + entry * 12)
        .find(|&at| u16_at(at) == Some(0x0112))
        .and_then(|at| u16_at(at + 8))
        .unwrap_or(1)
}
