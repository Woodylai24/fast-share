import { useState } from "react";
import "./Onboarding.css";

interface OnboardingProps {
  onComplete: () => void;
}

const STEPS = [
  {
    icon: "🚀",
    title: "Welcome to Fast Share",
    description:
      "Share files, text, and clipboard between your PC and phone — fast, private, and over your local network.",
  },
  {
    icon: "📱",
    title: "How It Works",
    description:
      "Your PC creates a local server. Scan the QR code with your phone to connect. No internet required — everything stays on your network.",
  },
  {
    icon: "✨",
    title: "What You Can Do",
    description: null,
    features: [
      { icon: "📁", title: "File Sharing", desc: "Drag & drop files of any size" },
      { icon: "💬", title: "Text Messages", desc: "Send quick text messages" },
      { icon: "📋", title: "Clipboard Sync", desc: "Copy & paste across devices" },
      { icon: "🔒", title: "Encrypted", desc: "End-to-end encryption built in" },
    ],
  },
  {
    icon: "📲",
    title: "Get the Mobile App",
    description:
      "You'll need the Fast Share app on your phone to connect. Download it and come back!",
    downloadUrl: "https://github.com/Woodylai24/fast-share/releases",
    downloadLabel: "Download for Android",
  },
  {
    icon: "🎉",
    title: "You're All Set!",
    description:
      "Scan the QR code on the next screen with your phone to connect. Happy sharing!",
  },
];

export function Onboarding({ onComplete }: OnboardingProps) {
  const [step, setStep] = useState(0);
  const current = STEPS[step];
  const isFirst = step === 0;
  const isLast = step === STEPS.length - 1;

  const next = () => {
    if (isLast) {
      onComplete();
    } else {
      setStep((s) => s + 1);
    }
  };

  const prev = () => {
    if (!isFirst) setStep((s) => s - 1);
  };

  return (
    <div className="onboarding-backdrop">
      <button className="onboarding-skip" onClick={onComplete}>
        Skip
      </button>

      <div className="onboarding-content">
        <div className="onboarding-icon">{current.icon}</div>
        <h1 className="onboarding-title">{current.title}</h1>

        {current.description && (
          <p className="onboarding-description">{current.description}</p>
        )}

        {current.features && (
          <div className="onboarding-features">
            {current.features.map((f) => (
              <div className="onboarding-feature" key={f.title}>
                <span className="onboarding-feature-icon">{f.icon}</span>
                <span className="onboarding-feature-text">
                  <strong>{f.title}</strong>
                  {f.desc}
                </span>
              </div>
            ))}
          </div>
        )}

        {current.downloadUrl && (
          <button
            className="onboarding-download-btn"
            onClick={() => {
              if (current.downloadUrl) {
                window.electronAPI.openExternal(current.downloadUrl);
              }
            }}
          >
            <span>⬇️</span>
            {current.downloadLabel}
          </button>
        )}

        <div className="onboarding-nav">
          <button
            className="onboarding-btn"
            onClick={prev}
            disabled={isFirst}
          >
            Back
          </button>

          <div className="onboarding-dots">
            {STEPS.map((_, i) => (
              <button
                key={i}
                className={`onboarding-dot ${i === step ? "active" : ""}`}
                onClick={() => setStep(i)}
                aria-label={`Step ${i + 1}`}
              />
            ))}
          </div>

          <button className="onboarding-btn primary" onClick={next}>
            {isLast ? "Get Started" : "Next"}
          </button>
        </div>
      </div>
    </div>
  );
}
