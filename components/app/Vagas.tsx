"use client";

import Link from "next/link";
import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import { oferecerVaga, abrirVaga, fecharVaga, type Resultado } from "@/app/(app)/encaixes/fixos/acoes";
import {
  horarioSemanal,
  estadoDaVaga,
  rotuloDaVaga,
  proximoPasso,
  rotuloMotivo,
  MOTIVOS,
  type VagaLinha,
} from "@/lib/vagafixa";
import { DIAS } from "@/lib/enquadre";
import { formatar, paraCentavos } from "@/lib/dinheiro";

const INICIAL: Resultado = { estado: "inicial" };

const DIA = new Intl.DateTimeFormat("pt-BR", {
  timeZone: "America/Sao_Paulo",
  day: "2-digit",
  month: "2-digit",
});

function Botao({ rotulo, destaque }: { rotulo: string; destaque?: boolean }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className={
        destaque
          ? "rounded-full bg-vaga px-4 py-1.5 text-[12.5px] font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-45"
          : "rounded-full border border-linha2 px-4 py-1.5 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2 disabled:opacity-45"
      }
    >
      {pending ? "…" : rotulo}
    </button>
  );
}

function Recado({ r }: { r: Resultado }) {
  if (r.estado === "ok") return <p className="mt-2 text-[12.5px] leading-relaxed text-cheia">{r.mensagem}</p>;
  if (r.estado === "erro")
    return (
      <ul className="mt-2 space-y-1">
        {r.erros.map((e, i) => (
          <li key={i} className="text-[12.5px] leading-relaxed text-vaga">
            {e}
          </li>
        ))}
      </ul>
    );
  return null;
}

const CAMPO =
  "w-full rounded-cartao border border-linha2 bg-folha px-3 py-2 text-[13px] text-tinta focus:border-tinta3 focus:outline-none";

export function PainelVagas({ vagas }: { vagas: VagaLinha[] }) {
  const [rOferecer, oferecer] = useActionState(oferecerVaga, INICIAL);
  const [rAbrir, abrir] = useActionState(abrirVaga, INICIAL);
  const [rFechar, fechar] = useActionState(fecharVaga, INICIAL);
  const [abrindo, setAbrindo] = useState(false);

  const vivas = vagas.filter((v) => v.fechada_em === null);
  const fechadas = vagas.filter((v) => v.fechada_em !== null);

  return (
    <>
      <div className="mt-6 space-y-3">
        {vivas.length === 0 && (
          <p className="rounded-cartao border border-linha bg-folha2 px-5 py-4 text-[13px] leading-relaxed text-tinta2">
            Nenhuma vaga fixa aberta. Quando você arquivar uma ficha ou encerrar
            um combinado, o horário aparece aqui sozinho.
          </p>
        )}

        {vivas.map((v) => {
          const e = estadoDaVaga(v);
          const passo = proximoPasso(v);

          return (
            <div
              key={v.id}
              className={`rounded-cartao border px-5 py-4 ${
                e === "aberta" ? "border-vaga-linha bg-vaga-bg" : "border-linha bg-folha2"
              }`}
            >
              <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                <span className="font-serif text-[18px] text-tinta">
                  {horarioSemanal(v.dia_semana, v.hora)}
                </span>
                <span className="text-[12px] text-tinta3">
                  {v.duracao_min} min · {rotuloMotivo(v.motivo)}
                  {v.valor_anterior && ` · era ${formatar(paraCentavos(v.valor_anterior))}`}
                </span>
                <span className="ml-auto font-mono text-[11.5px] text-tinta3">
                  aberta {DIA.format(new Date(v.aberta_em))}
                </span>
              </div>

              <p className="mt-2 text-[12.5px] leading-relaxed text-tinta2">
                {rotuloDaVaga(v)}
              </p>

              <div className="mt-3 flex flex-wrap items-center gap-2">
                {e === "aberta" && (
                  <form action={oferecer}>
                    <input type="hidden" name="vaga" value={v.id} />
                    <Botao rotulo={passo} destaque />
                  </form>
                )}

                <form action={fechar}>
                  <input type="hidden" name="vaga" value={v.id} />
                  <Botao rotulo="Fechar a vaga" />
                </form>
              </div>
            </div>
          );
        })}
      </div>

      <Recado r={rOferecer} />
      <Recado r={rFechar} />

      {/* ------------------------------------------------------ abrir à mão */}
      <div className="mt-5">
        {!abrindo ? (
          <button
            type="button"
            onClick={() => setAbrindo(true)}
            className="text-[12.5px] font-medium text-vaga hover:underline"
          >
            Abrir uma vaga à mão →
          </button>
        ) : (
          <form action={abrir} className="rounded-cartao border border-linha bg-folha2 px-5 py-4">
            <p className="text-[12.5px] leading-relaxed text-tinta2">
              Para quando o horário vagou sem passar pelo sistema — alguém que
              sumiu, ou um horário que você abriu na agenda e nunca teve dono.
            </p>
            <div className="mt-3 grid gap-3 sm:grid-cols-4">
              <div>
                <label htmlFor="dia_semana" className="text-[12px] font-medium text-tinta2">
                  Dia
                </label>
                <select id="dia_semana" name="dia_semana" defaultValue={2} className={`mt-1 ${CAMPO}`}>
                  {DIAS.map((d, i) => (
                    <option key={d} value={i}>
                      {d}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label htmlFor="hora" className="text-[12px] font-medium text-tinta2">
                  Hora
                </label>
                <input id="hora" name="hora" type="time" step={900} className={`mt-1 ${CAMPO}`} />
              </div>
              <div>
                <label htmlFor="duracao_min" className="text-[12px] font-medium text-tinta2">
                  Duração
                </label>
                <input
                  id="duracao_min"
                  name="duracao_min"
                  type="number"
                  onWheel={(e) => e.currentTarget.blur()}
                  min={15}
                  max={240}
                  step={5}
                  defaultValue={50}
                  className={`mt-1 ${CAMPO}`}
                />
              </div>
              <div>
                <label htmlFor="motivo" className="text-[12px] font-medium text-tinta2">
                  Por quê
                </label>
                <select id="motivo" name="motivo" defaultValue="abandono" className={`mt-1 ${CAMPO}`}>
                  {MOTIVOS.map((m) => (
                    <option key={m.valor} value={m.valor}>
                      {m.rotulo}
                    </option>
                  ))}
                </select>
              </div>
            </div>
            <div className="mt-3 flex items-center gap-3">
              <Botao rotulo="Abrir" />
              <button
                type="button"
                onClick={() => setAbrindo(false)}
                className="text-[12.5px] text-tinta3 hover:text-tinta2"
              >
                cancelar
              </button>
            </div>
            <Recado r={rAbrir} />
          </form>
        )}
      </div>

      {/* ------------------------------------------------------- o histórico */}
      {fechadas.length > 0 && (
        <section className="mt-10">
          <h2 className="rotulo">O que já aconteceu</h2>
          <ul className="mt-3 overflow-hidden rounded-cartao border border-linha bg-folha">
            {fechadas.map((v) => (
              <li
                key={v.id}
                className="flex flex-wrap items-baseline gap-x-3 gap-y-1 border-t border-linha px-5 py-3 first:border-t-0"
              >
                <span className="text-[13px] text-tinta2">
                  {horarioSemanal(v.dia_semana, v.hora)}
                </span>
                <span className="text-[12px] text-tinta3">{rotuloDaVaga(v)}</span>
                {v.fechada_por === "preenchida" && v.novo_paciente && (
                  <Link
                    href={`/pacientes/${v.novo_paciente}`}
                    className="ml-auto text-[12px] font-medium text-vaga hover:underline"
                  >
                    abrir o combinado →
                  </Link>
                )}
              </li>
            ))}
          </ul>
        </section>
      )}
    </>
  );
}
