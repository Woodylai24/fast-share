import { useState, useRef, useEffect } from "react";
import { type Message, type StoredMessage, MessageType } from "../types";
import { generateId, isImageFile } from "../utils";

// Message persistence service
const MessageStorage = {
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
  isConnected: boolean;
}

export function useMessages({ messages, setMessages, isConnected }: UseMessagesOptions) {
  const [inputText, setInputText] = useState("");
  const messageListRef = useRef<HTMLDivElement>(null);

  // Save messages when they change
  useEffect(() => {
    if (messages.length > 0) {
      MessageStorage.save(messages);
    }
  }, [messages]);

  // Auto-scroll to bottom when new messages arrive
  useEffect(() => {
    if (messageListRef.current) {
      messageListRef.current.scrollTop = messageListRef.current.scrollHeight;
    }
  }, [messages]);

  const sendText = () => {
    if (inputText.trim()) {
      window.electronAPI.sendText(inputText);
      const newMessage: Message = {
        id: generateId(),
        type: MessageType.TEXT,
        content: inputText,
        sender: "Me",
        timestamp: new Date(),
        deliveryStatus: isConnected ? 'delivered' : 'sent',
      };
      setMessages((prev) => [...prev, newMessage]);
      setInputText("");
    }
  };

  const clearHistory = () => {
    setMessages([]);
    MessageStorage.clear();
  };

  const addSentFileMessage = (
    fileName: string,
    httpPort: number,
    _selectedIp: string,
  ) => {
    const isImage = isImageFile(fileName);
    const fileUrl = `http://localhost:${httpPort}/files/${encodeURIComponent(fileName)}`;
    const newMessage: Message = {
      id: generateId(),
      type: isImage ? MessageType.IMAGE : MessageType.FILE,
      content: fileName,
      sender: "Me",
      timestamp: new Date(),
      url: fileUrl,
      filename: fileName,
    };
    setMessages((prev) => [...prev, newMessage]);
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
