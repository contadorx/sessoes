import type { MetadataRoute } from "next";

/**
 * O manifesto que faz o app instalar na tela inicial.
 *
 * Era critério de pronto da B3 — "o app instala no seu celular" — e não existia.
 * Não é vaidade: a psicóloga usa isto **entre uma sessão e outra**, no corredor,
 * com dez minutos e o celular na mão. Um endereço para digitar no navegador é
 * atrito suficiente para ela não abrir, e um produto que ela não abre não forma
 * hábito (é o risco R12 do doc 11).
 *
 * `display: standalone` tira a barra de endereço — junto com ela, some o nome do
 * site da tela. Numa sala com paciente, isso conta.
 */
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Sessões",
    short_name: "Sessões",
    description: "A agenda que não fura de graça.",
    start_url: "/agenda",
    scope: "/",
    display: "standalone",
    orientation: "portrait",
    background_color: "#ECEEE9",
    theme_color: "#ECEEE9",
    lang: "pt-BR",
    dir: "ltr",
    categories: ["productivity", "medical"],
    icons: [
      { src: "/icone-192.png", sizes: "192x192", type: "image/png", purpose: "any" },
      { src: "/icone-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
      // O Android recorta o ícone em círculo; o maskable tem a folga para isso.
      { src: "/icone-maskable-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
    ],
  };
}
