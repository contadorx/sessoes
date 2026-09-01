"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import Link from "next/link";
import {
  entrarNaFila,
  atualizarNaFila,
  sairDaFila,
  type Resultado,
} from "@/app/(app)/encaixes/acoes";
import type { NaFila } from "@/app/(app)/encaixes/dados";
import { rotuloJanela, tempoDeEspera } from "@/lib/janela";
import { DIAS } from "@/lib/enquadre";
import { Campo, Erros, ENTRADA } from "./campos";

const INICIAL: Resultado = { estado: "inicial" };

function Salvar({ rotulo, tom = "vaga" }: { rotulo: string; tom?: "vaga" | "leve" }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className={
        tom === "vaga"
          ? "rounded-full bg-vaga px-5 py-2.5 text-[13px] font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-45"
          : "text-[12px] text-tinta3 transition-colors hover:text-vaga disabled:opacity-45"
      }
    >
      {pending ? "…" : rotulo}
    </button>
  );
}

/** Dias, "a partir de" e "até". Uma janela cobre quase todo mundo. */
function CamposJanela({ base }: { base?: NaFila }) {
  const j = base?.janelas?.[0] ?? {};

  return (
    <>
      <fieldset className="mt-3">
        <legend className="rotulo">Dias que servem</legend>
        <div className="mt-2 flex flex-wrap gap-1.5">
          {DIAS.map((d, i) => (
            <label
              key={d}
              className="cursor-pointer select-none rounded-full border border-linha2 px-2.5 py-1 text-[12px] text-tinta2 has-[:checked]:border-vaga has-[:checked]:bg-vaga-bg has-[:checked]:text-vaga"
            >
              <input
                type="checkbox"
                name="dias"
                value={i}
                defaultChecked={j.dias?.includes(i)}
                className="sr-only"
              />
              {d.slice(0, 3)}
            </label>
          ))}
        </div>
        <p className="mt-1.5 text-[11px] text-tinta3">
          Nenhum marcado = qualquer dia serve.
        </p>
      </fieldset>

      <div className="mt-3 grid gap-3 sm:grid-cols-2">
        <Campo rotulo="A partir de">
          <input type="time" name="de" defaultValue={j.de ?? ""} className={ENTRADA} />
        </Campo>
        <Campo rotulo="Até">
          <input type="time" name="ate" defaultValue={j.ate ?? ""} className={ENTRADA} />
        </Campo>
      </div>

      <label className="mt-3 flex items-start gap-2 text-[12.5px] leading-relaxed text-tinta2">
        <input
          type="checkbox"
          name="topa_antecipar"
          value="sim"
          defaultChecked={base?.topa_antecipar ?? true}
          className="mt-0.5 accent-vaga"
        />
        <span>
          Topa antecipar a sessão da semana
          <span className="block text-[11px] text-tinta3">
            Desmarcado, só recebe oferta em semana onde não tem sessão marcada.
          </span>
        </span>
      </label>
    </>
  );
}

function Linha({ item }: { item: NaFila }) {
  const [aberto, setAberto] = useState(false);
  const [estado, salvar] = useActionState(atualizarNaFila, INICIAL);
  const [, sair] = useActionState(sairDaFila, INICIAL);
  const erros = estado.estado === "erro" ? estado.erros : [];

  return (
    <li className="border-t border-linha first:border-t-0">
      <div className="flex flex-wrap items-baseline gap-x-4 gap-y-1 px-5 py-3">
        <button
          type="button"
          onClick={() => setAberto((v) => !v)}
          className="text-left text-[14px] font-medium text-tinta hover:text-vaga"
        >
          {item.pacientes?.nome ?? "—"}
        </button>

        {!item.ativo && (
          <span className="rounded-full border border-linha bg-folha2 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider text-tinta3">
            pausada
          </span>
        )}
        {item.prioridade > 0 && (
          <span className="rounded-full bg-vaga-bg px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider text-vaga">
            prioridade {item.prioridade}
          </span>
        )}

        <span className="text-[12.5px] text-tinta2">{rotuloJanela(item.janelas)}</span>

        <span className="ml-auto font-mono text-[12px] text-tinta3">
          {tempoDeEspera(item.ultima_sessao ?? null)}
        </span>
      </div>

      {aberto && (
        <div className="border-t border-linha bg-folha2 px-5 py-4">
          <form action={salvar}>
            <input type="hidden" name="id" value={item.id} />
            <CamposJanela base={item} />

            <div className="mt-3 grid gap-3 sm:grid-cols-2">
              <Campo rotulo="Prioridade manual" dica="Empata por cima da regra. 0 = sem desempate.">
                <input
                  type="number"
                  name="prioridade"
                  min={0}
                  max={99}
                  defaultValue={item.prioridade}
                  className={ENTRADA}
                />
              </Campo>
              <label className="flex items-end gap-2 pb-2.5 text-[12.5px] text-tinta2">
                <input
                  type="checkbox"
                  name="ativo"
                  value="sim"
                  defaultChecked={item.ativo}
                  className="accent-vaga"
                />
                na fila
              </label>
            </div>

            <Erros erros={erros} />

            <div className="mt-4 flex items-center gap-4">
              <Salvar rotulo="Salvar" />
              <Link
                href={`/pacientes/${item.paciente_id}`}
                className="text-[12px] text-tinta3 hover:text-vaga"
              >
                ver cadastro
              </Link>
            </div>
          </form>

          <form action={sair} className="mt-3 border-t border-linha pt-3">
            <input type="hidden" name="id" value={item.id} />
            <Salvar rotulo="tirar da fila" tom="leve" />
          </form>
        </div>
      )}
    </li>
  );
}

export function EditorFila({
  fila,
  candidatos,
}: {
  fila: NaFila[];
  candidatos: { id: string; nome: string }[];
}) {
  const [abrindo, setAbrindo] = useState(false);
  const [estado, entrar] = useActionState(entrarNaFila, INICIAL);
  const erros = estado.estado === "erro" ? estado.erros : [];

  return (
    <section>
      <div className="flex flex-wrap items-baseline justify-between gap-3">
        <h2 className="rotulo">Quem está na fila</h2>
        <button
          type="button"
          onClick={() => setAbrindo((v) => !v)}
          disabled={candidatos.length === 0}
          className="text-[13px] font-medium text-vaga hover:underline disabled:opacity-40"
        >
          {abrindo ? "fechar" : "colocar alguém na fila →"}
        </button>
      </div>

      <p className="mt-2 max-w-[74ch] text-[12.5px] leading-relaxed text-tinta2">
        Quem está aqui recebe a oferta quando um horário vagar — um por vez, na
        ordem da sua regra, e só se a hora couber na janela que a pessoa aceitou.
        {candidatos.length === 0 && fila.length === 0 && (
          <>
            {" "}
            <Link href="/pacientes/novo" className="font-medium text-vaga hover:underline">
              Cadastre um paciente primeiro.
            </Link>
          </>
        )}
      </p>

      {abrindo && (
        <form action={entrar} className="mt-4 rounded-cartao border border-linha bg-folha p-5">
          <Campo rotulo="Quem">
            <select name="paciente_id" className={ENTRADA} defaultValue={candidatos[0]?.id}>
              {candidatos.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.nome}
                </option>
              ))}
            </select>
          </Campo>

          <CamposJanela />
          <Erros erros={erros} />

          <div className="mt-5">
            <Salvar rotulo="Colocar na fila" />
          </div>
        </form>
      )}

      {fila.length > 0 ? (
        <ul className="mt-4 overflow-hidden rounded-cartao border border-linha bg-folha">
          {fila.map((f) => (
            <Linha key={f.id} item={f} />
          ))}
        </ul>
      ) : (
        <p className="mt-4 rounded-cartao border border-dashed border-linha2 bg-folha px-5 py-8 text-center text-[13.5px] text-tinta2">
          A fila está vazia. Sem ela, um cancelamento vira só um buraco.
        </p>
      )}
    </section>
  );
}
