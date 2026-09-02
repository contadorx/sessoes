import Link from "next/link";
import { notFound } from "next/navigation";
import { sessaoAtual } from "@/lib/conta";
import { lerPostDoPainel, lerFiguras } from "@/lib/blog-dados";
import { BlogEditor, AcoesDoPost } from "@/components/app/BlogEditor";
import { estadoDoPost, dataPorExtenso } from "@/lib/blog";

export const metadata = { title: "Texto" };

/**
 * Um texto por dentro: as ações em cima, o formulário embaixo.
 *
 * A ordem é essa porque a pergunta que se faz ao abrir esta tela não é "o que
 * eu escrevi", é **"isto está no ar?"**. Quem vem editar já sabe o que
 * escreveu; quem vem conferir precisa da resposta antes de rolar.
 */
export default async function PostDoPainel({
  params,
}: {
  params: Promise<{ post: string }>;
}) {
  const sessao = await sessaoAtual();
  if (!sessao.operador) notFound();

  const { post: id } = await params;
  const ficha = await lerPostDoPainel(id);
  if (!ficha) notFound();

  const figuras = await lerFiguras();

  const e = estadoDoPost(ficha.post);

  return (
    <div className="mx-auto max-w-5xl">
      <Link href="/negocio/blog" className="text-[12.5px] text-tinta3 hover:text-vaga">
        ← o blog
      </Link>

      <h1 className="mt-2 font-serif text-[26px] leading-tight tracking-[-0.015em]">
        {ficha.post.titulo}
      </h1>
      {ficha.post.publicado_em && (
        <p className="mt-1 text-[12px] text-tinta3">
          estreou em {dataPorExtenso(ficha.post.publicado_em)}
          {e === "no_ar" && (
            <>
              {" · "}
              <a
                href={`/blog/${ficha.post.slug}`}
                className="underline underline-offset-2 hover:text-vaga"
              >
                ver no site
              </a>
            </>
          )}
        </p>
      )}

      <div className="mt-6">
        <AcoesDoPost post={ficha.post} />
      </div>

      <div className="mt-8 border-t border-linha pt-7">
        <BlogEditor post={ficha.post} links={ficha.links} figuras={figuras} />
      </div>
    </div>
  );
}
