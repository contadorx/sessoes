"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import { substituirEnquadre, type Resultado } from "@/app/(app)/pacientes/acoes";
import type { EnquadreLinha } from "@/app/(app)/pacientes/dados";
import { CamposEnquadre } from "./FormPaciente";
import { Campo, Erros, ENTRADA } from "./campos";

const INICIAL: Resultado = { estado: "inicial" };

function Salvar() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="rounded-full bg-vaga px-6 py-2.5 text-[13.5px] font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-45"
    >
      {pending ? "Salvando…" : "Abrir novo combinado"}
    </button>
  );
}

export function NovoEnquadre({
  pacienteId,
  aberto,
}: {
  pacienteId: string;
  aberto: EnquadreLinha | null;
}) {
  const [abertoNaTela, setAbertoNaTela] = useState(false);
  const [estado, despachar] = useActionState(substituirEnquadre, INICIAL);
  const erros = estado.estado === "erro" ? estado.erros : [];

  if (!abertoNaTela) {
    return (
      <button
        type="button"
        onClick={() => setAbertoNaTela(true)}
        className="mt-3 text-[13px] font-medium text-vaga hover:underline"
      >
        {aberto ? "Reajustar ou mudar o horário →" : "Definir o combinado →"}
      </button>
    );
  }

  return (
    <form
      action={despachar}
      className="mt-4 rounded-cartao border border-linha bg-folha p-6"
    >
      <input type="hidden" name="paciente_id" value={pacienteId} />
      {aberto && <input type="hidden" name="enquadre_aberto_id" value={aberto.id} />}

      {aberto && (
        <Campo rotulo="Por quê" dica="O combinado atual é fechado hoje e o novo passa a valer.">
          <select name="motivo_fim" defaultValue="reajuste" className={ENTRADA}>
            <option value="reajuste">reajuste de valor</option>
            <option value="mudanca_horario">mudança de horário</option>
            <option value="encerramento">encerramento</option>
          </select>
        </Campo>
      )}

      <CamposEnquadre base={aberto ?? undefined} />

      <Erros erros={erros} />

      <div className="mt-6 flex items-center gap-4">
        <Salvar />
        <button
          type="button"
          onClick={() => setAbertoNaTela(false)}
          className="text-[13px] text-tinta3 hover:text-tinta2"
        >
          cancelar
        </button>
      </div>
    </form>
  );
}
