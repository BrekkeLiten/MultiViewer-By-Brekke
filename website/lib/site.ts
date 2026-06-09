export const siteConfig = {
  name: "MultiViewer by Brekke",
  url: "https://multiviewer.brek.ke",
  description:
    "Native macOS multiview for NDI and DeckLink SDI — 4-up or 1-up with optional scope monitor, GPU picture tools, bundled NDI runtime, and HTTP control for Bitfocus Companion.",
  version: process.env.NEXT_PUBLIC_APP_VERSION ?? "1.0",
  downloadUrl: process.env.NEXT_PUBLIC_DOWNLOAD_URL ?? "",
} as const;
