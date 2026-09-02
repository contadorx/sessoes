"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import {
  abrirLinkDoPaciente,
  revogarLinkDoPaciente,
  type Resultado,
} from "@/app/(app)/pacientes/acoes";
import type { LinkDoPaciente as Linha } from "@/app/(app)/pacientes/dados";

const INICIAL: Resultado = { estado: "inicial" };

function Enviar({ rotulo, ocupado }: { rotulo: string; ocupado: string }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="rounded-full border border-linha2 bg-folha px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2 disabled:opacity-45"
    >
      {pending ? ocupado : rotulo}
    </button>
  );
}

function dataCurta(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "—";
  return d.toLocaleDateString("pt-BR", { timeZone: "America/Sao_Paulo" });
}

/**
 * O link da página do paciente (P7), do lado dela.
 *
 * **Ela manda, e não o sistema.** É a mesma regra do contrato (B19) e da
 * remarcação (B21), e ela não é preguiça de integração: um link que sai sozinho
 * pelo outbox chega do número do Sessões, e o paciente recebe um endereço para
 * a vida financeira dele vindo de um número que ele não conhece. Vindo dela,
 * com uma frase dela, é uma mensagem que ele reconhece.
 *
 * **Gerar de novo revoga o anterior**, e a tela diz isso antes do clique — do
 * contrário ela mandaria o link novo achando que os dois valem, e o paciente
 * que guardou o antigo cairia numa página morta sem entender por quê.
 *
 * **O contador de aberturas fica aqui, e não na trilha de acesso.** A trilha
 * responde quem, dentro da conta, leu prontuário de quem, e é lida atrás do
 * acesso clínico; misturar abertura de link ali diluiria a única tela de
 * auditoria do produto. Aqui ele responde a única pergunta que ela faz sobre
 * isso: *ele chegou a abrir?*
 */
export function LinkDoPaciente({
  pacienteId,
  pacienteNome,
  telefone,
  link,
}: {
  pacienteId: string;
  pacienteNome: string;
  telefone: string | null;
  link: Linha | null;
}) {
  const [rAbrir, abrir] = useActionState(abrirLinkDoPaciente, INICIAL);
  const [rRevogar, revogar] = useActionState(revogarLinkDoPaciente, INICIAL);
  const [copiado, setCopiado] = useState(false);

  // O token recém-criado vem na resposta da ação; o da linha é o que já
  // existia. O primeiro ganha, porque é o que ela acabou de pedir.
  const token = rAbrir.estado === "ok" ? rAbrir.mensagem : (link?.token ?? null);

  const url =
    token && typeof window !== "undefined" ? `${window.location.origin}/p/agora/${token}` : "";

  const primeiro = pacienteNome.trim().split(/\s+/)[0];
  const convite =
    `Oi, ${primeiro}. Nesta página fica o que estiver esperando por você — ` +
    `horário para confirmar, pagamento e documento: ${url}`;

  const zap = telefone
    ? `https://wa.me/${telefone.replace(/\D/g, "")}?text=${encodeURIComponent(convite)}`
    : null;

  async function copiar() {
    try {
      await navigator.clipboard.writeText(url);
      setCopiado(true);
      window.setTimeout(() => setCopiado(false), 4000);
    } catch {
      setCopiado(false);
    }
  }

  return (
    <div className="rounded-cartao border border-linha bg-folha2 px-5 py-4">
      <p className="text-[13px] leading-relaxed text-tinta">
        {token
          ? "A página do paciente está no ar. Um link por vez, e ele vale 30 dias."
          : "A página do paciente reúne, num link só, o horário a confirmar, o pagamento em aberto e os documentos dos últimos três meses."}
      </p>

      {(rAbrir.estado === "erro" || rRevogar.estado === "erro") && (
        <p className="mt-2.5 text-[12.5px] leading-relaxed text-aviso">
          {(rAbrir.estado === "erro" ? rAbrir.erros : rRevogar.estado === "erro" ? rRevogar.erros : [])[0]}
        </p>
      )}

      {rRevogar.estado === "ok" && (
        <p className="mt-2.5 text-[12.5px] leading-relaxed text-tinta2">{rRevogar.mensagem}</p>
      )}

      {token && (
        <>
          <p className="mt-3 break-all rounded-cartao border border-linha bg-folha px-3.5 py-2.5 font-mono text-[11.5px] leading-relaxed text-tinta2">
            {url || "…"}
          </p>

          {link && (
            <p className="mt-2 text-[12px] leading-relaxed text-tinta3">
              Vale até {dataCurta(link.expira_em)} ·{" "}
              {link.aberturas === 0
                ? "ainda não foi aberto"
                : link.aberturas === 1
                  ? "aberto uma vez"
                  : `aberto ${link.aberturas} vezes`}
            </p>
          )}

          <div className="mt-3 flex flex-wrap items-center gap-2">
            <button
              type="button"
              onClick={copiar}
              disabled={!url}
              className="rounded-full border border-linha2 bg-folha px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2 disabled:opacity-45"
            >
              {copiado ? "copiado" : "copiar o link"}
            </button>

            {zap && url && (
              <a
                href={zap}
                target="_blank"
                rel="noopener noreferrer"
                className="rounded-full bg-vaga px-4 py-2 text-[12.5px] font-semibold text-white transition-opacity hover:opacity-90"
              >
                mandar no WhatsApp
              </a>
            )}

            <form action={revogar}>
              <input type="hidden" name="paciente_id" value={pacienteId} />
              <Enviar rotulo="revogar" ocupado="revogando…" />
            </form>
          </div>
        </>
      )}

      <form action={abrir} className="mt-3">
        <input type="hidden" name="paciente_id" value={pacienteId} />
        <Enviar
          rotulo={token ? "gerar um link novo (o atual para de valer)" : "gerar o link"}
          ocupado="gerando…"
        />
      </form>
    </div>
  );
}
