"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import { salvarRegras, type Resultado } from "@/app/(app)/encaixes/acoes";
import type { Regras } from "@/app/(app)/encaixes/dados";
import { REGRAS, ROTULO_REGRA, EXPLICACAO_REGRA } from "@/lib/regra";
import { Campo, Erros, ENTRADA } from "./campos";

const INICIAL: Resultado = { estado: "inicial" };

function Salvar() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="rounded-full bg-vaga px-5 py-2.5 text-[13px] font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-45"
    >
      {pending ? "Salvando…" : "Salvar regra"}
    </button>
  );
}

export function RegrasDaFila({ regras }: { regras: Regras }) {
  const [escolhida, setEscolhida] = useState(regras.regra_prioridade);
  const [estado, salvar] = useActionState(salvarRegras, INICIAL);
  const erros = estado.estado === "erro" ? estado.erros : [];

  return (
    <section id="regras" className="scroll-mt-20 border-t border-linha pt-6">
      <h2 className="rotulo">A regra é sua</h2>
      <p className="mt-2 max-w-[74ch] text-[12.5px] leading-relaxed text-tinta2">
        Quem vem primeiro na cascata é decisão clínica, não comercial. Nenhuma
        das opções ordena por dinheiro, e não existe forma de comprar posição.
      </p>

      <form action={salvar} className="mt-4 rounded-cartao border border-linha bg-folha p-5">
        <div className="flex flex-col gap-2">
          {REGRAS.map((r) => (
            <label
              key={r}
              className={`cursor-pointer rounded-cartao border px-4 py-3 transition-colors ${
                escolhida === r ? "border-vaga-linha bg-vaga-bg" : "border-linha hover:bg-folha2"
              }`}
            >
              <span className="flex items-baseline gap-2">
                <input
                  type="radio"
                  name="regra_prioridade"
                  value={r}
                  checked={escolhida === r}
                  onChange={() => setEscolhida(r)}
                  className="accent-vaga"
                />
                <span className="text-[13.5px] font-medium text-tinta">{ROTULO_REGRA[r]}</span>
              </span>
              <span className="mt-1 block pl-6 text-[12px] leading-relaxed text-tinta3">
                {EXPLICACAO_REGRA[r]}
              </span>
            </label>
          ))}
        </div>

        <div className="mt-5 grid gap-3 sm:grid-cols-3">
          <Campo rotulo="Prazo da oferta (min)" dica="Depois disso, a fila anda.">
            <input
              type="number"
              name="oferta_timeout_min"
              min={5}
              max={720}
              defaultValue={regras.oferta_timeout_min}
              className={ENTRADA}
            />
          </Campo>
          <Campo rotulo="Não incomodar a partir de">
            <input
              type="time"
              name="silencio_inicio"
              defaultValue={regras.silencio_inicio?.slice(0, 5)}
              className={ENTRADA}
            />
          </Campo>
          <Campo rotulo="Voltar a avisar às">
            <input
              type="time"
              name="silencio_fim"
              defaultValue={regras.silencio_fim?.slice(0, 5)}
              className={ENTRADA}
            />
          </Campo>
        </div>

        <p className="mt-2 text-[11.5px] leading-relaxed text-tinta3">
          Ninguém recebe proposta de terapia de madrugada. A oferta feita dentro
          do silêncio fica guardada e sai no horário de voltar.
        </p>

        <Erros erros={erros} />
        {estado.estado === "ok" && (
          <p className="mt-3 text-[12.5px] font-medium text-cheia">{estado.mensagem}</p>
        )}

        <div className="mt-5">
          <Salvar />
        </div>
      </form>
    </section>
  );
}
