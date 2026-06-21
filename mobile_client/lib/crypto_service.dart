import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// CryptoService — End-to-end encryption for WebSocket communication.
///
/// Uses X25519 ECDH for key exchange, HKDF-SHA256 for key derivation,
/// and AES-256-GCM for authenticated encryption.
///
/// Wire format for encrypted messages:
/// { "type": "encrypted", "nonce": "<base64 12 bytes>", "payload": "<base64 ciphertext>", "tag": "<base64 16 bytes>" }
class CryptoService {
  final _x25519 = X25519();
  final _hkdf = Hkdf(hmac: Hmac(Sha256()), outputLength: 32);
  final _aesGcm = AesGcm.with256bits();

  SimpleKeyPair? _keyPair;
  SecretKey? _aesKey;

  /// Initialize — generate an ephemeral X25519 key pair.
  Future<void> init() async {
    _keyPair = await _x25519.newKeyPair();
  }

  /// Get the base64-encoded public key for key exchange.
  Future<String> getPublicKeyBase64() async {
    if (_keyPair == null) throw StateError('CryptoService not initialized');
    final publicKey = await _keyPair!.extractPublicKey();
    return base64Encode(publicKey.bytes);
  }

  /// Compute the shared secret from the remote peer's public key.
  /// Derives an AES-256 key via HKDF-SHA256.
  Future<void> computeSharedSecret(String remotePublicKeyBase64) async {
    if (_keyPair == null) throw StateError('CryptoService not initialized');

    final remoteBytes = base64Decode(remotePublicKeyBase64);
    final remotePublicKey = SimplePublicKey(remoteBytes, type: KeyPairType.x25519);

    // Compute shared secret via X25519
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: _keyPair!,
      remotePublicKey: remotePublicKey,
    );

    // Derive AES-256 key using HKDF-SHA256
    final derivedKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: Uint8List(0), // no salt/nonce for HKDF
      info: utf8.encode('fast-share-e2ee-v1'),
    );
    _aesKey = derivedKey;
  }

  /// Returns true if the session key has been established.
  bool get isReady => _aesKey != null;

  /// Encrypt a JSON-serializable map and return the encrypted wrapper.
  Future<Map<String, String>> encrypt(Map<String, dynamic> data) async {
    if (_aesKey == null) {
      throw StateError('Key exchange not completed — cannot encrypt');
    }

    final plaintext = utf8.encode(jsonEncode(data));

    // Generate a random 96-bit (12 byte) nonce
    final nonce = List<int>.generate(12, (_) => Random.secure().nextInt(256));
    // Encrypt with AES-256-GCM
    final secretBox = await _aesGcm.encrypt(
      plaintext,
      secretKey: _aesKey!,
      nonce: nonce,
    );

    return {
      'nonce': base64Encode(nonce),
      'payload': base64Encode(secretBox.cipherText),
      'tag': base64Encode(secretBox.mac.bytes),
    };
  }

  /// Decrypt an encrypted wrapper and return the parsed inner map.
  /// Returns null on decryption failure (instead of throwing).
  Future<Map<String, dynamic>?> decrypt(Map<String, String> wrapper) async {
    if (_aesKey == null) {
      print('[Crypto] Key exchange not completed — cannot decrypt');
      return null;
    }

    try {
      final nonce = base64Decode(wrapper['nonce']!);
      final ciphertext = base64Decode(wrapper['payload']!);
      final macBytes = base64Decode(wrapper['tag']!);

      final secretBox = SecretBox(
        ciphertext,
        nonce: nonce,
        mac: Mac(macBytes),
      );

      final decrypted = await _aesGcm.decrypt(
        secretBox,
        secretKey: _aesKey!,
      );

      final jsonStr = utf8.decode(decrypted);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (error) {
      print('[Crypto] Decryption failed: $error');
      return null;
    }
  }

  /// Compute SHA-256 checksum of byte data (for file chunks).
  static Future<String> sha256(List<int> data) async {
    final hash = await Sha256().hash(data);
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Message types that are sent unencrypted (pre-key-exchange or control messages).
const Set<String> unencryptedTypes = {
  'handshake',
  'key-exchange',
  'reconnect',
  'disconnect',
  'unpair',
  'ping',
  'pong',
  'message-ack',
};

/// Check if a message type should be sent unencrypted.
bool isUnencryptedType(String type) {
  return unencryptedTypes.contains(type);
}
