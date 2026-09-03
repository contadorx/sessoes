"use client";

import { useActionState, useState } from "react";
import {
  anotarObjetivo,
  concluirObjetivo,
  remarcarRevisao,
  type Resultado,
} from "@/app/(app)/pacientes/acoes";
import {
  estadoDoObjetivo,
  fraseDoObjetivo,
  fraseDoPlano,
  separar,
  type Objetivo,
} from "@/lib/objetivo";
import { useFormStatus } from "react-dom";

const INICIAL: Resultado = { estado: "inicial" };

const CAMPO =
  "w-full rounded-cartao border border-linha2 bg-folha px-3 py-2 text-[13px] leading-relaxed text-tinta placeholder:text-tinta3 focus:border-tinta3 focus:outline-none";

/** O mesmo botão do resto do prontuário, com o alvo de 44 px da B48. */
function Botao({ rotulo, destaque }: { rotulo: string; destaque?: boolean }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className={
        destaque
          ? "min-h-11 rounded-full bg-cheia px-4 py-2 text-[12.5px] font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-45"
          : "min-h-11 rounded-full border border-linha2 px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2 disabled:opacity-45"
      }
    >
      {pending ? "…" : rotulo}
    </button>
  );
}

/**
 * O plano terapêutico leve (PR9) — objetivos com data de revisão.
 *
 * **Leve significa leve.** O campo `objetivos` do bloco 2 continua onde está,
 * em texto livre, para o que se escreve uma vez. Isto aqui é o objetivo que tem
 * prazo para ser revisto, e que some de vista sem ele.
 *
 * Três coisas que este componente deliberadamente **não** faz:
 *
 * **1. Não sugere data.** Nem "revisar em 3 meses", nem intervalo recomendado.
 * Sugerir prazo de revisão é opinar sobre condução clínica pela porta dos
 * fundos — a fronteira 3, a mesma que matou o alerta de sumiço.
 *
 * **2. Não alerta.** A data alcançada aparece em texto, na mesma cor do resto.
 * Sem contagem regressiva, sem selo vermelho, sem número numa faixa no alto da
 * agenda. "Você marcou para revisar em 12/03" é uma frase sobre um combinado
 * dela consigo mesma; qualquer coisa mais forte vira uma frase sobre a
 * paciente, e o produto não tem o que dizer sobre isso.
 *
 * **3. Não deixa editar o texto.** Objetivo que mudou é objetivo novo, e o
 * antigo fica no registro contando o que aconteceu — a mesma decisão de
 * `evolucao_nao_se_reescreve`. Por isso concluir também não apaga.
 */
export function Objetivos({
  pacienteId,
  objetivos,
  hoje,
}: {
  pacienteId: string;
  objetivos: Objetivo[];
  /** Do servidor, em São Paulo — nunca do relógio do navegador (lei 3). */
  hoje: string;
}) {
  const [rAnotar, anotar] = useActionState(anotarObjetivo, INICIAL);
  const [abrindo, setAbrindo] = useState(false);
  const [verConcluidos, setVerConcluidos] = useState(false);

  const { abertos, concluidos } = separar(objetivos);
  const resumo = fraseDoPlano(objetivos, hoje);

  return (
    <div className="mt-6 border-t border-linha pt-5">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <p className="rotulo">Objetivos, e quando revisar</p>
        {resumo && <span className="text-[11.5px] text-tinta3">{resumo}</span>}
      </div>

      {abertos.length === 0 && (
        <p className="mt-2 text-[12.5px] leading-relaxed text-tinta3">
          Nenhum objetivo escrito aqui. É opcional — o bloco 2 acima já guarda os
          objetivos em texto livre; isto é para o que você quer revisar numa data.
        </p>
      )}

      {abertos.length > 0 && (
        <ul className="mt-2 space-y-2">
          {abertos.map((o) => (
            <Item key={o.id} o={o} pacienteId={pacienteId} hoje={hoje} />
          ))}
        </ul>
      )}

      {/* ------------------------------------------------------- anotar */}
      {abrindo ? (
        <form action={anotar} className="mt-3 rounded-cartao border border-linha2 px-4 py-3">
          <input type="hidden" name="paciente_id" value={pacienteId} />
          <textarea
            name="texto"
            rows={2}
            required
            minLength={3}
            maxLength={500}
            placeholder="O que vocês combinaram de trabalhar."
            className={CAMPO}
          />
          <div className="mt-2 flex flex-wrap items-end gap-3">
            <label className="text-[11.5px] text-tinta3">
              <span className="block">revisar em (opcional)</span>
              <input
                type="date"
                name="revisar_em"
                min={hoje}
                className="mt-0.5 rounded-[5px] border border-linha2 bg-folha px-2 py-1 text-[12.5px] text-tinta"
              />
            </label>
            <Botao rotulo="Anotar" destaque />
            <button
              type="button"
              onClick={() => setAbrindo(false)}
              className="min-h-11 rounded-full border border-linha2 px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2"
            >
              deixa
            </button>
          </div>
          {rAnotar.estado === "erro" && (
            <p role="alert" className="mt-2 text-[12px] font-medium text-vaga">
              {rAnotar.erros.join(" ")}
            </p>
          )}
        </form>
      ) : (
        <button
          type="button"
          onClick={() => setAbrindo(true)}
          className="mt-3 text-[12.5px] font-medium text-vaga hover:underline"
        >
          Anotar um objetivo →
        </button>
      )}

      {/* --------------------------------------------------- os concluídos */}
      {concluidos.length > 0 && (
        <div className="mt-4 border-t border-linha pt-3">
          <button
            type="button"
            onClick={() => setVerConcluidos((v) => !v)}
            className="text-[11.5px] text-tinta3 hover:text-tinta2"
          >
            {verConcluidos ? "esconder" : `ver os ${concluidos.length} concluídos`}
          </button>
          {verConcluidos && (
            <ul className="mt-2 space-y-1.5">
              {concluidos.map((o) => (
                <li key={o.id} className="text-[12.5px] leading-relaxed text-tinta3">
                  {o.texto} — {fraseDoObjetivo(o, hoje)}
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}

function Item({
  o,
  pacienteId,
  hoje,
}: {
  o: Objetivo;
  pacienteId: string;
  hoje: string;
}) {
  const [rConcluir, concluir] = useActionState(concluirObjetivo, INICIAL);
  const [rRemarcar, remarcar] = useActionState(remarcarRevisao, INICIAL);
  const [remarcando, setRemarcando] = useState(false);

  const estado = estadoDoObjetivo(o, hoje);
  const erro =
    rConcluir.estado === "erro"
      ? rConcluir.erros.join(" ")
      : rRemarcar.estado === "erro"
        ? rRemarcar.erros.join(" ")
        : null;

  return (
    <li className="rounded-cartao border border-linha2 px-4 py-3">
      <p className="text-[13px] leading-relaxed text-tinta">{o.texto}</p>

      {/*
        A frase da data, na mesma cor do resto — inclusive quando a data já
        passou. É a decisão da build: vencido é fato, não alerta.
      */}
      <p className="mt-1 text-[11.5px] text-tinta3">{fraseDoObjetivo(o, hoje)}</p>

      <div className="mt-2 flex flex-wrap items-center gap-2">
        <form action={concluir}>
          <input type="hidden" name="objetivo" value={o.id} />
          <input type="hidden" name="paciente_id" value={pacienteId} />
          <Botao rotulo="Concluir" />
        </form>

        {remarcando ? (
          <form action={remarcar} className="flex flex-wrap items-center gap-2">
            <input type="hidden" name="objetivo" value={o.id} />
            <input type="hidden" name="paciente_id" value={pacienteId} />
            <input
              type="date"
              name="revisar_em"
              min={hoje}
              defaultValue={o.revisar_em ?? ""}
              className="rounded-[5px] border border-linha2 bg-folha px-2 py-1 text-[12.5px] text-tinta"
            />
            <Botao rotulo="Remarcar" />
            <button
              type="button"
              onClick={() => setRemarcando(false)}
              className="text-[12px] text-tinta3 hover:text-tinta2"
            >
              deixa
            </button>
          </form>
        ) : (
          <button
            type="button"
            onClick={() => setRemarcando(true)}
            className="text-[12px] text-tinta3 hover:text-tinta2"
          >
            {estado === "sem_data" ? "marcar uma revisão" : "remarcar"}
          </button>
        )}
      </div>

      {erro && (
        <p role="alert" className="mt-2 text-[12px] font-medium text-vaga">
          {erro}
        </p>
      )}
    </li>
  );
}
