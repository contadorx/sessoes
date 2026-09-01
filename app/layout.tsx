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

// A frase do produto.
//
// Trocada duas vezes. A primeira ("sua agenda não fura mais de graça")
// prometia recuperar a hora, que depende de haver demanda represada — hipótese
// que ainda não foi medida. A segunda terminava em "quanto da sua capacidade
// virou receita", e a auditoria pegou o defeito: a meta description repetia a
// tese contábil em vez de dizer o que o produto faz, e o resultado de busca
// prometia painel a quem procura alívio.
//
// Esta diz as quatro coisas que a pessoa procura, na ordem em que ela procura.
const FRASE =
  "Agenda, pagamentos, recibos e o fechamento com o contador num lugar só. Você registra o atendimento uma vez e o resto acompanha.";

export const metadata: Metadata = {
  metadataBase: new URL("https://sessoes.com.br"),
  title: {
    default: "Sessões — tudo o que não é atender, num lugar só",
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
  // Instalado na tela inicial, o nome curto é o que cabe embaixo do ícone.
  applicationName: "Sessões",
  appleWebApp: {
    capable: true,
    title: "Sessões",
    statusBarStyle: "default",
  },
  icons: {
    icon: [
      { url: "/icone-192.png", sizes: "192x192", type: "image/png" },
      { url: "/icone-512.png", sizes: "512x512", type: "image/png" },
    ],
    apple: "/apple-icon.png",
  },
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
