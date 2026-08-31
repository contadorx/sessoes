"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import { venderPacote, cancelarPacote, type Resultado } from "@/app/(app)/pacientes/acoes";
import { formatar, paraCentavos } from "@/lib/dinheiro";
import { estadoDoPacote, rotuloDoPacote, type PacoteLinha } from "@/lib/cobranca";

const INICIAL: Resultado = { estado: "inicial" };

function Botao({ children }: { children: React.ReactNode }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="rounded-full bg-tinta px-4 py-1.5 text-[12.5px] font-medium text-papel transition-opacity hover:opacity-90 disabled:opacity-45"
    >
      {pending ? "…" : children}
    </button>
  );
}

const CAMPO =
  "w-full rounded-cartao border border-linha2 bg-folha px-3 py-2 text-[13px] text-tinta placeholder:text-tinta3 focus:border-tinta3 focus:outline-none";

/**
 * O painel do pacote.
 *
 * A informação que justifica esta tela existir é uma só: **quantos créditos
 * ainda há, e até quando**. Sem ela, o dia em que os créditos acabam é
 * descoberto pela cobrança — que chega ao paciente sem ninguém ter avisado, e
 * que a psicóloga descobre pela reclamação.
 *
 * Por isso o saldo aparece grande, o vencimento aparece junto, e o texto do
 * esgotado e do vencido diz explicitamente o que acontece a seguir.
 */
export function Pacote({
  pacienteId,
  pacotes,
  hoje,
  valorDaSessao,
}: {
  pacienteId: string;
  pacotes: PacoteLinha[];
  hoje: string;
  valorDaSessao: string | null;
}) {
  const [rVender, vender] = useActionState(venderPacote, INICIAL);
  const [rCancelar, cancelar] = useActionState(cancelarPacote, INICIAL);
  const [vendendo, setVendendo] = useState(false);

  const vivos = pacotes.filter((p) => estadoDoPacote(p, hoje) === "vivo");
  const outros = pacotes.filter((p) => estadoDoPacote(p, hoje) !== "vivo");

  // Uma sugestão que não é chute: dez sessões pelo valor da sessão. Ela troca
  // o número; o que não pode é a tela pedir um valor sem dar referência.
  const sugestao = valorDaSessao
    ? formatar(paraCentavos(valorDaSessao) * 10)
    : "";

  return (
    <div className="rounded-cartao border border-linha bg-folha2 px-5 py-4">
      {vivos.length === 0 && outros.length === 0 && (
        <p className="text-[13px] leading-relaxed text-tinta2">
          Nenhum pacote vendido. Enquanto não houver, as sessões são cobradas
          uma a uma.
        </p>
      )}

      {vivos.map((p) => (
        <div key={p.id} className="border-b border-linha pb-3 last:border-0 last:pb-0">
          <div className="flex flex-wrap items-baseline gap-x-3">
            <span className="font-mono text-[19px] text-cheia">
              {p.quantidade - p.consumidos}
            </span>
            <span className="text-[13px] text-tinta2">
              de {p.quantidade} crédito{p.quantidade > 1 ? "s" : ""} ·{" "}
              {formatar(paraCentavos(p.valor))}
            </span>
          </div>
          <p className="mt-1 text-[12.5px] leading-relaxed text-tinta2">
            {rotuloDoPacote(p, hoje)}
          </p>
          <form action={cancelar} className="mt-2">
            <input type="hidden" name="pacote" value={p.id} />
            <input type="hidden" name="paciente" value={pacienteId} />
            <button
              type="submit"
              className="text-[12px] text-tinta3 underline underline-offset-2 hover:text-vaga"
            >
              cancelar este pacote
            </button>
          </form>
        </div>
      ))}

      {outros.length > 0 && (
        <ul className="mt-3 space-y-1 border-t border-linha pt-3">
          {outros.map((p) => (
            <li key={p.id} className="text-[12px] leading-relaxed text-tinta3">
              {p.quantidade} crédito{p.quantidade > 1 ? "s" : ""} ·{" "}
              {rotuloDoPacote(p, hoje)}
            </li>
          ))}
        </ul>
      )}

      {!vendendo ? (
        <button
          type="button"
          onClick={() => setVendendo(true)}
          className="mt-3 text-[12.5px] font-medium text-vaga hover:underline"
        >
          Vender um pacote →
        </button>
      ) : (
        <form action={vender} className="mt-4 border-t border-linha pt-3">
          <input type="hidden" name="paciente" value={pacienteId} />
          <div className="grid gap-3 sm:grid-cols-3">
            <div>
              <label htmlFor="quantidade" className="text-[12px] font-medium text-tinta2">
                Sessões
              </label>
              <input
                id="quantidade"
                name="quantidade"
                type="number"
                min={1}
                max={60}
                defaultValue={10}
                className={`mt-1 ${CAMPO}`}
              />
            </div>
            <div>
              <label htmlFor="valor" className="text-[12px] font-medium text-tinta2">
                Valor total (R$)
              </label>
              <input
                id="valor"
                name="valor"
                inputMode="decimal"
                placeholder={sugestao || "1.800,00"}
                className={`mt-1 ${CAMPO}`}
              />
            </div>
            <div>
              <label htmlFor="validade" className="text-[12px] font-medium text-tinta2">
                Vale até
              </label>
              <input
                id="validade"
                name="validade"
                type="date"
                className={`mt-1 ${CAMPO}`}
              />
            </div>
          </div>

          <p className="mt-2 text-[11.5px] leading-relaxed text-tinta3">
            A validade é obrigatória: crédito sem prazo vira discussão três anos
            depois. Vender gera uma cobrança única do valor total — com o PIX
            junto, se você tiver chave cadastrada.
          </p>

          <div className="mt-3 flex items-center gap-3">
            <Botao>Vender</Botao>
            <button
              type="button"
              onClick={() => setVendendo(false)}
              className="text-[12.5px] text-tinta3 hover:text-tinta2"
            >
              cancelar
            </button>
          </div>
        </form>
      )}

      {[rVender, rCancelar].map((r, i) =>
        r.estado === "ok" ? (
          <p key={i} className="mt-2 text-[12.5px] text-cheia">
            {r.mensagem}
          </p>
        ) : r.estado === "erro" ? (
          <ul key={i} className="mt-2 space-y-1">
            {r.erros.map((e, j) => (
              <li key={j} className="text-[12.5px] leading-relaxed text-vaga">
                {e}
              </li>
            ))}
          </ul>
        ) : null,
      )}
    </div>
  );
}
