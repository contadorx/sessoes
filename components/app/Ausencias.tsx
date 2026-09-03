"use client";

import { Recado } from "@/components/app/campos";
import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import {
  criarAusencia,
  removerAusencia,
  reverMensalidade,
  type Resultado,
} from "@/app/(app)/agenda/acoes";
import type { Ausencia, MensalidadeARever } from "@/app/(app)/agenda/dados";
import { Campo, Erros, ENTRADA } from "./campos";
import { formatar, paraCentavos } from "@/lib/dinheiro";

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
  const [r, despachar] = useActionState(removerAusencia, INICIAL);

  return (
    <form action={despachar} className="flex flex-col items-end gap-1">
      <input type="hidden" name="id" value={id} />
      <BotaoRemover />
      <Recado r={r} />
    </form>
  );
}

/**
 * A conta do mês que ficou para trás.
 *
 * A mensalidade é gerada no dia do mês e o valor **congela** na cobrança. Uma
 * pausa marcada depois disso não volta atrás sozinha, e é decisão: reescrever
 * cobrança sem ela saber seria descobrir a mudança pelo extrato.
 *
 * Então a diferença aparece aqui, com os dois números lado a lado e um botão
 * por linha. Ela aplica o que quiser aplicar.
 */
function ARever({ itens }: { itens: MensalidadeARever[] }) {
  const [estado, despachar] = useActionState(reverMensalidade, INICIAL);
  if (itens.length === 0) return null;

  return (
    <div className="mt-4 rounded-cartao border border-aviso-linha bg-aviso-bg px-5 py-4">
      <p className="text-[13px] leading-relaxed text-tinta2">
        {itens.length === 1
          ? "Uma mensalidade em aberto deixou de bater com a conta do mês"
          : `${itens.length} mensalidades em aberto deixaram de bater com a conta do mês`}{" "}
        — a cobrança foi gerada antes da pausa. Nada foi mudado: quem decide é
        você.
      </p>

      <ul className="mt-3 flex flex-col gap-2">
        {itens.map((m) => {
          const antes = paraCentavos(m.valor_cobrado);
          const agora = paraCentavos(m.valor_agora);
          return (
            <li key={m.cobranca} className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
              <span className="text-[13px] text-tinta">{m.paciente}</span>
              <span className="font-mono text-[12.5px] tabular text-tinta3">
                {m.competencia.slice(5, 7)}/{m.competencia.slice(0, 4)}
              </span>
              <span className="font-mono text-[12.5px] tabular text-tinta2">
                {formatar(antes)} → <b className="font-semibold text-tinta">{formatar(agora)}</b>
              </span>
              <form action={despachar} className="ml-auto">
                <input type="hidden" name="cobranca" value={m.cobranca} />
                <button
                  type="submit"
                  className="min-h-11 rounded-full border border-linha2 bg-folha px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2"
                >
                  Passar para {formatar(agora)}
                </button>
              </form>
            </li>
          );
        })}
      </ul>

      {estado.estado === "erro" && (
        <p className="mt-2 text-[12.5px] text-vaga">{estado.erros[0]}</p>
      )}
    </div>
  );
}

export function Ausencias({
  ausencias,
  hoje,
  horizonte,
  aRever,
}: {
  ausencias: Ausencia[];
  hoje: string;
  horizonte: string | null;
  aRever: MensalidadeARever[];
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
        ninguém: só tira as sessões daquele período da agenda, e elas saem junto
        da conta do mês de quem paga mensalidade. Remover devolve a recorrência
        sozinha.
      </p>

      <ARever itens={aRever} />

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
          A agenda se monta oito semanas à frente e caminha sozinha — montada
          até {dm(horizonte)}.
        </p>
      )}
    </section>
  );
}
