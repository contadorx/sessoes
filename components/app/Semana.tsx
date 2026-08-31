"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import type { SessaoLinha } from "@/app/(app)/agenda/dados";
import { faixaDeHoras, posicaoNaGrade, porDiaDaSemana, type Semana as TSemana } from "@/lib/semana";
import { horaEmSP } from "@/lib/tempo";
import { PainelSessao } from "./PainelSessao";

const PX_POR_HORA = 56;

const CURTO = new Intl.DateTimeFormat("pt-BR", { timeZone: "UTC", weekday: "short" });

/** Cada estado tem sua cor, e o rosa é exclusivo do buraco (doc 09). */
const ESTILO: Record<SessaoLinha["estado"], string> = {
  prevista: "border-linha2 bg-folha text-tinta",
  confirmada: "border-cheia-linha bg-cheia-bg text-cheia",
  realizada: "border-cheia-linha bg-cheia text-white",
  falta: "border-aviso-linha bg-aviso-bg text-aviso",
  cancelada_cedo: "border-vaga-linha bg-vaga-bg text-vaga",
  cancelada_tarde: "border-vaga-linha bg-vaga-bg text-vaga",
};

export const ROTULO_ESTADO: Record<SessaoLinha["estado"], string> = {
  prevista: "prevista",
  confirmada: "confirmada",
  realizada: "realizada",
  falta: "faltou",
  cancelada_cedo: "cancelou a tempo",
  cancelada_tarde: "cancelou tarde",
};

export function Semana({
  semana,
  sessoes,
  hoje,
}: {
  semana: TSemana;
  sessoes: SessaoLinha[];
  hoje: string;
}) {
  const [escolhida, setEscolhida] = useState<string | null>(null);

  const [de, ate] = useMemo(() => faixaDeHoras(sessoes), [sessoes]);
  const porDia = useMemo(() => porDiaDaSemana(sessoes, semana.dias), [sessoes, semana.dias]);
  const horas = useMemo(
    () => Array.from({ length: ate - de }, (_, i) => de + i),
    [de, ate],
  );

  const sessaoAberta = sessoes.find((s) => s.id === escolhida) ?? null;

  return (
    <div>
      {/* ---------------- a grade, no computador ---------------- */}
      <div className="hidden overflow-x-auto rounded-cartao border border-linha bg-folha lg:block">
        <div className="min-w-[760px]">
          {/* cabeçalho dos dias */}
          <div className="grid grid-cols-[52px_repeat(7,minmax(0,1fr))] border-b border-linha">
            <div />
            {semana.dias.map((dia) => {
              const ehHoje = dia === hoje;
              return (
                <div
                  key={dia}
                  className={`border-l border-linha px-2 py-2 text-center ${ehHoje ? "bg-folha2" : ""}`}
                >
                  <div className="rotulo">
                    {CURTO.format(new Date(`${dia}T12:00:00Z`)).replace(".", "")}
                  </div>
                  <div
                    className={`tabular font-mono text-[15px] ${ehHoje ? "font-medium text-vaga" : "text-tinta2"}`}
                  >
                    {Number(dia.slice(8, 10))}
                  </div>
                </div>
              );
            })}
          </div>

          {/* corpo */}
          <div
            className="relative grid grid-cols-[52px_repeat(7,minmax(0,1fr))]"
            style={{ height: horas.length * PX_POR_HORA }}
          >
            {/* régua de horas */}
            <div className="relative">
              {horas.map((h, i) => (
                <div
                  key={h}
                  className="absolute right-2 -translate-y-1/2 font-mono text-[11px] tabular text-tinta3"
                  style={{ top: i * PX_POR_HORA }}
                >
                  {i === 0 ? "" : `${h}h`}
                </div>
              ))}
            </div>

            {/* colunas */}
            {semana.dias.map((dia) => (
              <div key={dia} className="relative border-l border-linha">
                {/* fios das horas */}
                {horas.map((h, i) => (
                  <div
                    key={h}
                    className="absolute inset-x-0 border-t border-linha"
                    style={{ top: i * PX_POR_HORA }}
                  />
                ))}

                {(porDia[dia] ?? []).map((s) => {
                  const { topo, altura } = posicaoNaGrade(s, de);
                  const selecionada = s.id === escolhida;

                  return (
                    <button
                      key={s.id}
                      type="button"
                      onClick={() => setEscolhida(selecionada ? null : s.id)}
                      aria-pressed={selecionada}
                      className={`absolute inset-x-1 overflow-hidden rounded-[4px] border px-1.5 py-1 text-left transition-shadow ${ESTILO[s.estado]} ${
                        selecionada ? "ring-2 ring-tinta/25" : ""
                      }`}
                      style={{
                        top: topo * PX_POR_HORA + 1,
                        height: Math.max(22, altura * PX_POR_HORA - 2),
                      }}
                    >
                      <span className="block truncate font-mono text-[10.5px] leading-tight opacity-80">
                        {horaEmSP(new Date(s.inicio))}
                      </span>
                      <span className="block truncate text-[12px] font-medium leading-tight">
                        {s.pacientes?.nome ?? "—"}
                      </span>
                    </button>
                  );
                })}
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* ---------------- a lista, no celular ---------------- */}
      <div className="space-y-5 lg:hidden">
        {semana.dias.map((dia) => {
          const doDia = porDia[dia] ?? [];
          if (doDia.length === 0) return null;

          return (
            <section key={dia}>
              <h3 className="rotulo">
                {CURTO.format(new Date(`${dia}T12:00:00Z`)).replace(".", "")}{" "}
                {Number(dia.slice(8, 10))}
                {dia === hoje && " · hoje"}
              </h3>
              <ul className="mt-2 overflow-hidden rounded-cartao border border-linha bg-folha">
                {doDia.map((s) => (
                  <li key={s.id} className="border-t border-linha first:border-t-0">
                    <button
                      type="button"
                      onClick={() => setEscolhida(s.id === escolhida ? null : s.id)}
                      className="flex w-full flex-wrap items-baseline gap-x-3 gap-y-1 px-4 py-3 text-left"
                    >
                      <span className="font-mono text-[13px] tabular text-tinta2">
                        {horaEmSP(new Date(s.inicio))}
                      </span>
                      <span
                        className={`text-[14px] font-medium ${
                          s.estado.startsWith("cancelada")
                            ? "text-tinta3 line-through"
                            : "text-tinta"
                        }`}
                      >
                        {s.pacientes?.nome ?? "—"}
                      </span>
                      <span className="ml-auto text-[11.5px] text-tinta3">
                        {ROTULO_ESTADO[s.estado]}
                      </span>
                    </button>
                  </li>
                ))}
              </ul>
            </section>
          );
        })}
      </div>

      {sessoes.length === 0 && (
        <div className="mt-6 rounded-cartao border border-dashed border-linha2 bg-folha px-6 py-10 text-center lg:mt-4">
          <p className="font-serif text-[19px] text-tinta">Nada marcado nesta semana.</p>
          <p className="mx-auto mt-2 max-w-[46ch] text-[13px] leading-relaxed text-tinta2">
            As sessões nascem do combinado de cada paciente. Se a semana deveria
            ter gente, confira se há férias ou feriado marcado abaixo.
          </p>
          <Link
            href="/pacientes/novo"
            className="mt-4 inline-block text-[13px] font-medium text-vaga hover:underline"
          >
            cadastrar paciente →
          </Link>
        </div>
      )}

      {sessaoAberta && (
        <div className="mt-4">
          <PainelSessao sessao={sessaoAberta} aoFechar={() => setEscolhida(null)} />
        </div>
      )}
    </div>
  );
}
