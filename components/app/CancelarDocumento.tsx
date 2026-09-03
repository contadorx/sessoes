"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import { cancelarDocumento, type Resultado } from "@/app/(app)/fechamento/documentos/acoes";

const INICIAL: Resultado = { estado: "inicial" };

/**
 * O botão que faltava.
 *
 * `cancelarDocumento` existia, correta, desde a B17 — e **nenhum arquivo `.tsx`
 * a importava**. A tela do documento até sabia desenhar o resultado: há dois
 * blocos que renderizam "Cancelado em … — motivo" e o carimbo na cópia
 * impressa. O que não havia era o caminho para produzir aquele estado.
 *
 * O que isso significava na mesa dela: um recibo emitido com o valor errado —
 * que leva o **nome e o CRP dela** e já foi entregue a alguém — não tinha como
 * ser cancelado pela interface. É um irreversível ao contrário: o irreversível
 * era não poder desfazer.
 *
 * **A palavra é "cancelar", e ela não é escolha de estilo.** A `/privacidade`
 * foi corrigida na B41 justamente para dizer que documento se cancela, com data
 * e motivo, e **não se exclui** — o número fica queimado, e sequência com
 * buraco é o que se audita. Um botão escrito "excluir" aqui faria a página
 * pública voltar a mentir.
 *
 * Duas etapas, no padrão da casa (`Privacidade.tsx`): cancelar um documento
 * emitido é irreversível na direção certa, e o motivo entra no lugar dele.
 */
export function CancelarDocumento({
  documentoId,
  numero,
}: {
  documentoId: string;
  numero: number | string;
}) {
  const [r, despachar] = useActionState(cancelarDocumento, INICIAL);
  const [confirmando, setConfirmando] = useState(false);

  if (r.estado === "ok") {
    return (
      <p className="mt-3 rounded-cartao border border-linha bg-folha2 px-4 py-3 text-[12.5px] leading-relaxed text-cheia">
        {r.mensagem}
      </p>
    );
  }

  if (!confirmando) {
    return (
      <button
        type="button"
        onClick={() => setConfirmando(true)}
        className="mt-3 min-h-11 rounded-full border border-linha2 px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2"
      >
        Cancelar este documento
      </button>
    );
  }

  return (
    <form
      action={despachar}
      className="mt-3 rounded-cartao border border-vaga-linha bg-vaga-bg px-4 py-3"
    >
      <input type="hidden" name="documento_id" value={documentoId} />

      <p className="text-[12.5px] leading-relaxed text-tinta2">
        Cancelar o documento nº <b className="font-medium text-tinta">{numero}</b>. Ele
        não é apagado: continua guardado, marcado como cancelado, e o número segue
        queimado — uma sequência com buraco é o que se audita. Se já entregou uma
        cópia, quem tem a cópia antiga não fica sabendo por aqui.
      </p>

      <label className="mt-2 block">
        <span className="text-[11.5px] text-tinta3">
          Por que está cancelando — fica no lugar do documento
        </span>
        <input
          name="motivo"
          required
          minLength={3}
          maxLength={200}
          placeholder="Valor errado; reemitido com o correto."
          className="mt-1 w-full rounded-cartao border border-linha2 bg-folha px-3 py-2 text-[13px] text-tinta placeholder:text-tinta3 focus:border-tinta3 focus:outline-none"
        />
      </label>

      <div className="mt-3 flex flex-wrap items-center gap-2">
        <Confirmar />
        <button
          type="button"
          onClick={() => setConfirmando(false)}
          className="min-h-11 rounded-full border border-linha2 bg-folha px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2"
        >
          deixa
        </button>
      </div>

      {r.estado === "erro" && (
        <p role="alert" className="mt-2 text-[12px] font-medium text-vaga">
          {r.erros.join(" ")}
        </p>
      )}
    </form>
  );
}

function Confirmar() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="min-h-11 rounded-full bg-vaga px-4 py-2 text-[12.5px] font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-45"
    >
      {pending ? "…" : "Sim, cancelar"}
    </button>
  );
}
