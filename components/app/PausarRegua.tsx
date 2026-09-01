"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import { pausarRegua, type Resultado } from "@/app/(app)/recebimentos/acoes";

const INICIAL: Resultado = { estado: "inicial" };

function Botao({ rotulo }: { rotulo: string }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="rounded-full border border-linha2 bg-folha px-4 py-1.5 text-[12px] font-medium text-tinta2 transition-colors hover:bg-folha2 disabled:opacity-45"
    >
      {pending ? "…" : rotulo}
    </button>
  );
}

export function PausarRegua({
  pacienteId,
  pausada,
}: {
  pacienteId: string;
  pausada: boolean;
}) {
  const [r, despachar] = useActionState(pausarRegua, INICIAL);

  return (
    <form action={despachar}>
      <input type="hidden" name="paciente_id" value={pacienteId} />
      <input type="hidden" name="ativar" value={pausada ? "1" : "0"} />
      <Botao rotulo={pausada ? "Voltar a lembrar" : "Não lembrar esta pessoa"} />
      {r.estado === "ok" && (
        <p className="mt-1.5 text-[11.5px] leading-relaxed text-tinta3">{r.mensagem}</p>
      )}
      {r.estado === "erro" && (
        <p className="mt-1.5 text-[11.5px] text-vaga">{r.erros[0]}</p>
      )}
    </form>
  );
}
