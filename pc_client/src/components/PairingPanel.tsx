import { useState, useEffect } from "react";
import { QRCodeSVG } from "qrcode.react";
import { type ConnectionInfo } from "../types";
import { formatRelativeTime } from "../utils";
import "./PairingPanel.css";

interface PairedDeviceInfo {
  fcmToken: string;
  name: string;
  pairedAt: string;
  lastSeenAt: string;
}

interface PairingPanelProps {
  isOpen: boolean;
  onClose: () => void;
  connectionInfo: ConnectionInfo | null;
  selectedIp: string;
  onIpChange: (ip: string) => void;
  getQrData: () => string;
  refreshTrigger: number;
}

export function PairingPanel({
  isOpen,
  onClose,
  connectionInfo,
  selectedIp,
  onIpChange,
  getQrData,
  refreshTrigger,
}: PairingPanelProps) {
  const [pairedDevices, setPairedDevices] = useState<Record<string, PairedDeviceInfo>>({});

  useEffect(() => {
    if (isOpen) {
      window.electronAPI.getPairedDevices().then((devices) => {
        setPairedDevices(devices as Record<string, PairedDeviceInfo>);
      });
    }
    // refreshTrigger changes when a device connects/disconnects/unpairs,
    // so the panel re-fetches even while open.
  }, [isOpen, refreshTrigger]);

  if (!isOpen) return null;

  const deviceEntries = Object.entries(pairedDevices);

  return (
    <div className="pairing-backdrop" onClick={onClose}>
      <div className="pairing-panel" onClick={(e) => e.stopPropagation()}>
        <div className="pairing-header">
          <h2>Pair New Device</h2>
          <button className="pairing-close" onClick={onClose} title="Close">
            <svg viewBox="0 0 12 12" width="14" height="14">
              <path
                d="M 2 2 L 10 10 M 10 2 L 2 10"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.5"
              />
            </svg>
          </button>
        </div>

        <div className="pairing-content">
          {/* QR Code Section */}
          <div className="qr-section">
            {connectionInfo && connectionInfo.ips.length > 1 && (
              <div className="qr-network-select">
                <label>Network: </label>
                <select
                  value={selectedIp}
                  onChange={(e) => onIpChange(e.target.value)}
                >
                  {connectionInfo.ips.map((ip) => (
                    <option key={ip} value={ip}>
                      {ip}
                    </option>
                  ))}
                </select>
              </div>
            )}
            <div className="qr-code-wrapper">
              <QRCodeSVG value={getQrData()} size={200} />
            </div>
            <p className="qr-instruction">Scan with Mobile App to pair</p>
            <p className="mono qr-address">
              {selectedIp}:{connectionInfo?.wsPort ?? 8080}
            </p>
          </div>

          {/* Paired Devices Section */}
          <div className="paired-devices-section">
            <h3>Paired Devices</h3>
            {deviceEntries.length === 0 ? (
              <p className="no-devices">No devices paired yet.</p>
            ) : (
              <div className="paired-device-list">
                {deviceEntries.map(([id, info]) => (
                  <div key={id} className="paired-device-item">
                    <div className="paired-device-icon">
                      <svg viewBox="0 0 20 20" width="20" height="20" fill="currentColor">
                        <path d="M7 1a2 2 0 00-2 2v1H4a2 2 0 00-2 2v11a2 2 0 002 2h12a2 2 0 002-2V6a2 2 0 00-2-2h-1V3a2 2 0 00-2-2H7zm0 2h6v1H7V3z" />
                      </svg>
                    </div>
                    <div className="paired-device-info">
                      <div className="paired-device-name">{info.name}</div>
                      <div className="paired-device-last-seen">
                        Last seen {formatRelativeTime(info.lastSeenAt)}
                      </div>
                    </div>
                    <button
                      className="paired-device-unpair"
                      title="Unpair device"
                      onClick={() => {
                        window.electronAPI.unpairDevice(id);
                        setPairedDevices((prev) => {
                          const next = { ...prev };
                          delete next[id];
                          return next;
                        });
                      }}
                    >
                      <svg viewBox="0 0 20 20" width="16" height="16" fill="currentColor">
                        <path d="M10 2a8 8 0 100 16 8 8 0 000-16zm3 5l-3 3-3-3-1 1 3 3-3 3 1 1 3-3 3 3 1-1-3-3 3-3-1-1z" />
                      </svg>
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
