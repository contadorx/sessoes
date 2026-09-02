import Link from "next/link";
import Image from "next/image";
import { notFound } from "next/navigation";
import { Moldura } from "@/components/site/Moldura";
import { lerPost } from "@/lib/blog-dados";
import { paragrafos, dataPorExtenso, minutosDeLeitura } from "@/lib/blog";

export const revalidate = 300;

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const achado = await lerPost(slug);
  if (!achado) return { title: "Texto não encontrado" };
  return {
    title: achado.post.titulo,
    description: achado.post.resumo ?? undefined,
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

  return (
    <Moldura>
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
            width={1200}
            height={675}
            priority
            className="mt-7 h-auto w-full rounded-cartao border border-linha"
            sizes="(min-width: 768px) 680px, 100vw"
          />
        )}

        <div className="mt-8 flex flex-col gap-5">
          {paragrafos(post.corpo).map((p, i) => (
            <p
              key={i}
              className="whitespace-pre-line font-serif text-[16.5px] leading-[1.75] text-tinta"
            >
              {p}
            </p>
          ))}
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
            Agenda, prontuário e o registro do mês no plano Grátis, que não
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
