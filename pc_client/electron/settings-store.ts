const ElectronStore = require("electron-store").default;

const settingsStore = new ElectronStore({
  name: "fastshare-settings",
  defaults: {
    startupOnBoot: false,
    minimizeToTray: false,
    clipboardSync: "auto-message",
    soundOnMessage: true,
    notificationsEnabled: true,
    theme: "system",
    onboardingComplete: false,
    lastConnectedDevice: '',
    lastConnectedAt: '',
    pairedDevices: {} as Record<string, { fcmToken: string; name: string; pairedAt: string; lastSeenAt: string }>,
  },
});

// --- Paired Device Helpers ---

export function isDevicePaired(deviceId: string): boolean {
  const devices = settingsStore.get("pairedDevices") as Record<string, { fcmToken: string; name: string; pairedAt: string; lastSeenAt: string }>;
  return !!devices[deviceId];
}

export function getPairedDeviceFcmToken(deviceId: string): string | undefined {
  const devices = settingsStore.get("pairedDevices") as Record<string, { fcmToken: string; name: string; pairedAt: string; lastSeenAt: string }>;
  return devices[deviceId]?.fcmToken;
}

export function getAllPairedDevices(): Record<string, { fcmToken: string; name: string; pairedAt: string; lastSeenAt: string }> {
  return (settingsStore.get("pairedDevices") as Record<string, { fcmToken: string; name: string; pairedAt: string; lastSeenAt: string }>) ?? {};
}

export function pairDevice(deviceId: string, info: { fcmToken?: string; name: string }): void {
  const devices = settingsStore.get("pairedDevices") as Record<string, { fcmToken: string; name: string; pairedAt: string; lastSeenAt: string }>;
  const existing = devices[deviceId];
  const now = new Date().toISOString();

  devices[deviceId] = {
    fcmToken: info.fcmToken ?? existing?.fcmToken ?? "",
    name: info.name,
    pairedAt: existing?.pairedAt ?? now,
    lastSeenAt: now,
  };

  settingsStore.set("pairedDevices", devices);
  console.log("[DEBUG] Device paired:", deviceId, info.name);
}

export function updateDeviceLastSeen(deviceId: string): void {
  const devices = settingsStore.get("pairedDevices") as Record<string, { fcmToken: string; name: string; pairedAt: string; lastSeenAt: string }>;
  if (devices[deviceId]) {
    devices[deviceId].lastSeenAt = new Date().toISOString();
    settingsStore.set("pairedDevices", devices);
  }
}

export function removePairedDevice(deviceId: string): void {
  const devices = settingsStore.get("pairedDevices") as Record<string, { fcmToken: string; name: string; pairedAt: string; lastSeenAt: string }>;
  delete devices[deviceId];
  settingsStore.set("pairedDevices", devices);
}

export default settingsStore;
