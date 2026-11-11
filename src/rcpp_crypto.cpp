#include <Rcpp.h>
#include "rcpp_crypto.h"

namespace dicomtk {
namespace crypto {

namespace {

// SHA-256 constants
const uint32_t K256[64] = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

inline uint32_t rotr32(uint32_t x, uint32_t n) {
  return (x >> n) | (x << (32 - n));
}

inline uint32_t ch(uint32_t x, uint32_t y, uint32_t z) {
  return (x & y) ^ (~x & z);
}

inline uint32_t maj(uint32_t x, uint32_t y, uint32_t z) {
  return (x & y) ^ (x & z) ^ (y & z);
}

inline uint32_t ep0(uint32_t x) {
  return rotr32(x, 2) ^ rotr32(x, 13) ^ rotr32(x, 22);
}

inline uint32_t ep1(uint32_t x) {
  return rotr32(x, 6) ^ rotr32(x, 11) ^ rotr32(x, 25);
}

inline uint32_t sig0(uint32_t x) {
  return rotr32(x, 7) ^ rotr32(x, 18) ^ (x >> 3);
}

inline uint32_t sig1(uint32_t x) {
  return rotr32(x, 17) ^ rotr32(x, 19) ^ (x >> 10);
}

void sha256_transform(uint32_t state[8], const uint8_t data[64]) {
  uint32_t m[64];
  for (int i = 0; i < 16; ++i) {
    m[i] = (static_cast<uint32_t>(data[i * 4]) << 24) |
           (static_cast<uint32_t>(data[i * 4 + 1]) << 16) |
           (static_cast<uint32_t>(data[i * 4 + 2]) << 8) |
           (static_cast<uint32_t>(data[i * 4 + 3]));
  }
  for (int i = 16; i < 64; ++i) {
    m[i] = sig1(m[i - 2]) + m[i - 7] + sig0(m[i - 15]) + m[i - 16];
  }

  uint32_t a = state[0], b = state[1], c = state[2], d = state[3];
  uint32_t e = state[4], f = state[5], g = state[6], h = state[7];

  for (int i = 0; i < 64; ++i) {
    uint32_t t1 = h + ep1(e) + ch(e, f, g) + K256[i] + m[i];
    uint32_t t2 = ep0(a) + maj(a, b, c);
    h = g;
    g = f;
    f = e;
    e = d + t1;
    d = c;
    c = b;
    b = a;
    a = t1 + t2;
  }

  state[0] += a;
  state[1] += b;
  state[2] += c;
  state[3] += d;
  state[4] += e;
  state[5] += f;
  state[6] += g;
  state[7] += h;
}

} // namespace

void sha256_init(SHA256Context& ctx) {
  ctx.state[0] = 0x6a09e667;
  ctx.state[1] = 0xbb67ae85;
  ctx.state[2] = 0x3c6ef372;
  ctx.state[3] = 0xa54ff53a;
  ctx.state[4] = 0x510e527f;
  ctx.state[5] = 0x9b05688c;
  ctx.state[6] = 0x1f83d9ab;
  ctx.state[7] = 0x5be0cd19;
  ctx.count = 0;
}

void sha256_update(SHA256Context& ctx, const uint8_t* data, size_t len) {
  size_t idx = static_cast<size_t>(ctx.count % 64);
  ctx.count += len;
  size_t part_len = 64 - idx;
  size_t i = 0;

  if (len >= part_len) {
    std::memcpy(&ctx.buffer[idx], data, part_len);
    sha256_transform(ctx.state, ctx.buffer);
    for (i = part_len; i + 63 < len; i += 64) {
      sha256_transform(ctx.state, &data[i]);
    }
    idx = 0;
  }
  if (i < len) {
    std::memcpy(&ctx.buffer[idx], &data[i], len - i);
  }
}

void sha256_final(SHA256Context& ctx, uint8_t digest[32]) {
  uint64_t total_bits = ctx.count * 8;
  size_t idx = static_cast<size_t>(ctx.count % 64);
  ctx.buffer[idx++] = 0x80;

  if (idx > 56) {
    std::memset(&ctx.buffer[idx], 0, 64 - idx);
    sha256_transform(ctx.state, ctx.buffer);
    std::memset(ctx.buffer, 0, 56);
  } else {
    std::memset(&ctx.buffer[idx], 0, 56 - idx);
  }

  for (int i = 7; i >= 0; --i) {
    ctx.buffer[56 + (7 - i)] = static_cast<uint8_t>((total_bits >> (i * 8)) & 0xFF);
  }
  sha256_transform(ctx.state, ctx.buffer);

  for (int i = 0; i < 8; ++i) {
    digest[i * 4]     = static_cast<uint8_t>((ctx.state[i] >> 24) & 0xFF);
    digest[i * 4 + 1] = static_cast<uint8_t>((ctx.state[i] >> 16) & 0xFF);
    digest[i * 4 + 2] = static_cast<uint8_t>((ctx.state[i] >> 8) & 0xFF);
    digest[i * 4 + 3] = static_cast<uint8_t>(ctx.state[i] & 0xFF);
  }
}

std::array<uint8_t, 32> sha256(const uint8_t* data, size_t len) {
  SHA256Context ctx;
  sha256_init(ctx);
  sha256_update(ctx, data, len);
  std::array<uint8_t, 32> digest;
  sha256_final(ctx, digest.data());
  return digest;
}

std::array<uint8_t, 32> hmac_sha256(const uint8_t* key, size_t key_len,
                                    const uint8_t* data, size_t data_len) {
  uint8_t k_pad[64];
  std::memset(k_pad, 0, sizeof(k_pad));

  if (key_len > 64) {
    auto kd = sha256(key, key_len);
    std::memcpy(k_pad, kd.data(), 32);
  } else {
    if (key_len > 0) {
      std::memcpy(k_pad, key, key_len);
    }
  }

  uint8_t k_ipad[64];
  uint8_t k_opad[64];
  for (int i = 0; i < 64; ++i) {
    k_ipad[i] = k_pad[i] ^ 0x36;
    k_opad[i] = k_pad[i] ^ 0x5c;
  }

  SHA256Context ctx;
  sha256_init(ctx);
  sha256_update(ctx, k_ipad, 64);
  if (data_len > 0) {
    sha256_update(ctx, data, data_len);
  }
  uint8_t inner_hash[32];
  sha256_final(ctx, inner_hash);

  sha256_init(ctx);
  sha256_update(ctx, k_opad, 64);
  sha256_update(ctx, inner_hash, 32);
  std::array<uint8_t, 32> result;
  sha256_final(ctx, result.data());
  return result;
}

std::vector<uint8_t> pbkdf2_hmac_sha256(const uint8_t* pass, size_t pass_len,
                                        const uint8_t* salt, size_t salt_len,
                                        uint32_t iterations, size_t dk_len) {
  if (iterations == 0) iterations = 1;
  std::vector<uint8_t> dk;
  dk.reserve(dk_len);

  uint32_t block_index = 1;
  while (dk.size() < dk_len) {
    std::vector<uint8_t> salt_block;
    salt_block.reserve(salt_len + 4);
    if (salt_len > 0) {
      salt_block.insert(salt_block.end(), salt, salt + salt_len);
    }
    salt_block.push_back(static_cast<uint8_t>((block_index >> 24) & 0xFF));
    salt_block.push_back(static_cast<uint8_t>((block_index >> 16) & 0xFF));
    salt_block.push_back(static_cast<uint8_t>((block_index >> 8) & 0xFF));
    salt_block.push_back(static_cast<uint8_t>(block_index & 0xFF));

    auto u = hmac_sha256(pass, pass_len, salt_block.data(), salt_block.size());
    auto t = u;

    for (uint32_t c = 1; c < iterations; ++c) {
      u = hmac_sha256(pass, pass_len, u.data(), u.size());
      for (size_t b = 0; b < 32; ++b) {
        t[b] ^= u[b];
      }
    }

    size_t to_copy = std::min<size_t>(32, dk_len - dk.size());
    dk.insert(dk.end(), t.begin(), t.begin() + to_copy);
    block_index++;
  }
  return dk;
}

std::array<uint8_t, 32> hkdf_extract(const uint8_t* salt, size_t salt_len,
                                     const uint8_t* ikm, size_t ikm_len) {
  const uint8_t default_salt[32] = {0};
  if (salt_len == 0 || salt == nullptr) {
    salt = default_salt;
    salt_len = 32;
  }
  return hmac_sha256(salt, salt_len, ikm, ikm_len);
}

std::vector<uint8_t> hkdf_expand(const uint8_t* prk, size_t prk_len,
                                 const uint8_t* info, size_t info_len,
                                 size_t okm_len) {
  size_t n = (okm_len + 31) / 32;
  if (n > 255) {
    throw std::invalid_argument("HKDF okm_len too large");
  }

  std::vector<uint8_t> okm;
  okm.reserve(okm_len);
  std::vector<uint8_t> prev_t;

  for (size_t i = 1; i <= n; ++i) {
    std::vector<uint8_t> step_input;
    step_input.reserve(prev_t.size() + info_len + 1);
    step_input.insert(step_input.end(), prev_t.begin(), prev_t.end());
    if (info_len > 0 && info != nullptr) {
      step_input.insert(step_input.end(), info, info + info_len);
    }
    step_input.push_back(static_cast<uint8_t>(i));

    auto t = hmac_sha256(prk, prk_len, step_input.data(), step_input.size());
    prev_t.assign(t.begin(), t.end());

    size_t to_copy = std::min<size_t>(32, okm_len - okm.size());
    okm.insert(okm.end(), t.begin(), t.begin() + to_copy);
  }
  return okm;
}

std::vector<uint8_t> hkdf_sha256(const uint8_t* ikm, size_t ikm_len,
                                 const uint8_t* salt, size_t salt_len,
                                 const uint8_t* info, size_t info_len,
                                 size_t okm_len) {
  auto prk = hkdf_extract(salt, salt_len, ikm, ikm_len);
  return hkdf_expand(prk.data(), prk.size(), info, info_len, okm_len);
}

// -----------------------------------------------------------------------------
// ChaCha20 and Poly1305 (RFC 8439)
// -----------------------------------------------------------------------------

namespace {

inline uint32_t rotl32(uint32_t v, int c) {
  return (v << c) | (v >> (32 - c));
}

inline void qround(uint32_t& a, uint32_t& b, uint32_t& c, uint32_t& d) {
  a += b; d ^= a; d = rotl32(d, 16);
  c += d; b ^= c; b = rotl32(b, 12);
  a += b; d ^= a; d = rotl32(d, 8);
  c += d; b ^= c; b = rotl32(b, 7);
}

inline uint32_t load32_le(const uint8_t* p) {
  return static_cast<uint32_t>(p[0]) |
         (static_cast<uint32_t>(p[1]) << 8) |
         (static_cast<uint32_t>(p[2]) << 16) |
         (static_cast<uint32_t>(p[3]) << 24);
}

inline void store32_le(uint8_t* p, uint32_t v) {
  p[0] = static_cast<uint8_t>(v & 0xFF);
  p[1] = static_cast<uint8_t>((v >> 8) & 0xFF);
  p[2] = static_cast<uint8_t>((v >> 16) & 0xFF);
  p[3] = static_cast<uint8_t>((v >> 24) & 0xFF);
}

inline void store64_le(uint8_t* p, uint64_t v) {
  store32_le(p, static_cast<uint32_t>(v & 0xFFFFFFFF));
  store32_le(p + 4, static_cast<uint32_t>(v >> 32));
}

void chacha20_block(const uint8_t key[32], uint32_t counter, const uint8_t nonce[12], uint8_t output[64]) {
  uint32_t state[16];
  state[0] = 0x61707865;
  state[1] = 0x3320646e;
  state[2] = 0x79622d32;
  state[3] = 0x6b206574;
  for (int i = 0; i < 8; ++i) {
    state[4 + i] = load32_le(key + i * 4);
  }
  state[12] = counter;
  state[13] = load32_le(nonce);
  state[14] = load32_le(nonce + 4);
  state[15] = load32_le(nonce + 8);

  uint32_t x[16];
  std::memcpy(x, state, sizeof(state));

  for (int i = 0; i < 10; ++i) {
    qround(x[0], x[4],  x[8], x[12]);
    qround(x[1], x[5],  x[9], x[13]);
    qround(x[2], x[6], x[10], x[14]);
    qround(x[3], x[7], x[11], x[15]);

    qround(x[0], x[5], x[10], x[15]);
    qround(x[1], x[6],  x[8], x[12]);
    qround(x[2], x[7],  x[9], x[13]);
    qround(x[3], x[4], x[11], x[14]);
  }

  for (int i = 0; i < 16; ++i) {
    store32_le(output + i * 4, x[i] + state[i]);
  }
}

void chacha20_xor(const uint8_t key[32], uint32_t counter, const uint8_t nonce[12],
                  const uint8_t* in, size_t in_len, uint8_t* out) {
  uint8_t block[64];
  size_t offset = 0;
  while (offset < in_len) {
    chacha20_block(key, counter++, nonce, block);
    size_t to_xor = std::min<size_t>(64, in_len - offset);
    for (size_t i = 0; i < to_xor; ++i) {
      out[offset + i] = in[offset + i] ^ block[i];
    }
    offset += to_xor;
  }
}

// Pure ISO C++17 Poly1305 (RFC 8439) using 5 x 26-bit limbs in uint64_t
void poly1305_mac(const uint8_t* msg, size_t msg_len, const uint8_t key[32], uint8_t tag[16]) {
  uint8_t r_bytes[16];
  std::memcpy(r_bytes, key, 16);
  r_bytes[3]  &= 15;
  r_bytes[7]  &= 15;
  r_bytes[11] &= 15;
  r_bytes[15] &= 15;
  r_bytes[4]  &= 252;
  r_bytes[8]  &= 252;
  r_bytes[12] &= 252;

  uint32_t rt0 = load32_le(r_bytes + 0);
  uint32_t rt1 = load32_le(r_bytes + 4);
  uint32_t rt2 = load32_le(r_bytes + 8);
  uint32_t rt3 = load32_le(r_bytes + 12);

  uint64_t r0 = rt0 & 0x3ffffffULL;
  uint64_t r1 = ((rt0 >> 26) | (rt1 << 6)) & 0x3ffffffULL;
  uint64_t r2 = ((rt1 >> 20) | (rt2 << 12)) & 0x3ffffffULL;
  uint64_t r3 = ((rt2 >> 14) | (rt3 << 18)) & 0x3ffffffULL;
  uint64_t r4 = (rt3 >> 8);

  uint64_t s1 = r1 * 5;
  uint64_t s2 = r2 * 5;
  uint64_t s3 = r3 * 5;
  uint64_t s4 = r4 * 5;

  uint64_t h0 = 0, h1 = 0, h2 = 0, h3 = 0, h4 = 0;

  size_t offset = 0;
  while (offset < msg_len) {
    size_t block_len = std::min<size_t>(16, msg_len - offset);
    uint8_t block[16] = {0};
    std::memcpy(block, msg + offset, block_len);
    uint64_t hibit = (block_len == 16) ? (1ULL << 24) : 0ULL;
    if (block_len < 16) {
      block[block_len] = 0x01;
    }

    uint32_t t0 = load32_le(block + 0);
    uint32_t t1 = load32_le(block + 4);
    uint32_t t2 = load32_le(block + 8);
    uint32_t t3 = load32_le(block + 12);

    h0 += t0 & 0x3ffffffULL;
    h1 += ((t0 >> 26) | (t1 << 6)) & 0x3ffffffULL;
    h2 += ((t1 >> 20) | (t2 << 12)) & 0x3ffffffULL;
    h3 += ((t2 >> 14) | (t3 << 18)) & 0x3ffffffULL;
    h4 += (t3 >> 8) | hibit;

    uint64_t d0 = h0 * r0 + h1 * s4 + h2 * s3 + h3 * s2 + h4 * s1;
    uint64_t d1 = h0 * r1 + h1 * r0 + h2 * s4 + h3 * s3 + h4 * s2;
    uint64_t d2 = h0 * r2 + h1 * r1 + h2 * r0 + h3 * s4 + h4 * s3;
    uint64_t d3 = h0 * r3 + h1 * r2 + h2 * r1 + h3 * r0 + h4 * s4;
    uint64_t d4 = h0 * r4 + h1 * r3 + h2 * r2 + h3 * r1 + h4 * r0;

    uint64_t c = d0 >> 26; h0 = d0 & 0x3ffffffULL;
    d1 += c;     c = d1 >> 26; h1 = d1 & 0x3ffffffULL;
    d2 += c;     c = d2 >> 26; h2 = d2 & 0x3ffffffULL;
    d3 += c;     c = d3 >> 26; h3 = d3 & 0x3ffffffULL;
    d4 += c;     c = d4 >> 26; h4 = d4 & 0x3ffffffULL;
    h0 += c * 5; c = h0 >> 26; h0 &= 0x3ffffffULL;
    h1 += c;

    offset += block_len;
  }

  // Final carry propagation and modular reduction mod 2^130 - 5
  uint64_t c = h1 >> 26; h1 &= 0x3ffffffULL;
  h2 += c;     c = h2 >> 26; h2 &= 0x3ffffffULL;
  h3 += c;     c = h3 >> 26; h3 &= 0x3ffffffULL;
  h4 += c;     c = h4 >> 26; h4 &= 0x3ffffffULL;
  h0 += c * 5; c = h0 >> 26; h0 &= 0x3ffffffULL;
  h1 += c;

  uint64_t g0 = h0 + 5; c = g0 >> 26; g0 &= 0x3ffffffULL;
  uint64_t g1 = h1 + c; c = g1 >> 26; g1 &= 0x3ffffffULL;
  uint64_t g2 = h2 + c; c = g2 >> 26; g2 &= 0x3ffffffULL;
  uint64_t g3 = h3 + c; c = g3 >> 26; g3 &= 0x3ffffffULL;
  uint64_t g4 = h4 + c - (1ULL << 26);

  uint64_t mask = (g4 >> 63) - 1ULL;
  g0 &= mask; g1 &= mask; g2 &= mask; g3 &= mask; g4 &= mask;
  mask = ~mask;
  h0 = (h0 & mask) | g0;
  h1 = (h1 & mask) | g1;
  h2 = (h2 & mask) | g2;
  h3 = (h3 & mask) | g3;
  h4 = (h4 & mask) | g4;

  uint64_t w0 = ((h0)       | (h1 << 26)) & 0xffffffffULL;
  uint64_t w1 = ((h1 >> 6)  | (h2 << 20)) & 0xffffffffULL;
  uint64_t w2 = ((h2 >> 12) | (h3 << 14)) & 0xffffffffULL;
  uint64_t w3 = ((h3 >> 18) | (h4 << 8))  & 0xffffffffULL;

  uint64_t f = w0 + load32_le(key + 16);
  store32_le(tag + 0, static_cast<uint32_t>(f));
  f = w1 + load32_le(key + 20) + (f >> 32);
  store32_le(tag + 4, static_cast<uint32_t>(f));
  f = w2 + load32_le(key + 24) + (f >> 32);
  store32_le(tag + 8, static_cast<uint32_t>(f));
  f = w3 + load32_le(key + 28) + (f >> 32);
  store32_le(tag + 12, static_cast<uint32_t>(f));
}

} // namespace

std::vector<uint8_t> chacha20_poly1305_encrypt(const uint8_t* key,
                                               const uint8_t* plaintext, size_t pt_len,
                                               const uint8_t* aad, size_t aad_len) {
  // Generate random 12-byte nonce
  uint8_t nonce[12];
  std::random_device rd;
  for (int i = 0; i < 3; ++i) {
    uint32_t r = rd();
    store32_le(nonce + i * 4, r);
  }

  // Derive Poly1305 key from chacha20 block with counter = 0
  uint8_t otk[64];
  chacha20_block(key, 0, nonce, otk);

  // Encrypt plaintext with ChaCha20 starting at counter = 1
  std::vector<uint8_t> ciphertext(pt_len);
  if (pt_len > 0) {
    chacha20_xor(key, 1, nonce, plaintext, pt_len, ciphertext.data());
  }

  // Construct Poly1305 message:
  // AAD || pad16(AAD) || ciphertext || pad16(ciphertext) || len64(AAD) || len64(ciphertext)
  size_t aad_pad = (16 - (aad_len % 16)) % 16;
  size_t ct_pad = (16 - (pt_len % 16)) % 16;
  size_t mac_data_len = aad_len + aad_pad + pt_len + ct_pad + 16;
  std::vector<uint8_t> mac_data(mac_data_len, 0);

  size_t pos = 0;
  if (aad_len > 0) {
    std::memcpy(&mac_data[pos], aad, aad_len);
  }
  pos += aad_len + aad_pad;

  if (pt_len > 0) {
    std::memcpy(&mac_data[pos], ciphertext.data(), pt_len);
  }
  pos += pt_len + ct_pad;

  store64_le(&mac_data[pos], static_cast<uint64_t>(aad_len));
  pos += 8;
  store64_le(&mac_data[pos], static_cast<uint64_t>(pt_len));

  // Compute 16-byte Poly1305 tag
  uint8_t tag[16];
  poly1305_mac(mac_data.data(), mac_data.size(), otk, tag);

  // Output format: nonce (12) || ciphertext (pt_len) || tag (16)
  std::vector<uint8_t> result;
  result.reserve(12 + pt_len + 16);
  result.insert(result.end(), nonce, nonce + 12);
  result.insert(result.end(), ciphertext.begin(), ciphertext.end());
  result.insert(result.end(), tag, tag + 16);
  return result;
}

std::vector<uint8_t> chacha20_poly1305_decrypt(const uint8_t* key,
                                               const uint8_t* ciphertext_with_nonce_tag, size_t ct_len,
                                               const uint8_t* aad, size_t aad_len) {
  if (ct_len < 28) {
    throw std::runtime_error("ChaCha20-Poly1305 ciphertext too short (minimum 28 bytes required)");
  }

  const uint8_t* nonce = ciphertext_with_nonce_tag;
  size_t cipher_len = ct_len - 28;
  const uint8_t* ciphertext = ciphertext_with_nonce_tag + 12;
  const uint8_t* received_tag = ciphertext_with_nonce_tag + 12 + cipher_len;

  // Derive Poly1305 key
  uint8_t otk[64];
  chacha20_block(key, 0, nonce, otk);

  // Construct Poly1305 input
  size_t aad_pad = (16 - (aad_len % 16)) % 16;
  size_t ct_pad = (16 - (cipher_len % 16)) % 16;
  size_t mac_data_len = aad_len + aad_pad + cipher_len + ct_pad + 16;
  std::vector<uint8_t> mac_data(mac_data_len, 0);

  size_t pos = 0;
  if (aad_len > 0) {
    std::memcpy(&mac_data[pos], aad, aad_len);
  }
  pos += aad_len + aad_pad;

  if (cipher_len > 0) {
    std::memcpy(&mac_data[pos], ciphertext, cipher_len);
  }
  pos += cipher_len + ct_pad;

  store64_le(&mac_data[pos], static_cast<uint64_t>(aad_len));
  pos += 8;
  store64_le(&mac_data[pos], static_cast<uint64_t>(cipher_len));

  uint8_t expected_tag[16];
  poly1305_mac(mac_data.data(), mac_data.size(), otk, expected_tag);

  // Constant-time tag verification
  if (!ct_memeq(expected_tag, received_tag, 16)) {
    throw std::runtime_error("ChaCha20-Poly1305 authentication failed: message corrupted or tampered");
  }

  // Decrypt ciphertext
  std::vector<uint8_t> plaintext(cipher_len);
  if (cipher_len > 0) {
    chacha20_xor(key, 1, nonce, ciphertext, cipher_len, plaintext.data());
  }
  return plaintext;
}

std::string hmac_dicom_uid(const std::array<uint8_t, 32>& uid_key, const std::string& orig_uid) {
  // Trim leading/trailing whitespace and NUL bytes
  size_t start = 0;
  while (start < orig_uid.size() &&
         (orig_uid[start] == ' ' || orig_uid[start] == '\0' || orig_uid[start] == '\r' ||
          orig_uid[start] == '\n' || orig_uid[start] == '\t')) {
    start++;
  }
  size_t end = orig_uid.size();
  while (end > start &&
         (orig_uid[end - 1] == ' ' || orig_uid[end - 1] == '\0' || orig_uid[end - 1] == '\r' ||
          orig_uid[end - 1] == '\n' || orig_uid[end - 1] == '\t')) {
    end--;
  }
  if (start >= end) {
    return "";
  }
  std::string trimmed = orig_uid.substr(start, end - start);

  // Standard DICOM UIDs starting with 1.2.840.10008. are preserved
  const std::string dcm_prefix = "1.2.840.10008.";
  if (trimmed.compare(0, dcm_prefix.size(), dcm_prefix) == 0) {
    return trimmed;
  }

  auto mac = hmac_sha256(uid_key.data(), uid_key.size(),
                         reinterpret_cast<const uint8_t*>(trimmed.data()), trimmed.size());

  // Extract 128-bit integer (first 16 bytes of HMAC) and convert to decimal string
  std::array<uint8_t, 16> num;
  std::memcpy(num.data(), mac.data(), 16);

  std::string digits;
  while (true) {
    bool all_zero = true;
    for (int i = 0; i < 16; ++i) {
      if (num[i] != 0) {
        all_zero = false;
        break;
      }
    }
    if (all_zero) break;

    uint32_t rem = 0;
    for (int i = 0; i < 16; ++i) {
      uint32_t cur = (rem << 8) | static_cast<uint32_t>(num[i]);
      num[i] = static_cast<uint8_t>(cur / 10);
      rem = cur % 10;
    }
    digits.push_back(static_cast<char>('0' + rem));
  }

  if (digits.empty()) {
    digits = "1";
  }
  std::reverse(digits.begin(), digits.end());

  std::string res = "2.25." + digits;
  if (res.size() > 64) {
    res.resize(64);
  }
  return res;
}

int hmac_patient_shift_days(const std::array<uint8_t, 32>& date_key,
                            const std::string& patient_id,
                            int min_days, int max_days) {
  if (min_days > max_days) {
    std::swap(min_days, max_days);
  }
  if (min_days == max_days) {
    return min_days;
  }

  auto mac = hmac_sha256(date_key.data(), date_key.size(),
                         reinterpret_cast<const uint8_t*>(patient_id.data()), patient_id.size());

  uint64_t val = 0;
  for (int i = 0; i < 8; ++i) {
    val = (val << 8) | static_cast<uint64_t>(mac[i]);
  }

  uint64_t range = static_cast<uint64_t>(static_cast<int64_t>(max_days) - static_cast<int64_t>(min_days) + 1);
  uint64_t offset = val % range;
  return min_days + static_cast<int>(offset);
}

std::string sha256_file_hex(const std::string& filepath) {
  std::ifstream ifs(filepath, std::ios::binary);
  if (!ifs) {
    Rcpp::stop("Cannot open file for SHA-256 calculation: " + filepath);
  }
  SHA256Context ctx;
  sha256_init(ctx);
  std::vector<uint8_t> buffer(65536);
  while (ifs.read(reinterpret_cast<char*>(buffer.data()), buffer.size()) || ifs.gcount() > 0) {
    sha256_update(ctx, buffer.data(), static_cast<size_t>(ifs.gcount()));
  }
  uint8_t digest[32];
  sha256_final(ctx, digest);
  return to_hex(digest, 32);
}

std::string to_hex(const uint8_t* data, size_t len) {
  static const char hex_chars[] = "0123456789abcdef";
  std::string s;
  s.reserve(len * 2);
  for (size_t i = 0; i < len; ++i) {
    s.push_back(hex_chars[(data[i] >> 4) & 0x0F]);
    s.push_back(hex_chars[data[i] & 0x0F]);
  }
  return s;
}

std::vector<uint8_t> from_hex(const std::string& hex) {
  std::vector<uint8_t> out;
  if (hex.size() % 2 != 0) return out;
  out.reserve(hex.size() / 2);
  for (size_t i = 0; i < hex.size(); i += 2) {
    char h1 = hex[i];
    char h2 = hex[i + 1];
    auto val = [](char c) -> int {
      if (c >= '0' && c <= '9') return c - '0';
      if (c >= 'a' && c <= 'f') return c - 'a' + 10;
      if (c >= 'A' && c <= 'F') return c - 'A' + 10;
      return 0;
    };
    out.push_back(static_cast<uint8_t>((val(h1) << 4) | val(h2)));
  }
  return out;
}

} // namespace crypto
} // namespace dicomtk

// =============================================================================
// Rcpp Exported Functions
// =============================================================================

// [[Rcpp::export]]
std::string cpp_hmac_sha256_hex(Rcpp::RawVector key, Rcpp::RawVector data) {
  auto mac = dicomtk::crypto::hmac_sha256(
    reinterpret_cast<const uint8_t*>(RAW(key)), key.size(),
    reinterpret_cast<const uint8_t*>(RAW(data)), data.size()
  );
  return dicomtk::crypto::to_hex(mac.data(), 32);
}

// [[Rcpp::export]]
Rcpp::RawVector cpp_pbkdf2_sha256(Rcpp::RawVector password, Rcpp::RawVector salt,
                                  int iterations, int dk_len) {
  if (iterations <= 0) iterations = 1;
  if (dk_len <= 0) dk_len = 32;
  auto out = dicomtk::crypto::pbkdf2_hmac_sha256(
    reinterpret_cast<const uint8_t*>(RAW(password)), password.size(),
    reinterpret_cast<const uint8_t*>(RAW(salt)), salt.size(),
    static_cast<uint32_t>(iterations), static_cast<size_t>(dk_len)
  );
  Rcpp::RawVector res(out.size());
  std::memcpy(RAW(res), out.data(), out.size());
  return res;
}

// [[Rcpp::export]]
Rcpp::RawVector cpp_hkdf_sha256(Rcpp::RawVector ikm, Rcpp::RawVector salt,
                                Rcpp::RawVector info, int length) {
  if (length <= 0) length = 32;
  auto out = dicomtk::crypto::hkdf_sha256(
    reinterpret_cast<const uint8_t*>(RAW(ikm)), ikm.size(),
    reinterpret_cast<const uint8_t*>(RAW(salt)), salt.size(),
    reinterpret_cast<const uint8_t*>(RAW(info)), info.size(),
    static_cast<size_t>(length)
  );
  Rcpp::RawVector res(out.size());
  std::memcpy(RAW(res), out.data(), out.size());
  return res;
}

// [[Rcpp::export]]
Rcpp::RawVector cpp_aead_encrypt(Rcpp::RawVector key, Rcpp::RawVector plaintext, Rcpp::RawVector aad) {
  if (key.size() != 32) {
    Rcpp::stop("ChaCha20-Poly1305 key must be exactly 32 bytes");
  }
  auto ct = dicomtk::crypto::chacha20_poly1305_encrypt(
    reinterpret_cast<const uint8_t*>(RAW(key)),
    reinterpret_cast<const uint8_t*>(RAW(plaintext)), plaintext.size(),
    reinterpret_cast<const uint8_t*>(RAW(aad)), aad.size()
  );
  Rcpp::RawVector res(ct.size());
  std::memcpy(RAW(res), ct.data(), ct.size());
  return res;
}

// [[Rcpp::export]]
Rcpp::RawVector cpp_aead_decrypt(Rcpp::RawVector key, Rcpp::RawVector ciphertext, Rcpp::RawVector aad) {
  if (key.size() != 32) {
    Rcpp::stop("ChaCha20-Poly1305 key must be exactly 32 bytes");
  }
  auto pt = dicomtk::crypto::chacha20_poly1305_decrypt(
    reinterpret_cast<const uint8_t*>(RAW(key)),
    reinterpret_cast<const uint8_t*>(RAW(ciphertext)), ciphertext.size(),
    reinterpret_cast<const uint8_t*>(RAW(aad)), aad.size()
  );
  Rcpp::RawVector res(pt.size());
  if (!pt.empty()) {
    std::memcpy(RAW(res), pt.data(), pt.size());
  }
  return res;
}

// [[Rcpp::export]]
std::string cpp_hmac_uid(Rcpp::RawVector key, std::string uid) {
  if (key.size() != 32) {
    Rcpp::stop("UID HMAC key must be exactly 32 bytes");
  }
  std::array<uint8_t, 32> k;
  std::memcpy(k.data(), RAW(key), 32);
  return dicomtk::crypto::hmac_dicom_uid(k, uid);
}

// [[Rcpp::export]]
int cpp_hmac_shift_days(Rcpp::RawVector key, std::string patient_id, int min_days, int max_days) {
  if (key.size() != 32) {
    Rcpp::stop("Date shift HMAC key must be exactly 32 bytes");
  }
  std::array<uint8_t, 32> k;
  std::memcpy(k.data(), RAW(key), 32);
  return dicomtk::crypto::hmac_patient_shift_days(k, patient_id, min_days, max_days);
}

// [[Rcpp::export]]
std::string cpp_sha256_file(std::string path) {
  return dicomtk::crypto::sha256_file_hex(path);
}
