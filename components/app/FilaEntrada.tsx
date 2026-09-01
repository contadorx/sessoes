"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import { mudarFilaDeEntrada, type Resultado } from "@/app/(app)/encaixes/fixos/acoes";

const INICIAL: Resultado = { estado: "inicial" };

function Botao({ rotulo }: { rotulo: string }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="rounded-full border border-linha2 px-4 py-1.5 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2 disabled:opacity-45"
    >
      {pending ? "…" : rotulo}
    </button>
  );
}

/**
 * A fila de entrada, na ficha.
 *
 * Aparece só para quem **não** tem combinado aberto, e é essa condição que
 * separa as duas filas na cabeça de quem usa: a de encaixe é de quem já é
 * paciente e topa uma hora extra; esta é de quem ainda não tem horário nenhum e
 * está esperando um vagar.
 */
export function FilaEntrada({
  pacienteId,
  naFila,
  desde,
}: {
  pacienteId: string;
  naFila: boolean;
  desde: string | null;
}) {
  const [r, mudar] = useActionState(mudarFilaDeEntrada, INICIAL);

  return (
    <div className="rounded-cartao border border-linha bg-folha2 px-5 py-4">
      <p className="text-[13px] leading-relaxed text-tinta">
        {naFila ? (
          <>
            Na fila de entrada
            {desde && (
              <span className="text-tinta2">
                {" "}
                desde {new Date(desde).toLocaleDateString("pt-BR", { timeZone: "America/Sao_Paulo" })}
              </span>
            )}
            . Quando um horário fixo vagar, o sistema oferece — na ordem de
            chegada, uma pessoa por vez.
          </>
        ) : (
          <>
            Fora da fila de entrada. Quem liga sem haver horário entra aqui e é
            chamado sozinho quando alguém recebe alta.
          </>
        )}
      </p>

      <form action={mudar} className="mt-3">
        <input type="hidden" name="paciente" value={pacienteId} />
        <input type="hidden" name="entrar" value={naFila ? "0" : "1"} />
        <Botao rotulo={naFila ? "Tirar da fila de entrada" : "Colocar na fila de entrada"} />
      </form>

      {r.estado === "ok" && (
        <p className="mt-2 text-[12.5px] leading-relaxed text-cheia">{r.mensagem}</p>
      )}
      {r.estado === "erro" && (
        <ul className="mt-2 space-y-1">
          {r.erros.map((e, i) => (
            <li key={i} className="text-[12.5px] leading-relaxed text-vaga">
              {e}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
