import { CryptoManager } from "../electron/crypto";

describe("CryptoManager", () => {
  test("key exchange: two managers derive the same shared secret", () => {
    const alice = new CryptoManager();
    const bob = new CryptoManager();

    // Exchange public keys
    const alicePub = alice.getPublicKeyBase64();
    const bobPub = bob.getPublicKeyBase64();

    // Both compute shared secret from the other's public key
    alice.computeSharedSecret(bobPub);
    bob.computeSharedSecret(alicePub);

    // Both should be ready
    expect(alice.isReady()).toBe(true);
    expect(bob.isReady()).toBe(true);

    // Verify they derived the same key by roundtripping a message
    const testMessage = { type: "test", data: "hello" };
    const encrypted = alice.encrypt(testMessage);
    const decrypted = bob.decrypt(encrypted);

    expect(decrypted).toEqual(testMessage);
  });

  test("encrypt/decrypt roundtrip", () => {
    const alice = new CryptoManager();
    const bob = new CryptoManager();

    alice.computeSharedSecret(bob.getPublicKeyBase64());
    bob.computeSharedSecret(alice.getPublicKeyBase64());

    const original = { type: "text", content: "Hello, E2EE world!" };
    const encrypted = alice.encrypt(original);

    // Encrypted wrapper should have the expected fields
    expect(encrypted).toHaveProperty("nonce");
    expect(encrypted).toHaveProperty("payload");
    expect(encrypted).toHaveProperty("tag");
    expect(typeof encrypted.nonce).toBe("string");
    expect(typeof encrypted.payload).toBe("string");
    expect(typeof encrypted.tag).toBe("string");

    // Decrypt should recover the original message
    const decrypted = bob.decrypt(encrypted);
    expect(decrypted).toEqual(original);

    // Also test the reverse direction
    const encrypted2 = bob.encrypt(original);
    const decrypted2 = alice.decrypt(encrypted2);
    expect(decrypted2).toEqual(original);
  });

  test("decrypt with wrong key returns null", () => {
    const alice = new CryptoManager();
    const bob = new CryptoManager();
    const eve = new CryptoManager();

    // Alice and Bob do key exchange
    alice.computeSharedSecret(bob.getPublicKeyBase64());
    bob.computeSharedSecret(alice.getPublicKeyBase64());

    // Eve does NOT exchange with Alice — she has a different key
    eve.computeSharedSecret(bob.getPublicKeyBase64());

    const original = { type: "secret", content: "classified" };
    const encrypted = alice.encrypt(original);

    // Eve should fail to decrypt (wrong key)
    const result = eve.decrypt(encrypted);
    expect(result).toBeNull();
  });

  test("decrypt with tampered payload returns null", () => {
    const alice = new CryptoManager();
    const bob = new CryptoManager();

    alice.computeSharedSecret(bob.getPublicKeyBase64());
    bob.computeSharedSecret(alice.getPublicKeyBase64());

    const original = { type: "text", content: "important message" };
    const encrypted = alice.encrypt(original);

    // Tamper with the ciphertext payload
    const tamperedPayload = Buffer.from(encrypted.payload, "base64");
    tamperedPayload[0] ^= 0xff; // flip bits in first byte
    const tampered = {
      ...encrypted,
      payload: tamperedPayload.toString("base64"),
    };

    const result = bob.decrypt(tampered);
    expect(result).toBeNull();
  });

  test("decrypt with tampered tag returns null", () => {
    const alice = new CryptoManager();
    const bob = new CryptoManager();

    alice.computeSharedSecret(bob.getPublicKeyBase64());
    bob.computeSharedSecret(alice.getPublicKeyBase64());

    const original = { type: "text", content: "important message" };
    const encrypted = alice.encrypt(original);

    // Tamper with the auth tag
    const tamperedTag = Buffer.from(encrypted.tag, "base64");
    tamperedTag[0] ^= 0xff;
    const tampered = {
      ...encrypted,
      tag: tamperedTag.toString("base64"),
    };

    const result = bob.decrypt(tampered);
    expect(result).toBeNull();
  });

  test("decrypt before key exchange returns null", () => {
    const alice = new CryptoManager();
    expect(alice.isReady()).toBe(false);

    const result = alice.decrypt({
      nonce: Buffer.alloc(12).toString("base64"),
      payload: Buffer.alloc(16).toString("base64"),
      tag: Buffer.alloc(16).toString("base64"),
    });
    expect(result).toBeNull();
  });

  test("encrypt before key exchange throws", () => {
    const alice = new CryptoManager();
    expect(() => alice.encrypt({ type: "test" })).toThrow(
      "Key exchange not completed",
    );
  });

  test("sha256 produces consistent hashes", () => {
    const data = Buffer.from("hello world");
    const hash1 = CryptoManager.sha256(data);
    const hash2 = CryptoManager.sha256(data);
    expect(hash1).toBe(hash2);
    expect(hash1).toMatch(/^[0-9a-f]{64}$/);
  });
});
