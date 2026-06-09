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
  },
});

export default settingsStore;
