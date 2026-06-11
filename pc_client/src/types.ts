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
  // transferState/transferProgress not persisted — in-progress transfers
  // shouldn't survive reload, and completed transfers don't need them
}

// Connection info shape returned from Electron
export interface ConnectionInfo {
  ips: string[];
  wsPort: number;
  httpPort: number;
}
