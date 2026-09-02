"use client";

import { conferencia, quantosFaltam, type PostParaConferir } from "@/lib/seo";

/**
 * A conferência — uma lista de fatos, e nenhuma nota.
 *
 * A tela que a concorrência faz aqui é um medidor: verde a partir de 80, com
 * peso inventado para cada item. Isso é uma opinião fantasiada de medição —
 * ninguém de fora avalia texto assim, e um número redondo convida a otimizar o
 * número em vez do texto.
 *
 * O que fica no lugar é o que o produto já faz com o piso da multa da B24:
 * **contar, e não adjetivar**. Cada linha é um fato verificável com a
 * consequência escrita ao lado, e quem decide é quem escreveu.
 *
 * As três marcas são deliberadamente feias de somar: "falta" é o que quebra
 * alguma coisa para quem lê (título ausente, figura sem alternativa); "atenção"
 * é escolha com consequência; "ok" é ok. Não há como transformar isso numa
 * média, e é esse o ponto.
 */

const MARCA = {
  ok: { sinal: "·", classe: "text-cheia" },
  atencao: { sinal: "!", classe: "text-tinta2" },
  falta: { sinal: "×", classe: "text-vaga" },
} as const;

export function ConferenciaSeo({ post }: { post: PostParaConferir }) {
  const itens = conferencia(post);
  const faltam = quantosFaltam(itens);

  return (
    <section className="rounded-cartao border border-linha bg-folha2 px-5 py-4">
      <h2 className="rotulo">Antes de publicar</h2>

      <p className="mt-1.5 max-w-[58ch] text-[12px] leading-relaxed text-tinta3">
        {faltam === 0
          ? "Nada aqui impede de publicar."
          : `${faltam} coisa${faltam > 1 ? "s" : ""} quebra${faltam > 1 ? "m" : ""} alguma coisa para quem lê.`}{" "}
        Não há nota: cada linha é um fato, e quem decide é você.
      </p>

      <ul className="mt-3 flex flex-col gap-2.5">
        {itens.map((i) => (
          <li key={i.id} className="flex gap-2.5">
            <span
              aria-hidden
              className={`mt-[1px] w-3 shrink-0 text-center font-mono text-[13px] font-semibold ${MARCA[i.estado].classe}`}
            >
              {MARCA[i.estado].sinal}
            </span>
            <span className="text-[12.5px] leading-relaxed text-tinta2">
              <b className="font-medium text-tinta">{i.titulo}.</b>{" "}
              <span className="sr-only">
                {i.estado === "falta" ? "falta: " : i.estado === "atencao" ? "atenção: " : "ok: "}
              </span>
              {i.frase}
            </span>
          </li>
        ))}
      </ul>

      <p className="mt-4 max-w-[58ch] border-t border-linha pt-3 text-[11.5px] leading-relaxed text-tinta3">
        Três coisas que costumam aparecer em lista de SEO e <b>não</b> estão aqui,
        porque a documentação do Google diz o contrário: não existe limite de
        caracteres para título e descrição (ele corta pela largura da tela), não
        existe número mínimo de palavras, e a <i>meta keywords</i> não é usada pela
        Busca.
      </p>
    </section>
  );
}
