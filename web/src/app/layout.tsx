import type { Metadata } from "next";
import { Source_Serif_4, Source_Sans_3 } from "next/font/google";
import { ThemeProvider, themeInitScript } from "@/lib/theme";
import "./globals.css";

// serif for headings, sans for body. same superfamily so the metrics match
const display = Source_Serif_4({
  subsets: ["latin"],
  weight: ["400", "600", "700"],
  variable: "--font-philmart-display",
  display: "swap",
});

const sans = Source_Sans_3({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
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
