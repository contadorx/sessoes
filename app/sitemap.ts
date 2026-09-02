import type { MetadataRoute } from "next";
import { lerSitemap } from "@/lib/blog-dados";

const BASE = "https://sessoes.com.br";

/**
 * O sitemap.
 *
 * Ele lista **originais que eu quero que sejam rastreados** — não tudo o que
 * responde. Por isso a lista dos textos vem de `posts_do_sitemap`, que já tira
 * o que pede `noindex` e o que declara canônica em outro endereço: pôr um
 * `noindex` aqui é mandar o rastreador a um lugar para ele descobrir que não
 * devia ter ido.
 *
 * `/entrar` e as telas do app ficam de fora pelo mesmo motivo pelo qual estão
 * no `robots.txt`: são portas de sessão, não conteúdo. Um endereço de app num
 * sitemap é rastreio gasto em página que devolve redirecionamento.
 *
 * E ele degrada: sem ambiente do Supabase, o sitemap sai com as páginas fixas
 * em vez de estourar o build. Mesma regra do `clientePublico` — a página que
 * vende o produto sobe mesmo quando o banco está fora.
 */
export const revalidate = 3600;

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const fixas: MetadataRoute.Sitemap = [
    { url: BASE, changeFrequency: "weekly", priority: 1 },
    { url: `${BASE}/blog`, changeFrequency: "weekly", priority: 0.8 },
    { url: `${BASE}/termos`, changeFrequency: "yearly", priority: 0.3 },
    { url: `${BASE}/privacidade`, changeFrequency: "yearly", priority: 0.3 },
    { url: `${BASE}/seguranca`, changeFrequency: "yearly", priority: 0.3 },
  ];

  const textos = await lerSitemap();

  return [
    ...fixas,
    ...textos.map((t) => ({
      url: `${BASE}/blog/${t.slug}`,
      // A data da última mudança de verdade. Carimbar `now()` em tudo, como
      // fazem os geradores preguiçosos, ensina o rastreador a ignorar o campo.
      lastModified: new Date(t.atualizado_em ?? t.publicado_em),
      changeFrequency: "monthly" as const,
      priority: 0.6,
    })),
  ];
}
