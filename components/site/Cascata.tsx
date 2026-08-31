"use client";

import { useCallback, useEffect, useRef, useState } from "react";

type Estado = "na_fila" | "ofertando" | "recusou" | "aceitou" | "fora";

const FILA: {
  nome: string;
  janela: string;
  espera: string;
  cabe: boolean;
  motivo?: string;
}[] = [
  {
    nome: "Caio Nogueira",
    janela: "terça ou quarta, à tarde",
    espera: "11 dias sem sessão",
    cabe: true,
  },
  {
    nome: "João Pedro Salles",
    janela: "qualquer dia, depois das 14h",
    espera: "6 dias sem sessão",
    cabe: true,
  },
  {
    nome: "Bia Nogueira",
    janela: "só pela manhã",
    espera: "4 dias sem sessão",
    cabe: false,
    motivo: "fora da janela",
  },
  {
    nome: "Rafael Tomé",
    janela: "qualquer horário",
    espera: "em férias até 14/09",
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
    texto: "Oferta discreta enviada ao Caio — 11 dias sem sessão.",
    estados: { "Caio Nogueira": "ofertando" },
  },
  {
    ms: 2600,
    hora: "11:52",
    texto: "Caio não consegue hoje. Segue na fila para a próxima.",
    estados: { "Caio Nogueira": "recusou" },
  },
  {
    ms: 3400,
    hora: "11:52",
    texto: "Oferta enviada ao João Pedro — 6 dias sem sessão.",
    estados: { "Caio Nogueira": "recusou", "João Pedro Salles": "ofertando" },
  },
  {
    ms: 5400,
    hora: "11:58",
    texto: "João Pedro confirmou. A terça das 15h está preenchida.",
    bom: true,
    estados: { "Caio Nogueira": "recusou", "João Pedro Salles": "aceitou" },
  },
];

export function Cascata() {
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
          <b className="font-semibold text-tinta">Regra de prioridade:</b> quem
          está há mais tempo sem sessão — definida por ela, no cadastro. A fila
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
                  ? "oferta enviada…"
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
              ? "Você não pediu nada a ninguém, não mandou mensagem e não negociou. Recebeu um aviso dizendo que a terça das 15h agora é do João Pedro."
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
