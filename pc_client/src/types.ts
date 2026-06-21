// Message types as const object
export const MessageType = {
  TEXT: "text",
  FILE: "file",
  IMAGE: "image",
  SYSTEM: "system",
} as const;

export type MessageTypeValue =
  (typeof MessageType)[keyof typeof MessageType];

// Transfer state for file/image messages
export type TransferState = "pending" | "transferring" | "complete" | "failed";

// Message interface
export interface Message {
  id: string;
  type: MessageTypeValue;
  content: string;
  sender: "Mobile" | "Me" | "System";
  timestamp: Date;
  url?: string;
  filename?: string;
  transferState?: TransferState;
  transferProgress?: number; // 0-100
  deliveryStatus?: 'pending' | 'sent' | 'delivered';
  // Forward-compatible fields for future multi-device support (#32).
  // Null/undefined means "the one paired device" (current 1:1 behavior).
  recipientId?: string;
  senderId?: string;
}

// Stored message interface for JSON parsing
export interface StoredMessage {
  id: string;
  type: MessageTypeValue;
  content: string;
  sender: "Mobile" | "Me" | "System";
  timestamp: string;
  url?: string;
  filename?: string;
  transferState?: TransferState;
  transferProgress?: number;
  deliveryStatus?: 'pending' | 'sent' | 'delivered';
}

// Connection info shape returned from Electron
export interface ConnectionInfo {
  ips: string[];
  wsPort: number;
  httpPort: number;
}
