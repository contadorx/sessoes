import Link from "next/link";
import Image from "next/image";
import { Moldura } from "@/components/site/Moldura";
import { lerVitrine } from "@/lib/blog-dados";
import { dataPorExtenso } from "@/lib/blog";

export const metadata = {
  title: "Textos",
  description:
    "O que a gente aprende conversando com quem atende: agenda, cobrança, recibo e as regras da profissão.",
};

/**
 * A vitrine.
 *
 * `revalidate` de cinco minutos, e não render a cada visita: o blog é leitura
 * pública de conteúdo que muda uma vez por semana, e uma consulta ao banco por
 * visitante seria pagar banco para servir texto parado. Cinco minutos é o
 * atraso máximo entre eu publicar e o texto aparecer — e as ações do painel
 * chamam `revalidatePath("/blog")`, então na prática o atraso é zero e o
 * intervalo é só a rede de segurança.
 */
export const revalidate = 300;

export default async function BlogPublico() {
  const posts = await lerVitrine(24);

  return (
    <Moldura>
      <div className="mx-auto max-w-5xl px-5 py-12 sm:px-8 sm:py-16">
        <h1 className="max-w-[20ch] font-serif text-[32px] leading-tight tracking-[-0.015em] text-balance sm:text-[40px]">
          O que a gente aprende conversando.
        </h1>
        <p className="mt-4 max-w-[58ch] text-[15px] leading-relaxed text-tinta2">
          Agenda, cobrança, recibo, as regras do Conselho — e o que dá para
          resolver de um jeito que não vira mais trabalho.
        </p>

        {posts.length === 0 ? (
          <p className="mt-12 max-w-[58ch] rounded-cartao border border-dashed border-linha2 bg-folha2 px-5 py-6 text-[13.5px] leading-relaxed text-tinta2">
            Ainda não há texto publicado aqui. Enquanto isso, o produto está no
            ar:{" "}
            <Link href="/entrar?criar" className="underline underline-offset-2 hover:text-vaga">
              a conta grátis não expira e não pede cartão
            </Link>
            .
          </p>
        ) : (
          <ul className="mt-12 grid gap-8 sm:grid-cols-2">
            {posts.map((p) => (
              <li key={p.slug}>
                <Link href={`/blog/${p.slug}`} className="group block">
                  {p.figura_url && (
                    <Image
                      src={p.figura_url}
                      alt={p.figura_alt ?? ""}
                      width={800}
                      height={450}
                      className="mb-4 h-auto w-full rounded-cartao border border-linha"
                      sizes="(min-width: 640px) 480px, 100vw"
                    />
                  )}
                  <h2 className="font-serif text-[21px] leading-snug text-tinta transition-colors group-hover:text-vaga">
                    {p.titulo}
                  </h2>
                  {p.resumo && (
                    <p className="mt-2 text-[13.5px] leading-relaxed text-tinta2">{p.resumo}</p>
                  )}
                  <p className="mt-2 text-[11.5px] text-tinta3">
                    {dataPorExtenso(p.publicado_em)}
                  </p>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </div>
    </Moldura>
  );
}
