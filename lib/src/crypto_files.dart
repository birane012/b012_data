import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// First bytes of a file encrypted by b012_data.
final List<int> fileMagic = ascii.encode('B012ENC1');

final AesGcm _aes = AesGcm.with256bits();

/// Whether [head] starts with the marker of a file encrypted by b012_data.
bool hasFileMagic(List<int> head) {
  if (head.length < fileMagic.length) return false;
  for (int i = 0; i < fileMagic.length; i++) {
    if (head[i] != fileMagic[i]) return false;
  }
  return true;
}

/// Whether [bytes] is a file encrypted by b012_data.
bool isEncryptedFile(List<int> bytes) {
  if (bytes.length < fileMagic.length + 12 + 16) return false;
  for (int i = 0; i < fileMagic.length; i++) {
    if (bytes[i] != fileMagic[i]) return false;
  }
  return true;
}

/// `B012ENC1` + nonce (12 bytes) + AES-256-GCM ciphertext + MAC (16 bytes).
Future<Uint8List> sealFile(List<int> clear, List<int> key) async {
  final SecretBox box = await _aes.encrypt(clear, secretKey: SecretKey(key));
  return Uint8List.fromList(<int>[...fileMagic, ...box.concatenation()]);
}

/// The clear content of a sealed file; throws when the key is wrong or the
/// file was altered.
Future<Uint8List> openFile(List<int> sealed, List<int> key) async {
  final SecretBox box = SecretBox.fromConcatenation(
    sealed.sublist(fileMagic.length),
    nonceLength: 12,
    macLength: 16,
  );
  return Uint8List.fromList(await _aes.decrypt(box, secretKey: SecretKey(key)));
}
