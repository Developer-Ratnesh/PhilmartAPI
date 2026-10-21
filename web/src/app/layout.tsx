import type { Metadata } from "next";
import localFont from "next/font/local";
import { ThemeProvider, themeInitScript } from "@/lib/theme";
import "./globals.css";

// serif for headings, sans for body. same superfamily so the metrics match.
// self-hosted latin variable files (OFL) because Turbopack in Next 16.3 can't
// resolve next/font/google, and the build then doesn't need Google at all
const display = localFont({
  src: "./fonts/SourceSerif4-latin.woff2",
  weight: "400 700",
  variable: "--font-philmart-display",
  display: "swap",
});

const sans = localFont({
  src: "./fonts/SourceSans3-latin.woff2",
  weight: "400 700",
  variable: "--font-philmart-sans",
  display: "swap",
});

export const metadata: Metadata = {
  title: {
    default: "PHILMART",
    template: "%s · PHILMART",
  },
  description:
    "South Africa's philatelic marketplace and auction house. Buy or bid on philatelic items from approved Shops and Clubs.",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en-ZA" className={`${display.variable} ${sans.variable}`} suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: themeInitScript }} />
        {/* eslint-disable-next-line @next/next/no-sync-scripts */}
        <script src="/config.js" />
      </head>
      <body className="min-h-screen">
        <ThemeProvider>{children}</ThemeProvider>
      </body>
    </html>
  );
}
