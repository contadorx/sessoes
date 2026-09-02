"use client";

import { useRef, useState } from "react";
import { Texto } from "@/components/site/Texto";
import { palavras, blocos } from "@/lib/marcacao";

/**
 * O editor de texto — uma barra, uma caixa de texto e a prévia de verdade.
 *
 * **A caixa continua sendo uma `textarea`, e isso é a decisão.** Um editor
 * "rico" (contentEditable) guarda HTML, e guardar HTML é exatamente o que a
 * 0051 recusou: a partir daí a página pública depende de um sanitizador estar
 * certo, atualizado e ter sido chamado. Aqui o que se guarda é o que a pessoa
 * digitou, e o que a página monta é árvore tipada.
 *
 * O que a barra faz é tirar da pessoa a obrigação de decorar a marcação: ela
 * seleciona e clica, e o texto ganha os asteriscos. É a mesma coisa que um
 * editor rico entrega, sem a parte que abre a porta.
 *
 * **A prévia usa o MESMO componente da página pública.** Uma prévia que
 * renderiza por outro caminho é uma prévia que mente — e mente exatamente no
 * dia em que os dois caminhos divergem, que é o dia em que ela mais importa.
 */

type Marca = {
  rotulo: string;
  titulo: string;
  antes: string;
  depois: string;
  bloco?: boolean;
  exemplo?: string;
};

const MARCAS: Marca[] = [
  { rotulo: "N", titulo: "Negrito", antes: "**", depois: "**", exemplo: "negrito" },
  { rotulo: "I", titulo: "Itálico", antes: "*", depois: "*", exemplo: "itálico" },
  { rotulo: "H2", titulo: "Subtítulo", antes: "## ", depois: "", bloco: true, exemplo: "Subtítulo" },
  { rotulo: "H3", titulo: "Sub-subtítulo", antes: "### ", depois: "", bloco: true, exemplo: "Sub-subtítulo" },
  { rotulo: "•", titulo: "Item de lista", antes: "- ", depois: "", bloco: true, exemplo: "item" },
  { rotulo: "1.", titulo: "Lista numerada", antes: "1. ", depois: "", bloco: true, exemplo: "item" },
  { rotulo: "❝", titulo: "Citação", antes: "> ", depois: "", bloco: true, exemplo: "citação" },
  { rotulo: "🔗", titulo: "Link", antes: "[", depois: "](/blog/)", exemplo: "o que se lê" },
  { rotulo: "—", titulo: "Separador", antes: "\n---\n", depois: "", bloco: true },
];

export function Marcador({
  nome,
  valor,
  aoMudar,
  formato,
  aoInserirFigura,
}: {
  nome: string;
  valor: string;
  aoMudar: (v: string) => void;
  formato: string;
  /** A função que o pai passa para o botão "figura" pedir uma da biblioteca. */
  aoInserirFigura?: () => void;
}) {
  const caixa = useRef<HTMLTextAreaElement>(null);
  const [vendo, setVendo] = useState(false);

  const podeMarcar = formato === "marcacao";

  /**
   * Aplica uma marca à seleção.
   *
   * Sem seleção, insere o exemplo já selecionado, para o próximo caractere
   * digitado substituí-lo. Um botão que insere `****` e deixa o cursor no fim
   * obriga a pessoa a navegar para dentro dos asteriscos, e é o motivo pelo qual
   * ninguém usa a barra do editor da concorrência.
   */
  const aplicar = (m: Marca) => {
    const el = caixa.current;
    if (!el) return;

    const ini = el.selectionStart;
    const fim = el.selectionEnd;
    const selecionado = valor.slice(ini, fim);
    const miolo = selecionado || m.exemplo || "";

    let inicioReal = ini;
    let texto = valor;

    if (m.bloco) {
      // Marca de bloco começa em linha própria. Achar o começo da linha em vez
      // de inserir no cursor é a diferença entre "## Título" e "meio de frase ##".
      inicioReal = texto.lastIndexOf("\n", ini - 1) + 1;
      const precisaQuebra = inicioReal > 0 && texto[inicioReal - 1] !== "\n" ? "" : "";
      texto =
        texto.slice(0, inicioReal) +
        precisaQuebra +
        m.antes +
        miolo +
        m.depois +
        texto.slice(fim);
    } else {
      texto = texto.slice(0, ini) + m.antes + miolo + m.depois + texto.slice(fim);
      inicioReal = ini;
    }

    aoMudar(texto);

    // Devolve o foco com o miolo selecionado. O `requestAnimationFrame` espera
    // o React repintar o valor — sem ele, a seleção é aplicada no texto antigo.
    const de = inicioReal + m.antes.length;
    const ate = de + miolo.length;
    requestAnimationFrame(() => {
      el.focus();
      el.setSelectionRange(de, ate);
    });
  };

  const n = podeMarcar ? palavras(valor) : valor.trim().split(/\s+/).filter(Boolean).length;
  const nb = podeMarcar ? blocos(valor).length : 0;

  return (
    <div>
      <div className="flex flex-wrap items-center gap-1.5">
        <span className="rotulo mr-1">O texto</span>

        {podeMarcar &&
          MARCAS.map((m) => (
            <button
              key={m.titulo}
              type="button"
              title={m.titulo}
              aria-label={m.titulo}
              onClick={() => aplicar(m)}
              className="min-w-[2rem] rounded border border-linha2 px-2 py-1 text-[12px] font-medium text-tinta2 transition-colors hover:bg-folha2 hover:text-tinta"
            >
              {m.rotulo}
            </button>
          ))}

        {podeMarcar && aoInserirFigura && (
          <button
            type="button"
            title="Figura da biblioteca"
            onClick={aoInserirFigura}
            className="rounded border border-linha2 px-2 py-1 text-[12px] font-medium text-tinta2 transition-colors hover:bg-folha2 hover:text-tinta"
          >
            figura
          </button>
        )}

        <button
          type="button"
          onClick={() => setVendo(!vendo)}
          aria-pressed={vendo}
          className={`ml-auto rounded-full px-3 py-1 text-[12px] font-medium transition-colors ${
            vendo
              ? "bg-cheia text-white"
              : "border border-linha2 text-tinta2 hover:bg-folha2"
          }`}
        >
          {vendo ? "voltar a escrever" : "ver como fica"}
        </button>
      </div>

      {vendo ? (
        <div className="mt-2 rounded-[5px] border border-linha2 bg-folha px-5 py-4">
          {valor.trim() === "" ? (
            <p className="text-[13px] text-tinta3">Ainda não há texto.</p>
          ) : (
            <Texto corpo={valor} formato={formato} />
          )}
          {/* A caixa continua no formulário mesmo escondida: tirá-la do DOM
              faria o `name` sumir e o envio ir sem o corpo. */}
          <textarea name={nome} value={valor} readOnly hidden />
        </div>
      ) : (
        <textarea
          ref={caixa}
          name={nome}
          required
          rows={18}
          value={valor}
          onChange={(e) => aoMudar(e.target.value)}
          spellCheck
          className="mt-2 w-full rounded-[5px] border border-linha2 bg-folha px-3 py-2 font-serif text-[14.5px] leading-[1.7] text-tinta"
        />
      )}

      <p className="mt-1.5 max-w-[68ch] text-[11.5px] leading-relaxed text-tinta3">
        {podeMarcar ? (
          <>
            <b className="font-medium">A marcação vira elemento, nunca HTML.</b> O que
            você escreve é lido por um interpretador que só sabe produzir parágrafo,
            subtítulo, lista, citação, link e figura — não existe caminho por onde um{" "}
            <code>{"<script>"}</code> atravesse.{" "}
            {n > 0 && (
              <b className="font-medium">
                {n} palavra{n > 1 ? "s" : ""} em {nb} bloco{nb > 1 ? "s" : ""}.
              </b>
            )}
          </>
        ) : (
          <>
            <b className="font-medium">Este texto está em formato antigo</b> — linha em
            branco separa parágrafo, e nada mais é interpretado. Ele já estreou, e o
            formato de um texto publicado não muda: trocar reescreveria o que as
            pessoas já leram. Para reescrever com marcação, duplique num rascunho novo.
            {n > 0 && <b className="font-medium"> {n} palavras.</b>}
          </>
        )}
      </p>
    </div>
  );
}
