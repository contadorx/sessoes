"use client";

import { useCallback, useEffect, useRef, useState } from "react";

type Estado = "na_fila" | "ofertando" | "recusou" | "aceitou" | "fora";

/**
 * A fila da demonstração, depois da segunda auditoria — e ela mudou por dois
 * motivos, os dois graves.
 *
 * **1. "11 dias sem sessão" contradizia a própria página.** Duas seções abaixo
 * está escrito "não opinamos sobre frequência", e o Código de Ética veda
 * induzir alguém a recorrer aos serviços. Ordenar pessoas por tempo sem
 * atendimento transforma frequência em critério operacional — e mesmo sendo a
 * psicóloga quem configura a regra, a demonstração fazia o **sistema** parecer
 * decidir quem "precisa" ser atendido antes. Numa landing, o que se demonstra
 * é o que se promete.
 *
 * **2. Nomes completos numa página que vende minimização de dados.** São
 * fictícios, e não é esse o ponto: uma demonstração de discrição que exibe
 * "João Pedro Salles" na tela ensina o contrário do que a seção ao lado
 * defende. Agora são iniciais — a mesma forma que a figura da hero já usava.
 *
 * O que ficou no lugar do tempo de espera é o que de fato decide: **a ordem
 * que ela definiu** e **a disponibilidade que a pessoa informou**. O sistema
 * respeita as duas e não sabe de mais nada.
 */
const FILA: {
  nome: string;
  janela: string;
  espera: string;
  cabe: boolean;
  motivo?: string;
}[] = [
  {
    nome: "C. N.",
    janela: "terça ou quarta, à tarde",
    espera: "1ª na ordem",
    cabe: true,
  },
  {
    nome: "J. P. S.",
    janela: "qualquer dia, depois das 14h",
    espera: "2ª na ordem",
    cabe: true,
  },
  {
    nome: "B. N.",
    janela: "só pela manhã",
    espera: "3ª na ordem",
    cabe: false,
    motivo: "fora da janela",
  },
  {
    nome: "R. T.",
    janela: "qualquer horário",
    espera: "em pausa até 14/09",
    cabe: false,
    motivo: "em pausa",
  },
];

type Passo = { ms: number; hora: string; texto: string; bom?: boolean; estados: Record<string, Estado> };

const PASSOS: Passo[] = [
  {
    ms: 0,
    hora: "11:46",
    texto: "Vaga detectada. Dois pacientes cabem na janela das 15h.",
    estados: {},
  },
  {
    ms: 900,
    hora: "11:46",
    texto: "Oferta discreta enviada à primeira da ordem que cabe na janela.",
    estados: { "C. N.": "ofertando" },
  },
  {
    ms: 2600,
    hora: "11:52",
    texto: "C. N. não consegue hoje. Segue na fila para a próxima.",
    estados: { "C. N.": "recusou" },
  },
  {
    ms: 3400,
    hora: "11:52",
    texto: "A vez passa para a segunda da ordem. Uma pessoa por vez, sempre.",
    estados: { "C. N.": "recusou", "J. P. S.": "ofertando" },
  },
  {
    ms: 5400,
    hora: "11:58",
    texto: "J. P. S. confirmou. A terça das 15h está preenchida.",
    bom: true,
    estados: { "C. N.": "recusou", "J. P. S.": "aceitou" },
  },
];

/**
 * A demonstração da cascata na página pública.
 *
 * O rótulo do passo do meio dizia "oferta enviada…", e enquanto não há provedor
 * nada sai sozinho: a mensagem nasce escrita e sai do WhatsApp dela, com um
 * toque. Quem assiste a esta animação antes de assinar conclui o contrário — e
 * "a promessa que o software não cumpre" é antipadrão nomeado deste projeto,
 * que já apareceu quatro vezes, a última na página de preços (0078).
 *
 * O booleano desce por prop porque `lib/promessa.ts` é `server-only` e isto é
 * componente de cliente. A landing o passa; no dia em que o provedor entrar, a
 * animação volta a dizer "enviada" sem ninguém reescrever nada.
 */
export function Cascata({ envioAutomatico }: { envioAutomatico: boolean }) {
  const [passo, setPasso] = useState(-1);
  const [rodando, setRodando] = useState(false);
  const timers = useRef<ReturnType<typeof setTimeout>[]>([]);
  const alvo = useRef<HTMLDivElement>(null);
  const jaRodou = useRef(false);

  const limpar = () => {
    timers.current.forEach(clearTimeout);
    timers.current = [];
  };

  const rodar = useCallback(() => {
    limpar();
    setPasso(-1);
    setRodando(true);

    const lento = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    PASSOS.forEach((p, i) => {
      timers.current.push(
        setTimeout(
          () => {
            setPasso(i);
            if (i === PASSOS.length - 1) setRodando(false);
          },
          lento ? i * 12 : p.ms,
        ),
      );
    });
  }, []);

  useEffect(() => {
    const no = alvo.current;
    if (!no) return;

    const obs = new IntersectionObserver(
      (entradas) => {
        if (entradas[0]?.isIntersecting && !jaRodou.current) {
          jaRodou.current = true;
          rodar();
        }
      },
      { threshold: 0.45 },
    );

    obs.observe(no);
    return () => {
      obs.disconnect();
      limpar();
    };
  }, [rodar]);

  const atual = passo >= 0 ? PASSOS[passo] : null;
  const estados = atual?.estados ?? {};
  const fechou = passo === PASSOS.length - 1;

  return (
    <div ref={alvo} className="grid gap-5 lg:grid-cols-[minmax(0,1.15fr)_minmax(0,1fr)]">
      {/* a fila */}
      <div>
        <div className="rounded-cartao border border-linha bg-folha2 px-4 py-3 text-[12.5px] leading-relaxed text-tinta2">
          <b className="font-semibold text-tinta">A ordem é definida por você.</b>{" "}
          O Sessões respeita essa ordem, confere a disponibilidade que a pessoa
          informou, e oferece o horário a uma pessoa por vez. A fila
          nunca vira leilão: dinheiro não compra posição.
        </div>

        <ul className="mt-3 flex flex-col gap-2">
          {FILA.map((p, i) => {
            const e: Estado = !p.cabe ? "fora" : (estados[p.nome] ?? "na_fila");

            const caixa =
              e === "ofertando"
                ? "border-vaga-linha bg-vaga-bg"
                : e === "aceitou"
                  ? "border-cheia-linha bg-cheia-bg"
                  : "border-linha bg-folha";

            const apagado = e === "fora" || e === "recusou" ? "opacity-55" : "";

            const rotulo =
              e === "fora"
                ? `✕ ${p.motivo}`
                : e === "ofertando"
                  ? envioAutomatico
                    ? "oferta enviada…"
                    : "oferta pronta, esperando um toque seu…"
                  : e === "recusou"
                    ? "não pôde hoje"
                    : e === "aceitou"
                      ? "✓ aceitou a vaga"
                      : "na fila";

            const cor =
              e === "ofertando"
                ? "text-vaga"
                : e === "aceitou"
                  ? "text-cheia"
                  : "text-tinta3";

            return (
              <li
                key={p.nome}
                className={`grid grid-cols-[22px_minmax(0,1fr)_auto] items-center gap-3 rounded-cartao border px-3 py-2.5 transition-colors duration-300 ${caixa} ${apagado}`}
              >
                <span className="font-mono text-[12px] text-tinta3">{i + 1}</span>
                <span className="min-w-0">
                  <span
                    className={`block truncate text-[13.5px] font-medium leading-tight ${e === "aceitou" ? "text-cheia" : "text-tinta"}`}
                  >
                    {p.nome}
                  </span>
                  <span className="block truncate text-[11.5px] leading-tight text-tinta3">
                    {p.janela} · {p.espera}
                  </span>
                </span>
                <span className={`whitespace-nowrap text-[11.5px] font-semibold ${cor}`}>
                  {rotulo}
                </span>
              </li>
            );
          })}
        </ul>

        <button
          type="button"
          onClick={rodar}
          disabled={rodando}
          className="mt-4 inline-flex items-center gap-2 rounded-full bg-vaga px-5 py-2.5 text-[13px] font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-40"
        >
          {rodando ? "Oferecendo…" : fechou ? "Rodar de novo" : "Oferecer em cascata"}
        </button>
      </div>

      {/* o log */}
      <div className="rounded-cartao border border-linha bg-folha p-5">
        <span className="rotulo">Terça, 1º de setembro</span>

        <ul className="mt-3 min-h-[168px]">
          {PASSOS.slice(0, passo + 1).map((p, i) => (
            <li
              key={i}
              className={`sobe grid grid-cols-[46px_minmax(0,1fr)] gap-3 border-t border-dotted border-linha2 py-2 text-[12.5px] first:border-t-0 ${
                p.bom ? "font-medium text-cheia" : "text-tinta2"
              }`}
            >
              <span className="font-mono text-[11px] text-tinta3">{p.hora}</span>
              <span>{p.texto}</span>
            </li>
          ))}
          {passo < 0 && (
            <li className="py-2 text-[12.5px] text-tinta3">
              Maria Fernanda desmarcou às 11h42, com três horas de antecedência.
            </li>
          )}
        </ul>

        <div
          className={`mt-1 rounded-cartao border px-4 py-4 transition-opacity duration-500 ${
            fechou
              ? "border-cheia-linha bg-cheia-bg opacity-100"
              : "border-linha bg-folha2 opacity-45"
          }`}
        >
          <p className="text-[12.5px] leading-relaxed text-tinta2">
            {fechou
              ? "Você não pediu nada a ninguém, não mandou mensagem e não negociou. Recebeu um aviso dizendo que a terça das 15h está preenchida."
              : "A hora vazia continua vazia."}
          </p>
          <span
            className={`tabular mt-2 block font-mono text-[26px] font-medium ${
              fechou ? "text-cheia" : "text-tinta3"
            }`}
          >
            {fechou ? "+ R$ 200,00" : "R$ 0,00"}
          </span>
        </div>
      </div>
    </div>
  );
}
