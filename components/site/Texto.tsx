import Link from "next/link";
import Image from "next/image";
import { lerCorpo, type Bloco, type Trecho } from "@/lib/marcacao";

/**
 * O renderizador da marcação — o outro lado da recusa da 0051.
 *
 * Cada caso do `switch` cria um elemento React com **filhos de texto**. Não há
 * nenhum ponto deste arquivo em que uma string vire marcação de página: o que o
 * interpretador devolveu é dado, e o que sai daqui é árvore de componentes. É
 * por isso que o teste que reprova `dangerouslySetInnerHTML` no repositório
 * continua passando com negrito, lista e figura funcionando.
 *
 * O mesmo componente serve a prévia do editor e a página pública, e isso é
 * decisão: uma prévia que renderiza por outro caminho é uma prévia que mente.
 */

function TrechoView({ t, i }: { t: Trecho; i: number }) {
  if (t.t === "negrito") return <strong key={i} className="font-semibold text-tinta">{t.v}</strong>;
  if (t.t === "italico") return <em key={i}>{t.v}</em>;
  if (t.t === "link") {
    const classe = "underline decoration-linha2 underline-offset-2 hover:text-vaga";
    // `noopener` em tudo o que é de fora. `nofollow` fica de fora de propósito:
    // a orientação é usá-lo no que não se avaliza, e um link que eu escolhi pôr
    // no meio do texto é exatamente o que eu avalizo.
    if (t.externo) {
      return (
        <a key={i} href={t.href} className={classe} target="_blank" rel="noopener noreferrer">
          {t.v}
        </a>
      );
    }
    return <Link key={i} href={t.href} className={classe}>{t.v}</Link>;
  }
  return <span key={i}>{t.v}</span>;
}

function Trechos({ ts }: { ts: Trecho[] }) {
  return <>{ts.map((t, i) => <TrechoView key={i} t={t} i={i} />)}</>;
}

function BlocoView({ b }: { b: Bloco }) {
  switch (b.b) {
    case "paragrafo":
      return (
        <p className="mt-4 text-[15px] leading-[1.75] text-tinta2">
          <Trechos ts={b.trechos} />
        </p>
      );

    case "subtitulo": {
      // A âncora deixa citar um trecho direto. `scroll-mt` para o título não
      // encostar no topo quando alguém chega pelo link.
      const comum = "scroll-mt-24 font-serif tracking-[-0.01em] text-tinta";
      if (b.nivel === 2) {
        return <h2 id={b.ancora} className={`mt-10 text-[21px] leading-snug ${comum}`}>{b.texto}</h2>;
      }
      return <h3 id={b.ancora} className={`mt-8 text-[17px] leading-snug ${comum}`}>{b.texto}</h3>;
    }

    case "lista":
      if (b.ordenada) {
        return (
          <ol className="mt-4 list-decimal space-y-1.5 pl-5 text-[15px] leading-[1.7] text-tinta2 marker:text-tinta3">
            {b.itens.map((it, i) => <li key={i}><Trechos ts={it} /></li>)}
          </ol>
        );
      }
      return (
        <ul className="mt-4 list-disc space-y-1.5 pl-5 text-[15px] leading-[1.7] text-tinta2 marker:text-tinta3">
          {b.itens.map((it, i) => <li key={i}><Trechos ts={it} /></li>)}
        </ul>
      );

    case "citacao":
      return (
        <blockquote className="mt-6 border-l-2 border-linha2 pl-4 text-[15px] leading-[1.7] text-tinta2 italic">
          <Trechos ts={b.trechos} />
        </blockquote>
      );

    case "figura":
      // `sizes` diz ao navegador a largura real que a imagem ocupa, para ele
      // não baixar a versão de 1200 num celular. As medidas são as da coluna de
      // leitura, e não as do arquivo.
      return (
        <figure className="mt-8">
          <Image
            src={b.url}
            alt={b.alt}
            width={1200}
            height={800}
            sizes="(max-width: 700px) 100vw, 680px"
            className="h-auto w-full rounded-cartao border border-linha"
          />
          {b.alt !== "" && (
            <figcaption className="mt-2 text-[12.5px] leading-relaxed text-tinta3">{b.alt}</figcaption>
          )}
        </figure>
      );

    case "separador":
      return <hr className="mt-10 border-0 border-t border-linha" />;
  }
}

export function Texto({ corpo, formato }: { corpo: string; formato: string }) {
  const arvore = lerCorpo(corpo, formato);
  return (
    <div>
      {arvore.map((b, i) => <BlocoView key={i} b={b} />)}
    </div>
  );
}

/**
 * O índice do texto, quando ele tem subtítulos suficientes para valer.
 *
 * Três é o piso: com dois, o índice ocupa mais espaço do que economiza. E ele
 * é `nav`, com rótulo — quem navega por leitor de tela pula a região inteira se
 * não quiser.
 */
export function Indice({ corpo, formato }: { corpo: string; formato: string }) {
  const subs = lerCorpo(corpo, formato).filter((b) => b.b === "subtitulo");
  if (subs.length < 3) return null;

  return (
    <nav aria-label="Neste texto" className="mt-8 rounded-cartao border border-linha bg-folha2 px-5 py-4">
      <p className="rotulo">Neste texto</p>
      <ul className="mt-2 space-y-1">
        {subs.map((s, i) => (
          <li key={i} className={s.nivel === 3 ? "pl-4" : ""}>
            <a href={`#${s.ancora}`} className="text-[13px] text-tinta2 underline decoration-linha2 underline-offset-2 hover:text-vaga">
              {s.texto}
            </a>
          </li>
        ))}
      </ul>
    </nav>
  );
}
