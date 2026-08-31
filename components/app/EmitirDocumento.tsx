"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import { emitirDocumento, type Resultado } from "@/app/(app)/documentos/acoes";
import type { PacienteParaDoc } from "@/app/(app)/documentos/dados";

const INICIAL: Resultado = { estado: "inicial" };

const EXPLICACAO: Record<string, string> = {
  recibo:
    "Diz quanto foi pago, em quais datas, e nomeia o atendimento psicológico. É o que o convênio pede para reembolsar.",
  declaracao_comparecimento:
    "Diz só que a pessoa esteve presente, com data e horário. Não fala de dinheiro e não nomeia terapia — é para entregar no trabalho ou na escola.",
  informe_anual:
    "O total pago no ano, para a declaração de imposto de renda de quem pagou.",
};

function Enviar() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="rounded-full bg-vaga px-5 py-2 text-[13px] font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-40"
    >
      {pending ? "emitindo…" : "Emitir"}
    </button>
  );
}

/** Primeiro e último dia do mês passado — o pedido mais comum, já preenchido. */
function mesPassado(hoje: string): { de: string; ate: string } {
  const [a, m] = hoje.split("-").map(Number);
  const ano = m === 1 ? a - 1 : a;
  const mes = m === 1 ? 12 : m - 1;
  const ultimo = new Date(Date.UTC(ano, mes, 0)).getUTCDate();
  const mm = String(mes).padStart(2, "0");
  return { de: `${ano}-${mm}-01`, ate: `${ano}-${mm}-${ultimo}` };
}

const CAMPO =
  "w-full rounded-cartao border border-linha2 bg-folha px-3 py-2 text-[13px] text-tinta focus:border-tinta3 focus:outline-none";

export function EmitirDocumento({
  pacientes,
  hoje,
}: {
  pacientes: PacienteParaDoc[];
  hoje: string;
}) {
  const [r, despachar] = useActionState(emitirDocumento, INICIAL);
  const [tipo, setTipo] = useState("recibo");
  const padrao = mesPassado(hoje);

  if (pacientes.length === 0) {
    return (
      <p className="rounded-cartao border border-linha bg-folha2 px-5 py-4 text-[13px] leading-relaxed text-tinta2">
        Nenhuma sessão marcada como <b>realizada</b> ainda. Documento sai do que
        aconteceu — marque as sessões na agenda e volte aqui.
      </p>
    );
  }

  return (
    <form action={despachar} className="rounded-cartao border border-linha bg-folha2 px-5 py-4">
      <div className="grid gap-3 sm:grid-cols-2">
        <div className="sm:col-span-2">
          <label htmlFor="paciente_id" className="text-[12px] font-medium text-tinta2">
            Para quem
          </label>
          <select id="paciente_id" name="paciente_id" required className={`mt-1 ${CAMPO}`}>
            <option value="">escolha…</option>
            {pacientes.map((p) => (
              <option key={p.id} value={p.id}>
                {p.nome}
              </option>
            ))}
          </select>
        </div>

        <div className="sm:col-span-2">
          <label htmlFor="tipo" className="text-[12px] font-medium text-tinta2">
            Tipo
          </label>
          <select
            id="tipo"
            name="tipo"
            value={tipo}
            onChange={(e) => setTipo(e.target.value)}
            className={`mt-1 ${CAMPO}`}
          >
            <option value="recibo">Recibo</option>
            <option value="declaracao_comparecimento">Declaração de comparecimento</option>
            <option value="informe_anual">Informe anual</option>
          </select>
          <p className="mt-1 text-[11.5px] leading-relaxed text-tinta3">
            {EXPLICACAO[tipo]}
          </p>
        </div>

        <div>
          <label htmlFor="de" className="text-[12px] font-medium text-tinta2">
            De
          </label>
          <input
            id="de"
            name="de"
            type="date"
            required
            defaultValue={padrao.de}
            max={hoje}
            className={`mt-1 ${CAMPO}`}
          />
        </div>
        <div>
          <label htmlFor="ate" className="text-[12px] font-medium text-tinta2">
            Até
          </label>
          <input
            id="ate"
            name="ate"
            type="date"
            required
            defaultValue={padrao.ate}
            max={hoje}
            className={`mt-1 ${CAMPO}`}
          />
        </div>
      </div>

      {r.estado === "erro" && (
        <ul className="mt-3 space-y-1">
          {r.erros.map((e, i) => (
            <li key={i} className="text-[12.5px] leading-relaxed text-vaga">
              {e}
            </li>
          ))}
        </ul>
      )}

      <div className="mt-4">
        <Enviar />
      </div>
    </form>
  );
}
