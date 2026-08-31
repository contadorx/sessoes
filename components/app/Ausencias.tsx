"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import { criarAusencia, removerAusencia, type Resultado } from "@/app/(app)/agenda/acoes";
import type { Ausencia } from "@/app/(app)/agenda/dados";
import { Campo, Erros, ENTRADA } from "./campos";

const INICIAL: Resultado = { estado: "inicial" };

const ROTULO: Record<Ausencia["tipo"], string> = {
  ferias: "férias",
  feriado: "feriado",
  bloqueio: "bloqueio",
};

const dm = (iso: string) => iso.split("-").reverse().slice(0, 2).join("/");

function Botao({ rotulo }: { rotulo: string }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="rounded-full bg-vaga px-5 py-2.5 text-[13px] font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-45"
    >
      {pending ? "Salvando…" : rotulo}
    </button>
  );
}

/** Precisa ser um componente próprio: `useFormStatus` só enxerga o form acima dele. */
function BotaoRemover() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="text-[12px] text-tinta3 transition-colors hover:text-vaga disabled:opacity-50"
    >
      {pending ? "removendo…" : "remover"}
    </button>
  );
}

function Remover({ id }: { id: string }) {
  const [, despachar] = useActionState(removerAusencia, INICIAL);

  return (
    <form action={despachar}>
      <input type="hidden" name="id" value={id} />
      <BotaoRemover />
    </form>
  );
}

export function Ausencias({
  ausencias,
  hoje,
  horizonte,
}: {
  ausencias: Ausencia[];
  hoje: string;
  horizonte: string | null;
}) {
  const [aberto, setAberto] = useState(false);
  const [estado, despachar] = useActionState(criarAusencia, INICIAL);
  const erros = estado.estado === "erro" ? estado.erros : [];

  return (
    <section className="border-t border-linha pt-6">
      <div className="flex flex-wrap items-baseline justify-between gap-3">
        <h2 className="rotulo">Férias, feriados e bloqueios</h2>
        <button
          type="button"
          onClick={() => setAberto((v) => !v)}
          className="text-[13px] font-medium text-vaga hover:underline"
        >
          {aberto ? "fechar" : "marcar ausência →"}
        </button>
      </div>

      <p className="mt-2 max-w-[70ch] text-[12.5px] leading-relaxed text-tinta2">
        Marcar ausência <b className="font-semibold text-tinta">não mexe no combinado</b> de
        ninguém: só tira as sessões daquele período da agenda. Remover devolve a
        recorrência sozinha.
      </p>

      {aberto && (
        <form action={despachar} className="mt-4 rounded-cartao border border-linha bg-folha p-5">
          <div className="grid gap-3 sm:grid-cols-4">
            <Campo rotulo="Tipo">
              <select name="tipo" defaultValue="ferias" className={ENTRADA}>
                <option value="ferias">férias</option>
                <option value="feriado">feriado</option>
                <option value="bloqueio">bloqueio</option>
              </select>
            </Campo>
            <Campo rotulo="De">
              <input type="date" name="inicio" required min={hoje} className={ENTRADA} />
            </Campo>
            <Campo rotulo="Até" dica="Em branco = um dia só.">
              <input type="date" name="fim" min={hoje} className={ENTRADA} />
            </Campo>
            <Campo rotulo="Motivo">
              <input name="motivo" maxLength={200} className={ENTRADA} />
            </Campo>
          </div>

          <Erros erros={erros} />
          {estado.estado === "ok" && (
            <p className="mt-3 text-[12.5px] font-medium text-cheia">{estado.mensagem}</p>
          )}

          <div className="mt-5">
            <Botao rotulo="Marcar" />
          </div>
        </form>
      )}

      {ausencias.length > 0 && (
        <ul className="mt-4 overflow-hidden rounded-cartao border border-linha bg-folha">
          {ausencias.map((a) => (
            <li
              key={a.id}
              className="flex flex-wrap items-baseline gap-x-4 gap-y-1 border-t border-linha px-5 py-3 first:border-t-0"
            >
              <span className="text-[13.5px] font-medium text-tinta">{ROTULO[a.tipo]}</span>
              <span className="font-mono text-[12.5px] tabular text-tinta2">
                {dm(a.inicio)}
                {a.fim !== a.inicio && ` → ${dm(a.fim)}`}
              </span>
              {a.motivo && <span className="text-[12.5px] text-tinta3">{a.motivo}</span>}
              <span className="ml-auto">
                <Remover id={a.id} />
              </span>
            </li>
          ))}
        </ul>
      )}

      {horizonte && (
        <p className="mt-4 text-[11.5px] text-tinta3">
          A agenda se monta oito semanas à frente e caminha sozinha —
          materializada até {dm(horizonte)}.
        </p>
      )}
    </section>
  );
}
