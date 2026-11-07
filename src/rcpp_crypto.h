#ifndef RCPP_CRYPTO_H
#define RCPP_CRYPTO_H

#include <cstdint>
#include <cstddef>
#include <string>
#include <vector>
#include <array>
#include <stdexcept>
#include <fstream>
#include <sstream>
#include <iomanip>
#include <algorithm>
#include <random>
#include <cstring>

namespace dicomtk {
namespace crypto {

// Constant-time memory comparison
inline bool ct_memeq(const void* a, const void* b, size_t n) {
  const auto* pa = static_cast<const uint8_t*>(a);
  const auto* pb = static_cast<const uint8_t*>(b);
  uint8_t diff = 0;
  for (size_t i = 0; i < n; ++i) {
    diff |= (pa[i] ^ pb[i]);
  }
  return diff == 0;
}

// SHA-256 context and primitives (RFC 6234 / FIPS 180-4)
struct SHA256Context {
  uint32_t state[8];
  uint64_t count;
  uint8_t buffer[64];
};

void sha256_init(SHA256Context& ctx);
void sha256_update(SHA256Context& ctx, const uint8_t* data, size_t len);
void sha256_final(SHA256Context& ctx, uint8_t digest[32]);

std::array<uint8_t, 32> sha256(const uint8_t* data, size_t len);
inline std::array<uint8_t, 32> sha256(const std::vector<uint8_t>& data) {
  return sha256(data.data(), data.size());
}
inline std::array<uint8_t, 32> sha256(const std::string& str) {
  return sha256(reinterpret_cast<const uint8_t*>(str.data()), str.size());
}

// HMAC-SHA256 (RFC 2104 / RFC 4231)
std::array<uint8_t, 32> hmac_sha256(const uint8_t* key, size_t key_len,
                                    const uint8_t* data, size_t data_len);
inline std::array<uint8_t, 32> hmac_sha256(const std::vector<uint8_t>& key,
                                           const std::vector<uint8_t>& data) {
  return hmac_sha256(key.data(), key.size(), data.data(), data.size());
}

// PBKDF2-HMAC-SHA256 (RFC 2898 / RFC 8018)
std::vector<uint8_t> pbkdf2_hmac_sha256(const uint8_t* pass, size_t pass_len,
                                        const uint8_t* salt, size_t salt_len,
                                        uint32_t iterations, size_t dk_len);

// HKDF-SHA256 (RFC 5869)
std::array<uint8_t, 32> hkdf_extract(const uint8_t* salt, size_t salt_len,
                                     const uint8_t* ikm, size_t ikm_len);
std::vector<uint8_t> hkdf_expand(const uint8_t* prk, size_t prk_len,
                                 const uint8_t* info, size_t info_len,
                                 size_t okm_len);
std::vector<uint8_t> hkdf_sha256(const uint8_t* ikm, size_t ikm_len,
                                 const uint8_t* salt, size_t salt_len,
                                 const uint8_t* info, size_t info_len,
                                 size_t okm_len);

// ChaCha20-Poly1305 AEAD (RFC 8439)
// Encrypt: returns 12-byte nonce || ciphertext || 16-byte Poly1305 tag
std::vector<uint8_t> chacha20_poly1305_encrypt(const uint8_t* key,
                                               const uint8_t* plaintext, size_t pt_len,
                                               const uint8_t* aad, size_t aad_len);

// Decrypt: expects input of at least 28 bytes (12-byte nonce || ciphertext || 16-byte tag)
std::vector<uint8_t> chacha20_poly1305_decrypt(const uint8_t* key,
                                               const uint8_t* ciphertext_with_nonce_tag, size_t ct_len,
                                               const uint8_t* aad, size_t aad_len);

// DICOM UID pseudonymization (maps to deterministic 2.25.<decimal>)
std::string hmac_dicom_uid(const std::array<uint8_t, 32>& uid_key, const std::string& orig_uid);

// Deterministic per-patient date shift
int hmac_patient_shift_days(const std::array<uint8_t, 32>& date_key,
                            const std::string& patient_id,
                            int min_days, int max_days);

// SHA-256 hash of a file on disk
std::string sha256_file_hex(const std::string& filepath);

// Hex helpers
std::string to_hex(const uint8_t* data, size_t len);
std::vector<uint8_t> from_hex(const std::string& hex);

} // namespace crypto
} // namespace dicomtk

#endif // RCPP_CRYPTO_H
