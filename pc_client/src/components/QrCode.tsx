import { QRCodeSVG } from "qrcode.react";
import { type ConnectionInfo } from "../types";

interface QrCodeSectionProps {
  connectionInfo: ConnectionInfo;
  selectedIp: string;
  onIpChange: (ip: string) => void;
  getQrData: () => string;
}

export function QrCodeSection({
  connectionInfo,
  selectedIp,
  onIpChange,
  getQrData,
}: QrCodeSectionProps) {
  return (
    <div className="qr-section">
      {connectionInfo.ips.length > 1 && (
        <div style={{ marginBottom: "1rem" }}>
          <label>Select Network: </label>
          <select
            title="network-selector"
            value={selectedIp}
            onChange={(e) => onIpChange(e.target.value)}
            style={{ padding: "5px" }}
          >
            {connectionInfo.ips.map((ip) => (
              <option key={ip} value={ip}>
                {ip}
              </option>
            ))}
          </select>
        </div>
      )}

      <QRCodeSVG value={getQrData()} size={200} />
      <p>Scan with Mobile App to Connect</p>
      <p className="mono">
        {selectedIp}:{connectionInfo.wsPort}
      </p>
    </div>
  );
}
