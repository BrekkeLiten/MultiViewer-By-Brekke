import type { Metadata } from "next";
import { DM_Sans, IBM_Plex_Mono, Syne } from "next/font/google";
import "./globals.css";
import { siteConfig } from "@/lib/site";

const syne = Syne({
  variable: "--font-syne",
  subsets: ["latin"],
  weight: ["700", "800"],
});

const dmSans = DM_Sans({
  variable: "--font-dm-sans",
  subsets: ["latin"],
  weight: ["400", "500"],
});

const ibmPlexMono = IBM_Plex_Mono({
  variable: "--font-ibm-plex-mono",
  subsets: ["latin"],
  weight: ["400", "500"],
});

export const metadata: Metadata = {
  metadataBase: new URL(siteConfig.url),
  title: "MultiViewer by Brekke — macOS Multiview & Scopes",
  description: siteConfig.description,
  openGraph: {
    title: "MultiViewer by Brekke",
    description: siteConfig.description,
    url: siteConfig.url,
    siteName: siteConfig.name,
    images: [{ url: "/og-image.png", width: 512, height: 512, alt: siteConfig.name }],
    locale: "en_US",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "MultiViewer by Brekke",
    description: siteConfig.description,
    images: ["/og-image.png"],
  },
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html
      lang="en"
      className={`${syne.variable} ${dmSans.variable} ${ibmPlexMono.variable} h-full scroll-smooth`}
    >
      <body className="min-h-full antialiased">{children}</body>
    </html>
  );
}
