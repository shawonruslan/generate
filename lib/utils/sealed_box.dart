import 'dart:math';
import 'dart:typed_data';

/// Pure-Dart `crypto_box_seal` (libsodium sealed box), ported 1:1 from a
/// Python implementation that was verified byte-for-byte against libsodium
/// (PyNaCl) in both directions — X25519 (RFC 7748), HSalsa20, XSalsa20-
/// Poly1305 secretbox (RFC 8439 Poly1305) and Blake2b all match. Needed for
/// GitHub Actions secrets: GitHub only accepts sealed-box-encrypted values.
/// No native dependency, so it works identically on Android and Windows.

final BigInt _p255 = (BigInt.one << 255) - BigInt.from(19);
const int _m32 = 0xFFFFFFFF;

// ---------------- X25519 (RFC 7748) ----------------

Uint8List _x25519(Uint8List scalarBytes, Uint8List uBytes) {
  final k = Uint8List.fromList(scalarBytes);
  k[0] &= 248;
  k[31] &= 127;
  k[31] |= 64;
  final n = _leToBigInt(k);
  final u = _leToBigInt(uBytes) & ((BigInt.one << 255) - BigInt.one);
  var x1 = u;
  var x2 = BigInt.one;
  var z2 = BigInt.zero;
  var x3 = u;
  var z3 = BigInt.one;
  var swap = 0;
  final a24 = BigInt.from(121665);
  for (var t = 254; t >= 0; t--) {
    final kt = ((n >> t) & BigInt.one).toInt();
    swap ^= kt;
    if (swap == 1) {
      final tx = x2;
      x2 = x3;
      x3 = tx;
      final tz = z2;
      z2 = z3;
      z3 = tz;
    }
    swap = kt;
    final a = (x2 + z2) % _p255;
    final aa = a * a % _p255;
    final b = (x2 - z2) % _p255;
    final bb = b * b % _p255;
    final e = (aa - bb) % _p255;
    final c = (x3 + z3) % _p255;
    final d = (x3 - z3) % _p255;
    final da = d * a % _p255;
    final cb = c * b % _p255;
    final s1 = (da + cb) % _p255;
    x3 = s1 * s1 % _p255;
    final s2 = (da - cb) % _p255;
    z3 = x1 * (s2 * s2 % _p255) % _p255;
    x2 = aa * bb % _p255;
    z2 = e * ((aa + a24 * e) % _p255) % _p255;
  }
  if (swap == 1) {
    final tx = x2;
    x2 = x3;
    x3 = tx;
    final tz = z2;
    z2 = z3;
    z3 = tz;
  }
  final out = x2 * z2.modPow(_p255 - BigInt.two, _p255) % _p255;
  return _bigIntToLe(out, 32);
}

BigInt _leToBigInt(Uint8List bytes) {
  var v = BigInt.zero;
  for (var i = bytes.length - 1; i >= 0; i--) {
    v = (v << 8) | BigInt.from(bytes[i]);
  }
  return v;
}

Uint8List _bigIntToLe(BigInt v, int length) {
  final out = Uint8List(length);
  var x = v;
  for (var i = 0; i < length; i++) {
    out[i] = (x & BigInt.from(0xFF)).toInt();
    x = x >> 8;
  }
  return out;
}

Uint8List _x25519Base(Uint8List scalar) {
  final base = Uint8List(32);
  base[0] = 9;
  return _x25519(scalar, base);
}

// ---------------- Salsa20 core / HSalsa20 ----------------

int _rotl32(int x, int b) => (((x << b) | (x >>> (32 - b))) & _m32);

void _qr(List<int> y, int a, int b, int c, int d) {
  y[b] ^= _rotl32((y[a] + y[d]) & _m32, 7);
  y[c] ^= _rotl32((y[b] + y[a]) & _m32, 9);
  y[d] ^= _rotl32((y[c] + y[b]) & _m32, 13);
  y[a] ^= _rotl32((y[d] + y[c]) & _m32, 18);
}

int _le32(Uint8List b, int off) =>
    b[off] | (b[off + 1] << 8) | (b[off + 2] << 16) | (b[off + 3] << 24);

final Uint8List _sigma = Uint8List.fromList('expand 32-byte k'.codeUnits);

void _rounds(List<int> y) {
  for (var i = 0; i < 10; i++) {
    _qr(y, 0, 4, 8, 12);
    _qr(y, 5, 9, 13, 1);
    _qr(y, 10, 14, 2, 6);
    _qr(y, 15, 3, 7, 11);
    _qr(y, 0, 1, 2, 3);
    _qr(y, 5, 6, 7, 4);
    _qr(y, 10, 11, 8, 9);
    _qr(y, 15, 12, 13, 14);
  }
}

Uint8List _hsalsa20(Uint8List key32, Uint8List nonce16) {
  final x = List<int>.filled(16, 0);
  x[0] = _le32(_sigma, 0);
  x[5] = _le32(_sigma, 4);
  x[10] = _le32(_sigma, 8);
  x[15] = _le32(_sigma, 12);
  for (var i = 0; i < 4; i++) {
    x[1 + i] = _le32(key32, i * 4);
    x[11 + i] = _le32(key32, 16 + i * 4);
  }
  for (var i = 0; i < 4; i++) {
    x[6 + i] = _le32(nonce16, i * 4);
  }
  final y = List<int>.from(x);
  _rounds(y);
  final outIdx = [0, 5, 10, 15, 6, 7, 8, 9];
  final out = Uint8List(32);
  for (var j = 0; j < 8; j++) {
    final v = y[outIdx[j]];
    out[j * 4] = v & 0xFF;
    out[j * 4 + 1] = (v >>> 8) & 0xFF;
    out[j * 4 + 2] = (v >>> 16) & 0xFF;
    out[j * 4 + 3] = (v >>> 24) & 0xFF;
  }
  return out;
}

Uint8List _salsa20Block(Uint8List key32, Uint8List nonce8, int ic) {
  final x = List<int>.filled(16, 0);
  x[0] = _le32(_sigma, 0);
  x[5] = _le32(_sigma, 4);
  x[10] = _le32(_sigma, 8);
  x[15] = _le32(_sigma, 12);
  for (var i = 0; i < 4; i++) {
    x[1 + i] = _le32(key32, i * 4);
    x[11 + i] = _le32(key32, 16 + i * 4);
  }
  x[6] = _le32(nonce8, 0);
  x[7] = _le32(nonce8, 4);
  x[8] = ic & _m32;
  x[9] = (ic >>> 32) & _m32;
  final y = List<int>.from(x);
  _rounds(y);
  final out = Uint8List(64);
  for (var i = 0; i < 16; i++) {
    final v = (y[i] + x[i]) & _m32;
    out[i * 4] = v & 0xFF;
    out[i * 4 + 1] = (v >>> 8) & 0xFF;
    out[i * 4 + 2] = (v >>> 16) & 0xFF;
    out[i * 4 + 3] = (v >>> 24) & 0xFF;
  }
  return out;
}

Uint8List _xsalsa20Stream(Uint8List key32, Uint8List nonce24, int length) {
  final sub = _hsalsa20(key32, Uint8List.sublistView(nonce24, 0, 16));
  final nonce8 = Uint8List.sublistView(nonce24, 16, 24);
  final out = Uint8List(length);
  var written = 0;
  var ic = 0;
  while (written < length) {
    final block = _salsa20Block(sub, nonce8, ic);
    ic++;
    final n = min(64, length - written);
    out.setRange(written, written + n, block);
    written += n;
  }
  return out;
}

// ---------------- Poly1305 (RFC 8439) ----------------

Uint8List _poly1305Mac(Uint8List msg, Uint8List key32) {
  final r = _leToBigInt(Uint8List.sublistView(key32, 0, 16)) &
      BigInt.parse('0ffffffc0ffffffc0ffffffc0fffffff', radix: 16);
  final s = _leToBigInt(Uint8List.sublistView(key32, 16, 32));
  final p = (BigInt.one << 130) - BigInt.from(5);
  var acc = BigInt.zero;
  for (var i = 0; i < msg.length; i += 16) {
    final end = min(i + 16, msg.length);
    final chunk = Uint8List.sublistView(msg, i, end);
    final n = _leToBigInt(chunk) + (BigInt.one << (8 * (end - i)));
    acc = ((acc + n) * r) % p;
  }
  final tag = (acc + s) % (BigInt.one << 128);
  return _bigIntToLe(tag, 16);
}

// ---------------- Blake2b (unkeyed) ----------------

BigInt _b(String hex) => BigInt.parse(hex, radix: 16);
final List<BigInt> _b2Iv = [
  _b('6a09e667f3bcc908'),
  _b('bb67ae8584caa73b'),
  _b('3c6ef372fe94f82b'),
  _b('a54ff53a5f1d36f1'),
  _b('510e527fade682d1'),
  _b('9b05688c2b3e6c1f'),
  _b('1f83d9abfb41bd6b'),
  _b('5be0cd19137e2179'),
];
const List<List<int>> _b2Sigma = [
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
  [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
  [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
  [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
  [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
  [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
  [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
  [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
  [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
  [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
];
final BigInt _m64 = (BigInt.one << 64) - BigInt.one;

BigInt _rotr64(BigInt x, int b) => ((x >> b) | (x << (64 - b))) & _m64;

Uint8List _blake2b(Uint8List data, int outLen) {
  final h = List<BigInt>.from(_b2Iv);
  h[0] ^= BigInt.from(0x01010000) ^ BigInt.from(outLen);
  final nBlocks = max(1, (data.length + 127) ~/ 128);
  for (var bi = 0; bi < nBlocks; bi++) {
    final isLast = bi == nBlocks - 1;
    final start = bi * 128;
    final end = min(start + 128, data.length);
    final count = isLast ? data.length : (bi + 1) * 128;
    final m = List<BigInt>.filled(16, BigInt.zero);
    for (var i = 0; i < 16; i++) {
      var v = BigInt.zero;
      for (var j = 7; j >= 0; j--) {
        final idx = start + i * 8 + j;
        v = (v << 8) | BigInt.from(idx < end ? data[idx] : 0);
      }
      m[i] = v;
    }
    final v = List<BigInt>.generate(16, (i) => i < 8 ? h[i] : _b2Iv[i - 8]);
    v[12] ^= BigInt.from(count) & _m64;
    v[13] ^= BigInt.from(count >> 64) & _m64;
    if (isLast) v[14] ^= _m64;
    void g(int a, int b, int c, int d, BigInt x, BigInt y) {
      v[a] = (v[a] + v[b] + x) & _m64;
      v[d] = _rotr64(v[d] ^ v[a], 32);
      v[c] = (v[c] + v[d]) & _m64;
      v[b] = _rotr64(v[b] ^ v[c], 24);
      v[a] = (v[a] + v[b] + y) & _m64;
      v[d] = _rotr64(v[d] ^ v[a], 16);
      v[c] = (v[c] + v[d]) & _m64;
      v[b] = _rotr64(v[b] ^ v[c], 63);
    }

    for (var r = 0; r < 12; r++) {
      final s = _b2Sigma[r % 10];
      g(0, 4, 8, 12, m[s[0]], m[s[1]]);
      g(1, 5, 9, 13, m[s[2]], m[s[3]]);
      g(2, 6, 10, 14, m[s[4]], m[s[5]]);
      g(3, 7, 11, 15, m[s[6]], m[s[7]]);
      g(0, 5, 10, 15, m[s[8]], m[s[9]]);
      g(1, 6, 11, 12, m[s[10]], m[s[11]]);
      g(2, 7, 8, 13, m[s[12]], m[s[13]]);
      g(3, 4, 9, 14, m[s[14]], m[s[15]]);
    }
    for (var i = 0; i < 8; i++) {
      h[i] ^= v[i] ^ v[i + 8];
    }
  }
  final full = Uint8List(64);
  for (var i = 0; i < 8; i++) {
    full.setRange(i * 8, i * 8 + 8, _bigIntToLe(h[i], 8));
  }
  return Uint8List.sublistView(full, 0, outLen);
}

// ---------------- secretbox + seal ----------------

Uint8List _secretboxEasy(Uint8List msg, Uint8List nonce24, Uint8List key32) {
  final stream = _xsalsa20Stream(key32, nonce24, msg.length + 32);
  final cipher = Uint8List(msg.length);
  for (var i = 0; i < msg.length; i++) {
    cipher[i] = msg[i] ^ stream[32 + i];
  }
  final tag = _poly1305Mac(cipher, Uint8List.sublistView(stream, 0, 32));
  final out = Uint8List(16 + cipher.length);
  out.setRange(0, 16, tag);
  out.setRange(16, out.length, cipher);
  return out;
}

/// Encrypt [message] for GitHub Actions secrets: returns the sealed box
/// (ephemeral public key || secretbox). Base64-encode before sending.
Uint8List sealForGitHub(Uint8List message, Uint8List recipientPublicKey) {
  final rng = Random.secure();
  final ephemeralSk = Uint8List.fromList(
      List<int>.generate(32, (_) => rng.nextInt(256)));
  final ephemeralPk = _x25519Base(ephemeralSk);
  final nonceInput = Uint8List(64);
  nonceInput.setRange(0, 32, ephemeralPk);
  nonceInput.setRange(32, 64, recipientPublicKey);
  final nonce = _blake2b(nonceInput, 24);
  final shared = _x25519(ephemeralSk, recipientPublicKey);
  final k = _hsalsa20(shared, Uint8List(16));
  final box = _secretboxEasy(message, nonce, k);
  final out = Uint8List(32 + box.length);
  out.setRange(0, 32, ephemeralPk);
  out.setRange(32, out.length, box);
  return out;
}
