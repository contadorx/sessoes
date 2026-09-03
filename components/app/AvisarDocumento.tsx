"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import { avisarDocumento, type Resultado } from "@/app/(app)/fechamento/documentos/acoes";

const INICIAL: Resultado = { estado: "inicial" };

function Botao() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="min-h-11 rounded-full border border-linha2 px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2 disabled:opacity-60"
    >
      {pending ? "Enfileirando…" : "Avisar que está disponível"}
    </button>
  );
}

/**
 * O aviso de que o documento está na página da pessoa.
 *
 * Um toque, e o resultado é sempre dito — inclusive quando nada foi
 * enfileirado. A ação devolve nulo em dois casos legítimos (a pessoa pediu para
 * não ser avisada; o aviso deste documento já estava na fila), e engolir isso
 * num "pronto" seria a família de defeito que a B49 varreu: a ação que diz que
 * fez e não fez.
 *
 * `frase` vem do servidor e é a de `lib/promessa`: enquanto o envio automático
 * não estiver ligado, a mensagem nasce escrita e sai da mão dela. Automação
 * condicional se diz condicional.
 */
export function AvisarDocumento({
  documentoId,
  frase,
}: {
  documentoId: string;
  frase: string;
}) {
  const [r, despachar] = useActionState(avisarDocumento, INICIAL);

  return (
    <div className="mt-3">
      {r.estado !== "ok" && (
        <form action={despachar}>
          <input type="hidden" name="documento_id" value={documentoId} />
          <Botao />
        </form>
      )}

      {r.estado === "erro" && (
        <ul className="mt-2 text-[12.5px] leading-relaxed text-vaga">
          {r.erros.map((e) => (
            <li key={e}>{e}</li>
          ))}
        </ul>
      )}

      {r.estado === "ok" && (
        <p className="rounded-cartao border border-linha bg-folha2 px-4 py-3 text-[12.5px] leading-relaxed text-tinta2">
          {r.mensagem}
        </p>
      )}

      {r.estado !== "ok" && frase && (
        <p className="mt-2 text-[12px] leading-relaxed text-tinta3">{frase}</p>
      )}
    </div>
  );
}
