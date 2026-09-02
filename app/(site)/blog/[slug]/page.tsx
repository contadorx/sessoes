import Link from "next/link";
import Image from "next/image";
import { notFound } from "next/navigation";
import { Moldura } from "@/components/site/Moldura";
import { lerPost } from "@/lib/blog-dados";
import { dataPorExtenso, minutosDeLeitura } from "@/lib/blog";
import { Texto as Corpo, Indice } from "@/components/site/Texto";
import { metaDoPost, jsonLdDoPost, jsonLdSeguro } from "@/lib/seo";

const BASE = "https://sessoes.com.br";
const AUTOR = "Leandro Alves";

export const revalidate = 300;

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const achado = await lerPost(slug);
  if (!achado) return { title: "Texto não encontrado" };

  const m = metaDoPost(achado.post, BASE);

  return {
    title: m.titulo,
    description: m.descricao,
    // A canônica diz qual endereço é o original. Sem ela, o mesmo texto
    // alcançável por dois caminhos vira duas páginas concorrendo entre si.
    alternates: { canonical: m.canonica },
    // `noindex` não esconde de ninguém: quem tem o link continua lendo. É um
    // pedido ao rastreador, e a tela do editor diz isso com essas palavras.
    robots: m.indexavel ? undefined : { index: false, follow: true },
    openGraph: {
      type: "article",
      title: m.titulo,
      description: m.descricao,
      url: m.canonica,
      siteName: "Sessões",
      locale: "pt_BR",
      publishedTime: achado.post.publicado_em ?? undefined,
      modifiedTime: achado.post.atualizado_em ?? undefined,
      images: m.figura ? [{ url: m.figura, alt: m.figuraAlt ?? m.titulo }] : undefined,
    },
    twitter: {
      card: m.figura ? "summary_large_image" : "summary",
      title: m.titulo,
      description: m.descricao,
    },
  };
}

/**
 * Um texto.
 *
 * **O corpo é renderizado como texto**, um `<p>` por parágrafo, e é aqui que a
 * decisão da 0051 aparece inteira: não existe caminho entre uma string do banco
 * e o HTML desta página. O React escapa por padrão, e o único jeito de desfazer
 * isso seria `dangerouslySetInnerHTML` — que tem teste no repositório inteiro
 * reprovando a presença dele.
 *
 * A `lerPost` usa o cliente **sem sessão**. Um rascunho não é 403 para o
 * visitante: ele simplesmente não existe, e a página é 404. Dizer "existe algo
 * que você não pode ver" é entregar informação de graça — mesmo padrão do
 * `/negocio` e do `/api/*`.
 */
export default async function Texto({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const achado = await lerPost(slug);
  if (!achado) notFound();

  const { post, links } = achado;
  const m = metaDoPost(post, BASE);

  // Os dados estruturados. A documentação do Google diz que **nenhuma
  // propriedade de Article é obrigatória** — então aqui não há campo com
  // valor de enfeite para "completar o schema": dado estruturado que não bate
  // com a página é violação declarada de política, e a ausência é honesta.
  //
  // Vai como **filho de texto** do `<script>`, e não por
  // `dangerouslySetInnerHTML`: o React trata filho de texto como texto, e o
  // `jsonLdSeguro` ainda escapa o `<` — sem isso, um título que contivesse
  // `</script>` fecharia a tag no meio do JSON.
  const dados = jsonLdSeguro(
    jsonLdDoPost({
      titulo: post.titulo,
      slug: post.slug,
      descricao: m.descricao,
      publicado_em: post.publicado_em,
      atualizado_em: post.atualizado_em ?? null,
      figura: post.figura_url,
      autor: AUTOR,
      site: "Sessões",
      base: BASE,
    }),
  );

  return (
    <Moldura>
      <script type="application/ld+json">{dados}</script>
      <article className="mx-auto max-w-[68ch] px-5 py-12 sm:px-8 sm:py-16">
        <Link href="/blog" className="text-[12.5px] text-tinta3 transition-colors hover:text-vaga">
          ← textos
        </Link>

        <h1 className="mt-3 font-serif text-[30px] leading-tight tracking-[-0.015em] text-balance sm:text-[38px]">
          {post.titulo}
        </h1>

        <p className="mt-3 text-[12.5px] text-tinta3">
          {dataPorExtenso(post.publicado_em)} · {minutosDeLeitura(post.corpo)} min de leitura
        </p>

        {post.figura_url && (
          <Image
            src={post.figura_url}
            alt={post.figura_alt ?? ""}
            /* As medidas do arquivo, quando existem. Sem elas o navegador não
               reserva o espaço e o texto pula quando a imagem chega. */
            width={post.figura_largura ?? 1200}
            height={post.figura_altura ?? 675}
            priority
            className="mt-7 h-auto w-full rounded-cartao border border-linha"
            sizes="(min-width: 768px) 680px, 100vw"
          />
        )}

        <Indice corpo={post.corpo} formato={post.formato} />

        <div className="mt-4">
          <Corpo corpo={post.corpo} formato={post.formato} />
        </div>

        {links.length > 0 && (
          <div className="mt-10 border-t border-linha pt-6">
            <p className="rotulo">Para ir adiante</p>
            <ul className="mt-3 flex flex-col gap-2">
              {links.map((l) => (
                <li key={l.url}>
                  <a
                    href={l.url}
                    className="text-[14px] text-tinta2 underline decoration-linha2 underline-offset-4 transition-colors hover:text-vaga"
                    {...(l.url.startsWith("/")
                      ? {}
                      : { target: "_blank", rel: "noopener noreferrer" })}
                  >
                    {l.rotulo}
                  </a>
                </li>
              ))}
            </ul>
          </div>
        )}

        <div className="mt-12 rounded-cartao border border-linha bg-folha2 px-5 py-6">
          <p className="font-serif text-[19px] leading-snug text-tinta">
            Tudo o que não é atender, num lugar só.
          </p>
          <p className="mt-2 max-w-[52ch] text-[13.5px] leading-relaxed text-tinta2">
            Agenda, prontuário e o registro do mês no plano Gratuito, que não
            expira e não pede cartão.
          </p>
          <Link
            href="/entrar?criar"
            className="mt-4 inline-block rounded-full bg-vaga px-5 py-2.5 text-[13px] font-semibold text-white transition-opacity hover:opacity-90"
          >
            Criar conta grátis
          </Link>
        </div>
      </article>
    </Moldura>
  );
}
