// Message types as const object
export const MessageType = {
  TEXT: "text",
  FILE: "file",
  IMAGE: "image",
  SYSTEM: "system",
} as const;

export type MessageTypeValue =
  (typeof MessageType)[keyof typeof MessageType];

// Message interface
export interface Message {
  id: string;
  type: MessageTypeValue;
  content: string;
  sender: "Mobile" | "Me" | "System";
  timestamp: Date;
  url?: string;
  filename?: string;
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
}

// Connection info shape returned from Electron
export interface ConnectionInfo {
  ips: string[];
  wsPort: number;
  httpPort: number;
}
