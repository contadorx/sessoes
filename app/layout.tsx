import type { Metadata, Viewport } from "next";
import { Newsreader, Archivo, IBM_Plex_Mono } from "next/font/google";
import "./globals.css";

const serif = Newsreader({
  variable: "--fonte-serif",
  subsets: ["latin"],
  display: "swap",
  weight: ["300", "400", "500", "600"],
});

const sans = Archivo({
  variable: "--fonte-sans",
  subsets: ["latin"],
  display: "swap",
  weight: ["400", "500", "600", "700"],
});

const mono = IBM_Plex_Mono({
  variable: "--fonte-mono",
  subsets: ["latin"],
  display: "swap",
  weight: ["400", "500"],
});

const FRASE =
  "Sua agenda não fura mais de graça, e você nunca mais precisa cobrar ninguém.";

export const metadata: Metadata = {
  metadataBase: new URL("https://sessoes.com.br"),
  title: {
    default: "Sessões — a agenda que não fura de graça",
    template: "%s · Sessões",
  },
  description: FRASE,
  openGraph: {
    title: "Sessões",
    description: FRASE,
    url: "https://sessoes.com.br",
    siteName: "Sessões",
    locale: "pt_BR",
    type: "website",
  },
  robots: { index: true, follow: true },
};

export const viewport: Viewport = {
  themeColor: "#ECEEE9",
  colorScheme: "light",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html
      lang="pt-BR"
      className={`${serif.variable} ${sans.variable} ${mono.variable} h-full`}
    >
      <body className="min-h-full">{children}</body>
    </html>
  );
}
