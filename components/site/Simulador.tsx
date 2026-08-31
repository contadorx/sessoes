"use client";

import { useId, useState } from "react";

const brl = (n: number) =>
  n.toLocaleString("pt-BR", {
    style: "currency",
    currency: "BRL",
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  });

/** A taxa que a fila precisa bater para o produto existir (métrica norte do projeto). */
const TAXA = 0.6;
const SOLO = 69;

export function Simulador() {
  const idValor = useId();
  const idFuros = useId();

  const [valor, setValor] = useState(200);
  const [furos, setFuros] = useState(4);

  const perdaMes = valor * furos;
  const perdaAno = perdaMes * 12;
  const recuperaMes = Math.round(perdaMes * TAXA);
  const recuperaAno = recuperaMes * 12;
  const vezes = recuperaMes / SOLO;

  return (
    <div className="grid gap-5 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.05fr)]">
      {/* controles */}
      <div className="self-start rounded-cartao border border-linha bg-folha p-5 sm:p-6">
        <div>
          <label htmlFor={idValor} className="rotulo">
            Quanto custa a sua sessão
          </label>
          <div className="mt-2 flex items-baseline gap-2">
            <span className="font-mono text-[15px] text-tinta3">R$</span>
            <span className="tabular font-mono text-[30px] font-medium leading-none text-tinta">
              {valor}
            </span>
          </div>
          <input
            id={idValor}
            type="range"
            min={60}
            max={600}
            step={10}
            value={valor}
            onChange={(e) => setValor(Number(e.target.value))}
            className="mt-3 h-1.5 w-full cursor-pointer appearance-none rounded-full bg-linha accent-vaga"
          />
        </div>

        <div className="mt-7">
          <label htmlFor={idFuros} className="rotulo">
            Horários que furam por mês
          </label>
          <div className="mt-2 flex items-baseline gap-2">
            <span className="tabular font-mono text-[30px] font-medium leading-none text-tinta">
              {furos}
            </span>
            <span className="text-[13px] text-tinta3">
              {furos === 1 ? "horário" : "horários"}
            </span>
          </div>
          <input
            id={idFuros}
            type="range"
            min={0}
            max={16}
            step={1}
            value={furos}
            onChange={(e) => setFuros(Number(e.target.value))}
            className="mt-3 h-1.5 w-full cursor-pointer appearance-none rounded-full bg-linha accent-vaga"
          />
          <p className="mt-3 text-[12px] leading-relaxed text-tinta3">
            Falta, cancelamento em cima da hora, remarcação que não achou lugar.
            Quem atende 25 pessoas por semana costuma responder entre 3 e 6.
          </p>
        </div>
      </div>

      {/* resultado */}
      <div className="flex flex-col gap-4">
        <div className="rounded-cartao border border-vaga-linha bg-vaga-bg p-5 sm:p-6">
          <span className="rotulo text-vaga/70">Hoje, essa hora vira</span>
          <span className="tabular mt-1 block font-mono text-[38px] font-medium leading-none tracking-[-0.02em] text-vaga sm:text-[46px]">
            {brl(perdaAno)}
          </span>
          <p className="mt-2 text-[13px] text-tinta2">
            por ano — {brl(perdaMes)} por mês que deixam de existir. A hora da
            terapia não é revendável: você já estava lá.
          </p>
        </div>

        <div className="rounded-cartao border border-cheia-linha bg-cheia-bg p-5 sm:p-6">
          <span className="rotulo text-cheia/70">Com a fila preenchendo 60%</span>
          <span className="tabular mt-1 block font-mono text-[38px] font-medium leading-none tracking-[-0.02em] text-cheia sm:text-[46px]">
            {brl(recuperaAno)}
          </span>
          <p className="mt-2 text-[13px] text-tinta2">
            de volta por ano, {brl(recuperaMes)} por mês.{" "}
            {furos > 0 && (
              <>
                O plano Solo custa R$ 69 — ele se pagaria{" "}
                <b className="font-semibold text-cheia">
                  {vezes >= 10
                    ? `${Math.round(vezes)} vezes`
                    : vezes >= 1.2
                      ? `${vezes.toFixed(1).replace(".", ",")} vezes`
                      : "quase uma vez"}
                </b>{" "}
                por mês.
              </>
            )}
          </p>
        </div>

        <p className="text-[11.5px] leading-relaxed text-tinta3">
          60% é a meta que o produto se impõe: a proporção de cancelamentos que
          a fila precisa preencher ou ao menos oferecer. Se não bater, o produto
          não se justifica — e é assim que a gente mede.
        </p>
      </div>
    </div>
  );
}
