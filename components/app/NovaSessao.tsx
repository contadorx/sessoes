"use client";

import { useActionState, useEffect, useRef, useState } from "react";
import { useFormStatus } from "react-dom";
import { criarSessao, type Resultado } from "@/app/(app)/agenda/acoes";
import { Campo, Erros, ENTRADA } from "./campos";

const INICIAL: Resultado = { estado: "inicial" };

type Paciente = { id: string; nome: string; valor: string; duracao_min: number };

const DIA_CURTO = new Intl.DateTimeFormat("pt-BR", {
  timeZone: "UTC",
  weekday: "short",
  day: "numeric",
  month: "numeric",
});

function Botao() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="rounded-full bg-vaga px-5 py-2.5 text-[13px] font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-45"
    >
      {pending ? "Marcando…" : "Marcar sessão"}
    </button>
  );
}

/**
 * Marcar uma sessão fora da recorrência.
 *
 * DUAS COISAS MUDARAM DE NOME AQUI, E AS DUAS ERAM PRECISÃO
 *
 * A seção se chamava **Encaixe**, e encaixe neste produto é uma coisa
 * específica: a hora que a fila preencheu depois de alguém desmarcar. Isto
 * aqui é qualquer sessão que não vem do combinado — e chamar as duas pelo
 * mesmo nome era o que fazia a origem errada parecer certa. Ver o comentário
 * de `criarSessao`.
 *
 * E ela passou a abrir por endereço. `/agenda?novo=sessao` é para onde o menu
 * Novo → Sessão manda desde que o menu existe, e até aqui a página abria
 * idêntica: nenhuma criação, nenhum campo, nada. O parâmetro abre esta
 * composição — paciente, dia, hora, duração — e **rola até ela**, porque em
 * 375 px um formulário que abre abaixo de sete dias de agenda é um formulário
 * que ela não vê. O combinado continua sendo a fonte das recorrências; isto é
 * a sessão que não é recorrente.
 */
export function MarcarSessao({
  pacientes,
  dias,
  abrirDeInicio = false,
}: {
  pacientes: Paciente[];
  dias: string[];
  /** Chegou por `/agenda?novo=sessao`: abre já composta e traz a seção ao campo de visão. */
  abrirDeInicio?: boolean;
}) {
  const [aberto, setAberto] = useState(abrirDeInicio && pacientes.length > 0);
  const secao = useRef<HTMLElement>(null);

  // O mesmo motivo do painel da `Semana`: abrir algo fora do campo de visão é
  // indistinguível de não ter aberto nada.
  useEffect(() => {
    if (!abrirDeInicio) return;
    secao.current?.scrollIntoView({ behavior: "smooth", block: "start" });
  }, [abrirDeInicio]);
  const [escolhido, setEscolhido] = useState<Paciente | undefined>(pacientes[0]);
  const [estado, despachar] = useActionState(criarSessao, INICIAL);
  const erros = estado.estado === "erro" ? estado.erros : [];

  return (
    <section ref={secao} id="marcar-sessao" className="border-t border-linha pt-6">
      <div className="flex flex-wrap items-baseline justify-between gap-3">
        <h2 className="rotulo">Marcar sessão</h2>
        <button
          type="button"
          onClick={() => setAberto((v) => !v)}
          className="text-[13px] font-medium text-vaga hover:underline"
          disabled={pacientes.length === 0}
        >
          {aberto ? "fechar" : "marcar uma sessão →"}
        </button>
      </div>

      <p className="mt-2 max-w-[70ch] text-[12.5px] leading-relaxed text-tinta2">
        Marcar uma sessão fora da recorrência. Horário já ocupado é recusado pelo
        banco, então não há como marcar duas pessoas na mesma hora.{" "}
        {pacientes.length === 0 && (
          <b className="font-semibold text-tinta">Cadastre um paciente primeiro.</b>
        )}
      </p>

      {aberto && (
        <form action={despachar} className="mt-4 rounded-cartao border border-linha bg-folha p-5">
          <div className="grid gap-3 sm:grid-cols-5">
            <div className="sm:col-span-2">
              <Campo rotulo="Quem">
                <select
                  name="paciente_id"
                  className={ENTRADA}
                  value={escolhido?.id ?? ""}
                  onChange={(e) =>
                    setEscolhido(pacientes.find((p) => p.id === e.target.value))
                  }
                >
                  {pacientes.map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.nome}
                    </option>
                  ))}
                </select>
              </Campo>
            </div>

            <Campo rotulo="Dia">
              <select name="dia" defaultValue={dias[0]} className={ENTRADA}>
                {dias.map((d) => (
                  <option key={d} value={d}>
                    {DIA_CURTO.format(new Date(`${d}T12:00:00Z`)).replace(".", "")}
                  </option>
                ))}
              </select>
            </Campo>

            <Campo rotulo="Hora">
              <input type="time" step={900} name="hora" required className={ENTRADA} />
            </Campo>

            <Campo rotulo="Duração">
              <input
                type="number"
                onWheel={(e) => e.currentTarget.blur()}
                name="duracao_min"
                min={15}
                max={240}
                step={5}
                key={escolhido?.id}
                defaultValue={escolhido?.duracao_min ?? 50}
                className={ENTRADA}
              />
            </Campo>
          </div>

          <div className="mt-3 max-w-[12rem]">
            <Campo rotulo="Valor (R$)" dica="Vem do combinado; dá para mudar.">
              <input
                name="valor"
                inputMode="decimal"
                key={`v-${escolhido?.id}`}
                defaultValue={escolhido?.valor ?? ""}
                className={ENTRADA}
              />
            </Campo>
          </div>

          <Erros erros={erros} />
          {estado.estado === "ok" && (
            <p className="mt-3 text-[12.5px] font-medium text-cheia">{estado.mensagem}</p>
          )}

          <div className="mt-5">
            <Botao />
          </div>
        </form>
      )}
    </section>
  );
}
