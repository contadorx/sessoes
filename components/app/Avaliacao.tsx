"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import { registrarAvaliacao, type Resultado } from "@/app/(app)/perfil/acoes";
import {
  PERGUNTA,
  PERGUNTA_ABERTA,
  ANCORA_BAIXA,
  ANCORA_ALTA,
  type Pendencia,
} from "@/lib/avaliacao";

const INICIAL: Resultado = { estado: "inicial" };

/**
 * A pergunta.
 *
 * Cinco decisões de interface, e nenhuma é sobre a nota:
 *
 * 1. **Ela se recusa.** O "agora não" fecha a caixa e não pergunta por quê. Um
 *    convite que não pode ser dispensado não é convite — e a recusa não vira
 *    dado: nada é gravado, e a pergunta volta no ciclo seguinte como voltaria
 *    de qualquer jeito.
 *
 * 2. **Não trava tela nenhuma.** É um bloco no fim do Perfil, sem modal, sem
 *    sobreposição, sem foco roubado. A pergunta é o item menos importante de
 *    qualquer tela em que ela apareça.
 *
 * 3. **As âncoras descrevem o fato**, não julgam: "não mudou nada" e "mudou
 *    muito". Rotular a ponta baixa de "ruim" convida a pessoa a ser gentil — e
 *    a partir daí o instrumento mede a vontade de agradar.
 *
 * 4. **O texto é opcional, e a caixa só aparece depois da nota.** Pedir
 *    justificativa antes do número é o jeito mais rápido de não receber número
 *    nenhum.
 *
 * 5. **A resposta é a mesma para 0 e para 10.** Agradecer mais quem deu nota
 *    alta ensina qual nota agrada.
 */
export function Avaliacao({ pendencia }: { pendencia: Pendencia }) {
  const [estado, acao] = useActionState(registrarAvaliacao, INICIAL);
  const [nota, setNota] = useState<number | null>(null);
  const [dispensada, setDispensada] = useState(false);

  if (!pendencia.pedir || dispensada) return null;

  if (estado.estado === "ok") {
    return (
      <div className="mt-3 rounded-cartao border border-linha bg-folha px-5 py-4">
        <p className="text-[13px] text-cheia">{estado.mensagem}</p>
      </div>
    );
  }

  return (
    <div className="mt-3 rounded-cartao border border-linha bg-folha px-5 py-4">
      <form action={acao}>
        <input type="hidden" name="momento" value="perfil" />
        <input type="hidden" name="nota" value={nota ?? ""} />

        <p className="max-w-2xl text-[13px] leading-relaxed text-tinta">{PERGUNTA}</p>

        <div className="mt-3 flex flex-wrap gap-1.5">
          {Array.from({ length: 11 }, (_, i) => i).map((n) => (
            <button
              key={n}
              type="button"
              onClick={() => setNota(n)}
              aria-pressed={nota === n}
              className={
                nota === n
                  ? "h-9 w-9 rounded-full border border-tinta bg-tinta font-mono text-[12.5px] tabular-nums text-folha"
                  : "h-9 w-9 rounded-full border border-linha2 font-mono text-[12.5px] tabular-nums text-tinta2 transition-colors hover:bg-folha2"
              }
            >
              {n}
            </button>
          ))}
        </div>

        <div className="mt-1.5 flex justify-between text-[11.5px] text-tinta3">
          <span>{ANCORA_BAIXA}</span>
          <span>{ANCORA_ALTA}</span>
        </div>

        {nota !== null && (
          <div className="mt-4">
            <label
              htmlFor="avaliacao-texto"
              className="block text-[12.5px] leading-relaxed text-tinta2"
            >
              {PERGUNTA_ABERTA}{" "}
              <span className="text-tinta3">(opcional)</span>
            </label>
            <textarea
              id="avaliacao-texto"
              name="texto"
              rows={3}
              maxLength={2000}
              className="mt-1.5 w-full rounded-cartao border border-linha2 bg-folha px-3 py-2 text-[13px] text-tinta placeholder:text-tinta3 focus:border-tinta3 focus:outline-none"
            />
          </div>
        )}

        <div className="mt-3 flex items-center gap-3">
          <Enviar podeEnviar={nota !== null} />
          <button
            type="button"
            onClick={() => setDispensada(true)}
            className="text-[12.5px] text-tinta3 underline underline-offset-2 transition-colors hover:text-tinta2"
          >
            agora não
          </button>
        </div>

        {estado.estado === "erro" && (
          <ul className="mt-2 space-y-1">
            {estado.erros.map((e, i) => (
              <li key={i} className="text-[12.5px] leading-relaxed text-vaga">
                {e}
              </li>
            ))}
          </ul>
        )}
      </form>

      {/* O que acontece com a resposta, dito antes de ela responder. Uma
          pergunta cujo destino não se sabe é uma pergunta que se responde por
          educação — e é assim que se coleta elogio em vez de informação. */}
      <p className="mt-3 max-w-2xl text-[11.5px] leading-relaxed text-tinta3">
        A resposta vai para mim, não para uma tela de ninguém. Ela não muda o seu
        plano, o seu preço nem o que o sistema faz por você — e sai junto quando
        você exporta a conta.
      </p>
    </div>
  );
}

function Enviar({ podeEnviar }: { podeEnviar: boolean }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending || !podeEnviar}
      className="rounded-full border border-linha2 px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2 disabled:opacity-45"
    >
      {pending ? "…" : "Enviar"}
    </button>
  );
}
