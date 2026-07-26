///|
/// Version tag for Cire's first deterministic source-content fingerprint.
pub const CONTENT_HASH_ALGORITHM : String = "cire-fnv1a64-utf8-v1"

///|
/// Computes a deterministic FNV-1a 64-bit fingerprint over the UTF-8 encoding
/// of decoded source text.
///
/// This is an identity/checksum for artifacts and incremental caches, not a
/// cryptographic integrity primitive. Changing its encoding or algorithm
/// requires a new version tag.
pub fn content_hash(text : String) -> String {
  let mut hash = 14695981039346656037UL
  let mut cursor = 0
  while cursor < text.length() {
    guard text.get_char(cursor) is Some(char) else { break }
    let scalar = char.to_int()
    if scalar <= 0x7f {
      hash = fnv1a_byte(hash, scalar)
    } else if scalar <= 0x7ff {
      hash = fnv1a_byte(hash, 0xc0 | (scalar >> 6))
      hash = fnv1a_byte(hash, 0x80 | (scalar & 0x3f))
    } else if scalar <= 0xffff {
      hash = fnv1a_byte(hash, 0xe0 | (scalar >> 12))
      hash = fnv1a_byte(hash, 0x80 | ((scalar >> 6) & 0x3f))
      hash = fnv1a_byte(hash, 0x80 | (scalar & 0x3f))
    } else {
      hash = fnv1a_byte(hash, 0xf0 | (scalar >> 18))
      hash = fnv1a_byte(hash, 0x80 | ((scalar >> 12) & 0x3f))
      hash = fnv1a_byte(hash, 0x80 | ((scalar >> 6) & 0x3f))
      hash = fnv1a_byte(hash, 0x80 | (scalar & 0x3f))
    }
    cursor = cursor + char.utf16_len()
  }
  let hex = hash.to_string(radix=16)
  let padded = if hex.length() < 16 {
    "0".repeat(16 - hex.length()) + hex
  } else {
    hex
  }
  "\{CONTENT_HASH_ALGORITHM}:\{padded}"
}

///|
fn fnv1a_byte(hash : UInt64, byte : Int) -> UInt64 {
  (hash ^ byte.to_uint64()) * 1099511628211UL
}
