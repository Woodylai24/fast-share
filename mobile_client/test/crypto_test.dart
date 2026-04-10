import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fast_share_mobile/crypto_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CryptoService', () {
    test('key exchange: two services derive the same shared key', () async {
      final alice = CryptoService();
      final bob = CryptoService();

      await alice.init();
      await bob.init();

      // Exchange public keys
      final alicePub = await alice.getPublicKeyBase64();
      final bobPub = await bob.getPublicKeyBase64();

      // Both compute shared secret from the other's public key
      await alice.computeSharedSecret(bobPub);
      await bob.computeSharedSecret(alicePub);

      // Both should be ready
      expect(alice.isReady, isTrue);
      expect(bob.isReady, isTrue);

      // Verify they derived the same key by roundtripping a message
      const testMessage = {'type': 'test', 'data': 'hello'};
      final encrypted = await alice.encrypt(testMessage);
      final decrypted = await bob.decrypt(encrypted);

      expect(decrypted, equals(testMessage));
    });

    test('encrypt/decrypt roundtrip', () async {
      final alice = CryptoService();
      final bob = CryptoService();

      await alice.init();
      await bob.init();

      await alice.computeSharedSecret(await bob.getPublicKeyBase64());
      await bob.computeSharedSecret(await alice.getPublicKeyBase64());

      const original = {'type': 'text', 'content': 'Hello, E2EE world!'};
      final encrypted = await alice.encrypt(original);

      // Encrypted wrapper should have the expected fields
      expect(encrypted, contains('nonce'));
      expect(encrypted, contains('payload'));
      expect(encrypted, contains('tag'));
      expect(encrypted['nonce'], isA<String>());
      expect(encrypted['payload'], isA<String>());
      expect(encrypted['tag'], isA<String>());

      // Decrypt should recover the original message
      final decrypted = await bob.decrypt(encrypted);
      expect(decrypted, equals(original));

      // Also test the reverse direction
      final encrypted2 = await bob.encrypt(original);
      final decrypted2 = await alice.decrypt(encrypted2);
      expect(decrypted2, equals(original));
    });

    test('decrypt with wrong key returns null', () async {
      final alice = CryptoService();
      final bob = CryptoService();
      final eve = CryptoService();

      await alice.init();
      await bob.init();
      await eve.init();

      // Alice and Bob do key exchange
      await alice.computeSharedSecret(await bob.getPublicKeyBase64());
      await bob.computeSharedSecret(await alice.getPublicKeyBase64());

      // Eve does NOT exchange with Alice — she pairs with Bob instead
      await eve.computeSharedSecret(await bob.getPublicKeyBase64());

      const original = {'type': 'secret', 'content': 'classified'};
      final encrypted = await alice.encrypt(original);

      // Eve should fail to decrypt (wrong key)
      final result = await eve.decrypt(encrypted);
      expect(result, isNull);
    });

    test('decrypt with tampered payload returns null', () async {
      final alice = CryptoService();
      final bob = CryptoService();

      await alice.init();
      await bob.init();

      await alice.computeSharedSecret(await bob.getPublicKeyBase64());
      await bob.computeSharedSecret(await alice.getPublicKeyBase64());

      const original = {'type': 'text', 'content': 'important message'};
      final encrypted = await alice.encrypt(original);

      // Tamper with the ciphertext payload
      final payloadBytes = base64Decode(encrypted['payload']!);
      final tampered = Uint8List.fromList(payloadBytes);
      tampered[0] ^= 0xff; // flip bits in first byte

      final tamperedWrapper = <String, String>{
        'nonce': encrypted['nonce']!,
        'payload': base64Encode(tampered),
        'tag': encrypted['tag']!,
      };

      final result = await bob.decrypt(tamperedWrapper);
      expect(result, isNull);
    });

    test('decrypt with tampered tag returns null', () async {
      final alice = CryptoService();
      final bob = CryptoService();

      await alice.init();
      await bob.init();

      await alice.computeSharedSecret(await bob.getPublicKeyBase64());
      await bob.computeSharedSecret(await alice.getPublicKeyBase64());

      const original = {'type': 'text', 'content': 'important message'};
      final encrypted = await alice.encrypt(original);

      // Tamper with the auth tag
      final tagBytes = base64Decode(encrypted['tag']!);
      final tamperedTag = Uint8List.fromList(tagBytes);
      tamperedTag[0] ^= 0xff;

      final tamperedWrapper = <String, String>{
        'nonce': encrypted['nonce']!,
        'payload': encrypted['payload']!,
        'tag': base64Encode(tamperedTag),
      };

      final result = await bob.decrypt(tamperedWrapper);
      expect(result, isNull);
    });

    test('decrypt before key exchange returns null', () async {
      final alice = CryptoService();
      await alice.init();

      expect(alice.isReady, isFalse);

      final result = await alice.decrypt({
        'nonce': base64Encode(Uint8List(12)),
        'payload': base64Encode(Uint8List(16)),
        'tag': base64Encode(Uint8List(16)),
      });
      expect(result, isNull);
    });

    test('encrypt before key exchange throws', () async {
      final alice = CryptoService();
      await alice.init();

      expect(
        () => alice.encrypt({'type': 'test'}),
        throwsStateError,
      );
    });

    test('sha256 produces consistent hashes', () async {
      final data = utf8.encode('hello world');
      final hash1 = await CryptoService.sha256(data);
      final hash2 = await CryptoService.sha256(data);

      expect(hash1, equals(hash2));
      expect(hash1, matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  });
}
