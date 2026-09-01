import Link from "next/link";
import { listarDocumentos, pacientesComAtendimento } from "./dados";
import { EmitirDocumento } from "@/components/app/EmitirDocumento";
import { formatar, paraCentavos } from "@/lib/dinheiro";
import { hoje } from "@/lib/tempo-servidor";

export const metadata = { title: "Documentos" };

const ROTULO = {
  recibo: "recibo",
  declaracao_comparecimento: "declaração",
  informe_anual: "informe anual",
} as const;

const DIA = new Intl.DateTimeFormat("pt-BR", { timeZone: "America/Sao_Paulo" });

export default async function DocumentosEmitidos() {
  const [documentos, pacientes] = await Promise.all([
    listarDocumentos(),
    pacientesComAtendimento(),
  ]);

  return (
    <div className="mx-auto max-w-3xl">
      <h1 className="font-serif text-[28px] leading-tight tracking-[-0.015em]">
        Documentos
      </h1>
      <p className="mt-2 max-w-xl text-[14px] leading-relaxed text-tinta2">
        Recibo para reembolso, declaração de comparecimento e informe anual. Sai
        do que já está na agenda — <b>só as sessões marcadas como realizadas</b>.
        Falta cobrada não entra: não é atendimento prestado, e convênio nenhum
        reembolsa.
      </p>

      <section className="mt-6">
        <EmitirDocumento pacientes={pacientes} hoje={hoje()} />
      </section>

      <section className="mt-10">
        <h2 className="rotulo">Emitidos</h2>

        {documentos.length === 0 ? (
          <p className="mt-3 rounded-cartao border border-linha bg-folha2 px-5 py-4 text-[13px] leading-relaxed text-tinta2">
            Nenhum ainda. Os números são sequenciais e por conta — o primeiro vai
            ser o 000001.
          </p>
        ) : (
          <div className="mt-3 overflow-x-auto rounded-cartao border border-linha">
            <table className="w-full text-[13px]">
              <thead>
                <tr className="border-b border-linha bg-folha2">
                  <th className="px-3 py-2 text-left font-medium text-tinta3">nº</th>
                  <th className="px-3 py-2 text-left font-medium text-tinta3">tipo</th>
                  <th className="px-3 py-2 text-left font-medium text-tinta3">para</th>
                  <th className="px-3 py-2 text-left font-medium text-tinta3">período</th>
                  <th className="px-3 py-2 text-right font-medium text-tinta3">valor</th>
                </tr>
              </thead>
              <tbody>
                {documentos.map((d) => (
                  <tr
                    key={d.id}
                    className={`border-b border-linha last:border-0 ${
                      d.cancelado_em ? "opacity-50" : ""
                    }`}
                  >
                    <td className="px-3 py-2 font-mono text-[12px] tabular-nums text-tinta2">
                      <Link href={`/fechamento/documentos/${d.id}`} className="hover:text-vaga">
                        {String(d.numero).padStart(6, "0")}
                      </Link>
                    </td>
                    <td className="px-3 py-2 text-tinta2">
                      {ROTULO[d.tipo]}
                      {d.cancelado_em && (
                        <span className="ml-1 text-[11px] text-vaga">· cancelado</span>
                      )}
                    </td>
                    <td className="px-3 py-2 text-tinta">
                      {d.retrato?.paciente?.nome ?? d.pacientes?.nome ?? "—"}
                    </td>
                    <td className="px-3 py-2 tabular-nums text-tinta2">
                      {DIA.format(new Date(`${d.periodo_de}T12:00:00Z`))} –{" "}
                      {DIA.format(new Date(`${d.periodo_ate}T12:00:00Z`))}
                    </td>
                    <td className="px-3 py-2 text-right font-mono text-[12px] tabular-nums text-tinta2">
                      {d.tipo === "declaracao_comparecimento"
                        ? "—"
                        : formatar(paraCentavos(d.valor_total))}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        <p className="mt-3 text-[11.5px] leading-relaxed text-tinta3">
          Documento emitido não se edita. Se algo saiu errado, cancele e emita
          outro — o número cancelado fica queimado, porque sequência com buraco é
          auditável e sequência remontada não é.
        </p>
      </section>
    </div>
  );
}
