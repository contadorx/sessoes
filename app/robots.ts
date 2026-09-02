import type { MetadataRoute } from "next";

const BASE = "https://sessoes.com.br";

/**
 * O robots.txt.
 *
 * As proibições aqui são sobre **rastreio**, não sobre segredo — e a diferença
 * importa: o que trancar de verdade é a RLS, e nada aqui protege coisa alguma.
 * O que esta lista faz é não gastar o rastreio de ninguém em página que devolve
 * redirecionamento de sessão.
 *
 * Por isso as telas do app entram na lista e a `/p/...` também: os links
 * mágicos de contrato e remarcação são endereços de uma pessoa só, e um deles
 * indexado seria o contrato de alguém aparecendo numa busca.
 */
export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: "*",
        allow: "/",
        disallow: [
          "/api/",
          "/auth/",
          "/entrar",
          "/p/",
          "/agenda",
          "/pacientes",
          "/recebimentos",
          "/fechamento",
          "/encaixes",
          "/negocio",
          "/perfil",
        ],
      },
    ],
    sitemap: `${BASE}/sitemap.xml`,
    host: BASE,
  };
}
