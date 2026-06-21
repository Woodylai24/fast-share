import { useState, useRef, useEffect } from "react";
import { type Message, type StoredMessage, MessageType } from "../types";
import { generateId, isImageFile } from "../utils";

// Message persistence service
export const MessageStorage = {
  STORAGE_KEY: "fastshare_messages",

  save(messages: Message[]): void {
    try {
      const data: StoredMessage[] = messages.map((msg) => ({
        ...msg,
        timestamp: msg.timestamp.toISOString(),
      }));
      localStorage.setItem(this.STORAGE_KEY, JSON.stringify(data));
    } catch (e) {
      console.error("Failed to save messages:", e);
    }
  },

  load(): Message[] {
    try {
      const data = localStorage.getItem(this.STORAGE_KEY);
      if (!data) return [];
      const parsed: StoredMessage[] = JSON.parse(data);
      return parsed.map((msg) => ({
        ...msg,
        timestamp: new Date(msg.timestamp),
        // Reset any in-progress transfers — they can't resume across restart
        transferState: msg.transferState === "pending" || msg.transferState === "transferring"
          ? "failed" as const
          : msg.transferState,
      }));
    } catch (e) {
      console.error("Failed to load messages:", e);
      return [];
    }
  },

  clear(): void {
    localStorage.removeItem(this.STORAGE_KEY);
  },
};

interface UseMessagesOptions {
  messages: Message[];
  setMessages: React.Dispatch<React.SetStateAction<Message[]>>;
}

export function useMessages({ messages, setMessages }: UseMessagesOptions) {
  const [inputText, setInputText] = useState("");
  const messageListRef = useRef<HTMLDivElement>(null);

  // Keep a ref to the latest messages so beforeunload can access them
  // synchronously without waiting for React's async effect cycle.
  const messagesRef = useRef(messages);
  messagesRef.current = messages;

  // Save messages whenever they change
  useEffect(() => {
    MessageStorage.save(messages);
  }, [messages]);

  // Safety net: force-save on app exit. React effects fire asynchronously
  // after paint — if the window is destroyed before the effect runs, the
  // last state update is lost. This is the main cause of file/image
  // messages disappearing after restart (rapid IPC events from chunked
  // transfers get batched; if the app closes before the batched render,
  // the save never fires).
  useEffect(() => {
    const handleBeforeUnload = () => {
      MessageStorage.save(messagesRef.current);
    };
    window.addEventListener("beforeunload", handleBeforeUnload);
    return () => window.removeEventListener("beforeunload", handleBeforeUnload);
  }, []);

  // Auto-scroll to bottom when new messages arrive
  useEffect(() => {
    if (messageListRef.current) {
      messageListRef.current.scrollTop = messageListRef.current.scrollHeight;
    }
  }, [messages]);

  const sendText = () => {
    if (inputText.trim()) {
      const messageId = generateId();
      window.electronAPI.sendText(inputText, messageId);
      const newMessage: Message = {
        id: messageId,
        type: MessageType.TEXT,
        content: inputText,
        sender: "Me",
        timestamp: new Date(),
        deliveryStatus: 'sent', // upgrades to 'delivered' when ACK arrives
      };
      setMessages((prev) => [...prev, newMessage]);
      setInputText("");
    }
  };

  const clearHistory = () => {
    setMessages([]);
    MessageStorage.save([]);
  };

  const addSentFileMessage = (
    fileName: string,
    httpPort: number,
    _selectedIp: string,
  ) => {
    const isImage = isImageFile(fileName);
    const fileUrl = `http://localhost:${httpPort}/files/${encodeURIComponent(fileName)}`;
    const messageId = generateId();
    // Note: offerFile is called by App.tsx, not here. The messageId must
    // be passed back so App.tsx can include it in the offerFile call.
    const newMessage: Message = {
      id: messageId,
      type: isImage ? MessageType.IMAGE : MessageType.FILE,
      content: fileName,
      sender: "Me",
      timestamp: new Date(),
      url: fileUrl,
      filename: fileName,
      deliveryStatus: 'sent',
    };
    setMessages((prev) => [...prev, newMessage]);
    return messageId;
  };

  return {
    inputText,
    setInputText,
    sendText,
    clearHistory,
    addSentFileMessage,
    messageListRef,
  };
}
