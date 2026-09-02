import Link from "next/link";
import Image from "next/image";
import { lerVitrine } from "@/lib/blog-dados";
import { dataPorExtenso } from "@/lib/blog";

/**
 * Os últimos textos, na página inicial.
 *
 * **Condicional, pela mesma regra da seção das capturas de tela:** sem texto
 * publicado, a seção não existe. Uma faixa "em breve, nossos artigos" numa
 * landing é a promessa não cumprida que a auditoria encontrou no funil, com
 * outra roupa.
 *
 * **E ela entra depois dos planos, antes do fechamento.** Não antes: quem chega
 * pela primeira vez está decidindo se o produto resolve o mês dela, e três
 * links de leitura no meio dessa decisão são três saídas da página. Depois do
 * preço, eles viram a outra coisa que a pessoa pode fazer se não estiver pronta
 * para criar conta — que é exatamente o papel que a conversa já ocupa no fim.
 *
 * Três, e não seis: é vitrine, não índice. Quem quiser mais vai ao /blog.
 */
export async function UltimosTextos() {
  const posts = await lerVitrine(3);
  if (posts.length === 0) return null;

  return (
    <section id="textos" className="scroll-mt-16 border-t border-linha">
      <div className="mx-auto max-w-5xl px-5 py-12 sm:px-8 sm:py-16">
        <div className="flex flex-wrap items-baseline justify-between gap-3">
          <div>
            <p className="rotulo">Textos</p>
            <h2 className="mt-2 max-w-[24ch] font-serif text-[26px] leading-tight tracking-[-0.015em] text-balance sm:text-[32px]">
              O que a gente aprende conversando.
            </h2>
          </div>
          <Link
            href="/blog"
            className="text-[13px] font-medium text-tinta2 underline decoration-linha2 underline-offset-4 transition-colors hover:text-vaga"
          >
            ver todos
          </Link>
        </div>

        <ul className="mt-9 grid gap-7 sm:grid-cols-3">
          {posts.map((p) => (
            <li key={p.slug}>
              <Link href={`/blog/${p.slug}`} className="group block">
                {p.figura_url && (
                  <Image
                    src={p.figura_url}
                    alt={p.figura_alt ?? ""}
                    width={600}
                    height={338}
                    className="mb-3 h-auto w-full rounded-cartao border border-linha"
                    sizes="(min-width: 640px) 320px, 100vw"
                  />
                )}
                <h3 className="font-serif text-[18px] leading-snug text-tinta transition-colors group-hover:text-vaga">
                  {p.titulo}
                </h3>
                {p.resumo && (
                  <p className="mt-1.5 text-[13px] leading-relaxed text-tinta2">{p.resumo}</p>
                )}
                <p className="mt-1.5 text-[11px] text-tinta3">
                  {dataPorExtenso(p.publicado_em)}
                </p>
              </Link>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
