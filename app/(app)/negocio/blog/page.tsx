import Link from "next/link";
import { notFound } from "next/navigation";
import { sessaoAtual } from "@/lib/conta";
import { lerPostsDoPainel } from "@/lib/blog-dados";
import { estadoDoPost, rotuloDoEstado, dataCurta } from "@/lib/blog";

export const metadata = { title: "Blog" };

/**
 * A lista dos textos — rascunho junto com o que está no ar.
 *
 * A decisão desta tela é mostrar os três estados na mesma lista, e não separar
 * "publicados" de "rascunhos" em abas. Um rascunho escondido numa segunda aba é
 * um texto que fica dois anos esquecido; um rascunho no meio da lista, com um
 * rótulo dizendo que ninguém o vê, é uma coisa que incomoda até ser resolvida.
 *
 * É a mesma regra da faixa de prazos da Agenda: o que precisa de decisão fica
 * onde a pessoa já olha.
 */
export default async function Blog() {
  const sessao = await sessaoAtual();
  if (!sessao.operador) notFound();

  const posts = await lerPostsDoPainel();

  return (
    <div className="mx-auto max-w-3xl">
      <Link href="/negocio" className="text-[12.5px] text-tinta3 hover:text-vaga">
        ← o negócio
      </Link>

      <div className="mt-2 flex flex-wrap items-baseline justify-between gap-3">
        <h1 className="font-serif text-[26px] leading-tight tracking-[-0.015em]">
          O blog
        </h1>
        <Link
          href="/negocio/blog/novo"
          className="rounded-full bg-vaga px-4 py-2 text-[12.5px] font-semibold text-white transition-opacity hover:opacity-90"
        >
          Escrever
        </Link>
      </div>

      <p className="mt-3 max-w-[64ch] text-[12.5px] leading-relaxed text-tinta3">
        O que estiver no ar aparece na página inicial e em{" "}
        <Link href="/blog" className="underline underline-offset-2 hover:text-vaga">
          sessoes.com.br/blog
        </Link>
        . Um texto nasce rascunho e continua rascunho até você publicar — e
        depois de publicado o endereço dele não muda mais, porque passa a estar
        em links que outras pessoas guardaram.
      </p>

      {posts.length === 0 ? (
        <p className="mt-8 rounded-cartao border border-dashed border-linha2 bg-folha2 px-5 py-6 text-[13px] leading-relaxed text-tinta2">
          Nenhum texto ainda. O primeiro pode ser o mais curto: uma coisa que
          você explica toda semana no WhatsApp e cansou de digitar de novo.
        </p>
      ) : (
        <ul className="mt-7 grid gap-px overflow-hidden rounded-cartao border border-linha bg-linha">
          {posts.map((p) => {
            const e = estadoDoPost(p);
            return (
              <li key={p.id} className="bg-folha">
                <Link
                  href={`/negocio/blog/${p.id}`}
                  className="flex flex-wrap items-baseline gap-x-3 gap-y-1 px-5 py-3.5 transition-colors hover:bg-folha2"
                >
                  <span className="text-[14px] font-medium text-tinta">{p.titulo}</span>
                  <span
                    className={`rounded-full px-2 py-0.5 text-[11px] font-medium ${
                      e === "no_ar"
                        ? "bg-cheia-bg text-cheia"
                        : e === "rascunho"
                          ? "bg-aviso-bg text-aviso"
                          : "bg-folha2 text-tinta3"
                    }`}
                  >
                    {rotuloDoEstado(e)}
                  </span>
                  <span className="ml-auto font-mono text-[11.5px] text-tinta3">
                    /{p.slug}
                  </span>
                  <span className="w-full font-mono text-[11px] text-tinta3">
                    {p.publicado_em ? `estreou em ${dataCurta(p.publicado_em)}` : "sem estreia"}
                    {p.links > 0 && ` · ${p.links} link${p.links > 1 ? "s" : ""}`}
                  </span>
                </Link>
              </li>
            );
          })}
        </ul>
      )}

      <p className="mt-6 max-w-[64ch] text-[11.5px] leading-relaxed text-tinta3">
        O blog não conta quem leu. Não há tabela de visita nem identificador de
        leitor — num site cujo argumento inteiro é sigilo, medir quem leu o quê
        seria construir o contrário do que a página promete.
      </p>
    </div>
  );
}
