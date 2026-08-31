"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import {
  abrirRemarcacao,
  remarcarAgora,
  type ResultadoRemarcar,
} from "@/app/(app)/agenda/remarcar";
import { porqueDaOpcao, ganhoDaOpcao, quando, convite, custoEmCentavos } from "@/lib/remarcacao";
import { formatar } from "@/lib/dinheiro";

const INICIAL: ResultadoRemarcar = { estado: "inicial" };

function Botao({ rotulo }: { rotulo: string }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="rounded-full border border-linha2 px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2 disabled:opacity-45"
    >
      {pending ? "…" : rotulo}
    </button>
  );
}

/**
 * A remarcação guiada, na sessão (D11).
 *
 * A tela existe para responder três coisas antes de qualquer link sair:
 * **quais horas o sistema quer preencher**, **por que cada uma está na lista**,
 * e **quanto esta troca custa** pelo combinado desta pessoa.
 *
 * O "por quê" de cada opção só aparece aqui. Do outro lado a pessoa vê dois ou
 * três horários e mais nada — "esta hora vagou porque alguém desmarcou" é
 * informação sobre um terceiro.
 */
export function Remarcar({
  sessaoId,
  pacienteNome,
  telefone,
}: {
  sessaoId: string;
  pacienteNome: string;
  telefone: string | null;
}) {
  const [r, abrir] = useActionState(abrirRemarcacao, INICIAL);
  const [t, trocar] = useActionState(remarcarAgora, INICIAL);
  const [copiado, setCopiado] = useState(false);

  const link =
    r.estado === "aberta" && typeof window !== "undefined"
      ? `${window.location.origin}/p/remarcar/${r.token}`
      : "";

  const texto = convite(pacienteNome, link);
  const zap = telefone
    ? `https://wa.me/${telefone.replace(/\D/g, "")}?text=${encodeURIComponent(texto)}`
    : null;

  if (t.estado === "trocada") {
    return <p className="mt-3 text-[12.5px] leading-relaxed text-cheia">{t.mensagem}</p>;
  }

  if (r.estado !== "aberta") {
    return (
      <>
        <form action={abrir}>
          <input type="hidden" name="sessao" value={sessaoId} />
          <Botao rotulo="Remarcar" />
        </form>
        {r.estado === "erro" && (
          <ul className="mt-2 space-y-1">
            {r.erros.map((e, i) => (
              <li key={i} className="text-[12.5px] leading-relaxed text-vaga">
                {e}
              </li>
            ))}
          </ul>
        )}
      </>
    );
  }

  const centavos = custoEmCentavos(r.custo);

  return (
    <div className="mt-3 rounded-cartao border border-linha bg-folha2 px-4 py-3">
      {/* ------------------------------------------------------ o custo */}
      {r.custo && (
        <p
          className={`text-[12.5px] leading-relaxed ${
            r.custo.tardia ? "text-aviso" : "text-tinta2"
          }`}
        >
          {r.custo.texto}
          {centavos > 0 && (
            <>
              {" "}
              <b className="font-semibold">{formatar(centavos)}</b>.
            </>
          )}
        </p>
      )}

      {/* ----------------------------------------------------- as opções */}
      <ul className="mt-3 space-y-2">
        {r.opcoes.map((o) => (
          <li
            key={o.inicio}
            className={`rounded-cartao border px-3 py-2 ${
              ganhoDaOpcao(o.motivo) === "tapa"
                ? "border-cheia-linha bg-cheia-bg"
                : "border-linha bg-folha"
            }`}
          >
            <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
              <span className="text-[13px] text-tinta">{quando(o.inicio)}</span>
              <span className="text-[11.5px] text-tinta3">{porqueDaOpcao(o.motivo)}</span>
              <form action={trocar} className="ml-auto">
                <input type="hidden" name="sessao" value={sessaoId} />
                <input type="hidden" name="inicio" value={o.inicio} />
                <button
                  type="submit"
                  className="text-[12px] font-medium text-vaga hover:underline"
                >
                  marcar esta
                </button>
              </form>
            </div>
          </li>
        ))}
      </ul>

      {/* ------------------------------------------------------- o envio */}
      <div className="mt-3 flex flex-wrap items-center gap-2">
        {zap && (
          <a
            href={zap}
            target="_blank"
            rel="noreferrer"
            className="rounded-full bg-tinta px-4 py-1.5 text-[12.5px] font-medium text-papel transition-opacity hover:opacity-90"
          >
            Abrir no WhatsApp
          </a>
        )}
        <button
          type="button"
          onClick={async () => {
            try {
              await navigator.clipboard.writeText(link);
              setCopiado(true);
              setTimeout(() => setCopiado(false), 2500);
            } catch {
              setCopiado(false);
            }
          }}
          className="rounded-full border border-linha2 px-4 py-1.5 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2"
        >
          {copiado ? "copiado" : "Copiar o link"}
        </button>
      </div>

      <p className="mt-2 text-[11.5px] leading-relaxed text-tinta3">
        O link vale 48 horas e a mensagem sai de você, do seu número, com um texto
        que não nomeia nada. <b>Nenhuma dessas horas fica reservada</b>: se a fila
        preencher uma antes, a pessoa vê só as que sobraram — e a hora que você
        libera aqui vai para a fila no mesmo instante.
      </p>

      {t.estado === "erro" && (
        <ul className="mt-2 space-y-1">
          {t.erros.map((e, i) => (
            <li key={i} className="text-[12.5px] leading-relaxed text-vaga">
              {e}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
