import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 站点库整库签名（Ed25519）验签：只验不签。
///
/// 签名私钥只存在于生成器一侧（工作目录本地文件，权限 600，
/// 不进树）；App 里只写死公钥。验签数学与生成器用的
/// ed25519_ref.py 同源，两边都用 RFC 8032 官方测试向量钉过：
/// 向量 1（空消息）在 Python 侧全对，Dart 侧由
/// test/station_library_test.dart 用同一向量钉。
///
/// 实现是纯 Dart 大整数运算（曲线点加/倍点带求逆），一次验签
/// 约几百次模幂，只在导入站点库时跑一次，不进任何热路径。
const stationSignaturePublicKeyHex =
    '2b3101912b442c89922075a11159eb67ca99f84e3ee09f59e91dfe8a95ebbde9';

final BigInt _p = (BigInt.one << 255) - BigInt.from(19);
final BigInt _l =
    (BigInt.one << 252) +
    BigInt.parse('27742317777372353535851937790883648493');
final BigInt _d = _mod(-BigInt.from(121665) * _inv(BigInt.from(121666)));
final BigInt _sqrtM1 = BigInt.two.modPow(
  (_p - BigInt.one) ~/ BigInt.from(4),
  _p,
);

BigInt _mod(BigInt x) => x % _p;

BigInt _inv(BigInt x) => x.modPow(_p - BigInt.two, _p);

class _Point {
  const _Point(this.x, this.y);

  final BigInt x;
  final BigInt y;

  @override
  bool operator ==(Object other) =>
      other is _Point && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

BigInt _xRecover(BigInt y) {
  final xx = _mod((y * y - BigInt.one) * _inv(_mod(_d * y * y + BigInt.one)));
  var x = xx.modPow((_p + BigInt.from(3)) ~/ BigInt.from(8), _p);
  if (_mod(x * x - xx) != BigInt.zero) x = _mod(x * _sqrtM1);
  if (x.isOdd) x = _p - x;
  return x;
}

_Point get _basePoint {
  final by = _mod(BigInt.from(4) * _inv(BigInt.from(5)));
  return _Point(_xRecover(by), by);
}

_Point _edwards(_Point p, _Point q) {
  final t = _mod(_d * p.x * q.x * p.y * q.y);
  final x = _mod((p.x * q.y + q.x * p.y) * _inv(_mod(BigInt.one + t)));
  final y = _mod((p.y * q.y + p.x * q.x) * _inv(_mod(BigInt.one - t)));
  return _Point(x, y);
}

_Point _scalarMult(_Point point, BigInt e) {
  var result = _Point(BigInt.zero, BigInt.one);
  var addend = point;
  var scalar = e;
  while (scalar > BigInt.zero) {
    if (scalar.isOdd) result = _edwards(result, addend);
    addend = _edwards(addend, addend);
    scalar = scalar >> 1;
  }
  return result;
}

BigInt _intFromLittleEndian(List<int> bytes) {
  var value = BigInt.zero;
  for (var i = bytes.length - 1; i >= 0; i--) {
    value = (value << 8) | BigInt.from(bytes[i] & 0xff);
  }
  return value;
}

_Point _decodePoint(List<int> bytes) {
  final y = _intFromLittleEndian(bytes) & ((BigInt.one << 255) - BigInt.one);
  final sign = (bytes[31] >> 7) & 1;
  var x = _xRecover(y);
  if ((x.isOdd ? 1 : 0) != sign) x = _p - x;
  return _Point(x, y);
}

/// Ed25519 验签本体：[signature] 64 字节、[publicKey] 32 字节、
/// [message] 为被签字节。格式不对或验不过一律返回 false。
bool ed25519Verify({
  required List<int> signature,
  required List<int> message,
  required List<int> publicKey,
}) {
  if (signature.length != 64 || publicKey.length != 32) return false;
  try {
    final rBytes = signature.sublist(0, 32);
    final aBytes = publicKey;
    final s = _intFromLittleEndian(signature.sublist(32, 64));
    if (s >= _l) return false;
    final r = _decodePoint(rBytes);
    final a = _decodePoint(aBytes);
    final digest = sha512.convert([...rBytes, ...aBytes, ...message]).bytes;
    final h = _intFromLittleEndian(digest) % _l;
    final left = _scalarMult(_basePoint, s);
    final right = _edwards(r, _scalarMult(a, h));
    return left == right;
  } catch (_) {
    return false;
  }
}

Uint8List? _hexToBytes(String hex) {
  if (hex.length.isOdd) return null;
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    final byte = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    if (byte == null) return null;
    out[i] = byte;
  }
  return out;
}

/// 站点库签名校验入口：公钥用写死常量，[payload] 是生成器与
/// 导入器约定的签名字节串（见 station_library.dart 的版本门）。
bool verifyStationLibrarySignature({
  required List<int> payload,
  required String signatureHex,
}) {
  final signature = _hexToBytes(signatureHex);
  final publicKey = _hexToBytes(stationSignaturePublicKeyHex);
  if (signature == null || publicKey == null) return false;
  return ed25519Verify(
    signature: signature,
    message: payload,
    publicKey: publicKey,
  );
}
