import crypto from "crypto";

/**
 * CryptoManager — End-to-end encryption for WebSocket communication.
 *
 * Uses X25519 ECDH for key exchange, HKDF-SHA256 for key derivation,
 * and AES-256-GCM for authenticated encryption.
 *
 * Wire format for encrypted messages:
 * { "type": "encrypted", "nonce": "<base64 12 bytes>", "payload": "<base64 ciphertext>", "tag": "<base64 16 bytes>" }
 */
export class CryptoManager {
  private privateKey: Buffer;
  private publicKey: Buffer;
  private sharedKey: Buffer | null = null;
  private aesKey: Buffer | null = null;

  constructor() {
    // Generate ephemeral X25519 key pair
    const keyPair = crypto.generateKeyPairSync("x25519");
    this.privateKey = keyPair.privateKey
      .export({ type: "pkcs8", format: "der" })
      .slice(-32); // last 32 bytes is the raw private key
    this.publicKey = keyPair.publicKey
      .export({ type: "spki", format: "der" })
      .slice(-32); // last 32 bytes is the raw public key
  }

  /** Get the base64-encoded public key for key exchange. */
  getPublicKeyBase64(): string {
    return this.publicKey.toString("base64");
  }

  /**
   * Compute the shared secret from the remote peer's public key.
   * Derives an AES-256 key via HKDF-SHA256.
   */
  computeSharedSecret(remotePublicKeyBase64: string): void {
    const remotePublicKey = Buffer.from(remotePublicKeyBase64, "base64");

    // Create X25519 key objects for the diffie-hellman
    const localPrivateKey = crypto.createPrivateKey({
      key: this.wrapX25519Private(this.privateKey),
      format: "der",
      type: "pkcs8",
    });
    const remotePub = crypto.createPublicKey({
      key: this.wrapX25519Public(remotePublicKey),
      format: "der",
      type: "spki",
    });

    // Compute raw shared secret
    this.sharedKey = crypto.diffieHellman({
      privateKey: localPrivateKey,
      publicKey: remotePub,
    });

    // Derive AES-256 key using HKDF-SHA256
    this.aesKey = Buffer.from(
      crypto.hkdfSync(
        "sha256",
        this.sharedKey,
        Buffer.alloc(0), // no salt
        Buffer.from("fast-share-e2ee-v1", "utf8"), // info/context string
        32, // 256-bit key
      ),
    );
  }

  /** Returns true if the session key has been established. */
  isReady(): boolean {
    return this.aesKey !== null;
  }

  /**
   * Encrypt a JSON-serializable object and return the encrypted wrapper.
   * @throws Error if key exchange hasn't been completed.
   */
  encrypt(data: object): { nonce: string; payload: string; tag: string } {
    if (!this.aesKey) {
      throw new Error("Key exchange not completed — cannot encrypt");
    }

    const plaintext = Buffer.from(JSON.stringify(data), "utf8");
    const nonce = crypto.randomBytes(12); // 96-bit IV for GCM
    const cipher = crypto.createCipheriv("aes-256-gcm", this.aesKey, nonce);

    const encrypted = Buffer.concat([
      cipher.update(plaintext),
      cipher.final(),
    ]);
    const tag = cipher.getAuthTag(); // 16 bytes

    return {
      nonce: nonce.toString("base64"),
      payload: encrypted.toString("base64"),
      tag: tag.toString("base64"),
    };
  }

  /**
   * Decrypt an encrypted wrapper and return the parsed inner object.
   * Returns null on decryption failure (instead of throwing).
   */
  decrypt(wrapper: {
    nonce: string;
    payload: string;
    tag: string;
  }): object | null {
    if (!this.aesKey) {
      console.error("[Crypto] Key exchange not completed — cannot decrypt");
      return null;
    }

    try {
      const nonce = Buffer.from(wrapper.nonce, "base64");
      const ciphertext = Buffer.from(wrapper.payload, "base64");
      const tag = Buffer.from(wrapper.tag, "base64");

      const decipher = crypto.createDecipheriv(
        "aes-256-gcm",
        this.aesKey,
        nonce,
      );
      decipher.setAuthTag(tag);

      const decrypted = Buffer.concat([
        decipher.update(ciphertext),
        decipher.final(),
      ]);

      return JSON.parse(decrypted.toString("utf8"));
    } catch (error) {
      console.error("[Crypto] Decryption failed:", error);
      return null;
    }
  }

  /**
   * Compute SHA-256 checksum of a buffer (for file chunks).
   */
  static sha256(data: Buffer): string {
    return crypto.createHash("sha256").update(data).digest("hex");
  }

  // --- Private helpers for X25519 key wrapping ---

  /** Wrap a raw 32-byte X25519 private key into PKCS#8 DER. */
  private wrapX25519Private(raw: Buffer): Buffer {
    // PKCS#8 DER for X25519: 46 bytes
    // 30 2e 02 01 00 30 05 06 03 2b 65 6e 04 22 04 20 <32 bytes>
    const prefix = Buffer.from([
      0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x6e,
      0x04, 0x22, 0x04, 0x20,
    ]);
    return Buffer.concat([prefix, raw]);
  }

  /** Wrap a raw 32-byte X25519 public key into SPKI DER. */
  private wrapX25519Public(raw: Buffer): Buffer {
    // SPKI DER for X25519: 44 bytes
    // 30 2a 30 05 06 03 2b 65 6e 03 21 00 <32 bytes>
    const prefix = Buffer.from([
      0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x6e, 0x03, 0x21, 0x00,
    ]);
    return Buffer.concat([prefix, raw]);
  }
}

/** Message types that are sent unencrypted (pre-key-exchange). */
export const UNENCRYPTED_TYPES = new Set([
  "handshake",
  "key-exchange",
  "reconnect",
  "disconnect",
]);

/**
 * Check if a message type should be sent unencrypted.
 */
export function isUnencryptedType(type: string): boolean {
  return UNENCRYPTED_TYPES.has(type);
}
