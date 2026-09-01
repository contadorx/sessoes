import Link from "next/link";
import { notFound } from "next/navigation";
import { obterDocumento, type DocumentoLinha } from "../dados";
import { Imprimir } from "@/components/app/Imprimir";
import { formatar, paraCentavos } from "@/lib/dinheiro";

export const metadata = { title: "Documento" };

const TITULO: Record<DocumentoLinha["tipo"], string> = {
  recibo: "Recibo",
  declaracao_comparecimento: "Declaração de comparecimento",
  informe_anual: "Informe anual de pagamentos",
};

const DIA = new Intl.DateTimeFormat("pt-BR", { timeZone: "America/Sao_Paulo" });
const DIA_E_HORA = new Intl.DateTimeFormat("pt-BR", {
  timeZone: "America/Sao_Paulo",
  day: "2-digit",
  month: "2-digit",
  year: "numeric",
  hour: "2-digit",
  minute: "2-digit",
});

/** "123.456.789-01" / "12.345.678/0001-99" — como as pessoas leem. */
function documento(bruto: string | null): string | null {
  if (!bruto) return null;
  if (bruto.length === 11) {
    return `${bruto.slice(0, 3)}.${bruto.slice(3, 6)}.${bruto.slice(6, 9)}-${bruto.slice(9)}`;
  }
  if (bruto.length === 14) {
    return `${bruto.slice(0, 2)}.${bruto.slice(2, 5)}.${bruto.slice(5, 8)}/${bruto.slice(8, 12)}-${bruto.slice(12)}`;
  }
  return bruto;
}

function porExtenso(iso: string): string {
  const [a, m, d] = iso.split("-").map(Number);
  return new Intl.DateTimeFormat("pt-BR", { day: "numeric", month: "long", year: "numeric" })
    .format(new Date(Date.UTC(a, m - 1, d)));
}

export default async function Documento({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const doc = await obterDocumento(id);
  if (!doc) notFound();

  const r = doc.retrato;
  const total = formatar(paraCentavos(doc.valor_total));
  const ehDeclaracao = doc.tipo === "declaracao_comparecimento";
  const cidade = r.conta?.cidade ?? null;

  return (
    <div className="mx-auto max-w-3xl">
      {/* -------------------------------------------- o que não é impresso */}
      <div className="nao-imprime">
        <Link href="/fechamento/documentos" className="text-[12.5px] text-tinta3 hover:text-vaga">
          ← documentos
        </Link>

        {doc.cancelado_em && (
          <p className="mt-3 rounded-cartao border border-vaga-linha bg-vaga-bg px-4 py-3 text-[13px] leading-relaxed text-tinta2">
            <b className="font-semibold text-vaga">Cancelado</b> em{" "}
            {DIA.format(new Date(doc.cancelado_em))} — {doc.motivo_cancelamento}. O
            número {doc.numero} continua queimado.
          </p>
        )}

        {!ehDeclaracao && (
          <div className="mt-3 rounded-cartao border border-linha bg-folha2 px-4 py-3">
            <p className="text-[13px] leading-relaxed text-tinta2">
              <b className="font-semibold text-tinta">
                Isto não substitui o Receita Saúde.
              </b>{" "}
              Desde 2025, o recibo de cada atendimento precisa ser emitido por você
              no app ou no e-CAC da Receita Federal — a multa é de R$ 100 por
              mês-calendário ou fração por recibo que faltar. Não existe API
              pública: ninguém consegue emitir no seu lugar.
            </p>
            <p className="mt-2 text-[12.5px] leading-relaxed text-tinta3">
              Este documento serve para a pessoa pedir reembolso ao convênio e
              para o registro de vocês dois. Os dois existem, e um não dispensa o
              outro.
            </p>
          </div>
        )}

        <div className="mt-4">
          <Imprimir />
        </div>
      </div>

      {/* ------------------------------------------------------- o papel */}
      <article className="papel mt-6 rounded-cartao border border-linha bg-folha px-8 py-10">
        <header>
          <p className="font-serif text-[19px] leading-tight text-tinta">
            {r.profissional?.nome ?? r.conta?.nome ?? "—"}
          </p>
          <p className="mt-0.5 text-[12.5px] text-tinta2">
            {[
              r.profissional?.crp ? `CRP ${r.profissional.crp}` : null,
              documento(r.profissional?.documento ?? null),
            ]
              .filter(Boolean)
              .join(" · ") || "—"}
          </p>
        </header>

        <h1 className="mt-8 font-serif text-[23px] leading-tight tracking-[-0.01em] text-tinta">
          {TITULO[doc.tipo]}
        </h1>
        <p className="mt-0.5 font-mono text-[12px] text-tinta3">
          nº {String(doc.numero).padStart(6, "0")}
        </p>

        <p className="mt-6 text-[14px] leading-[1.7] text-tinta">
          {ehDeclaracao ? (
            <>
              Declaro para os devidos fins que{" "}
              <b className="font-semibold">{r.paciente.nome}</b>
              {r.paciente.cpf ? `, CPF ${documento(r.paciente.cpf)},` : ""} esteve
              presente em <b className="font-semibold">{doc.quantidade}</b>{" "}
              atendimento{doc.quantidade > 1 ? "s" : ""} nas datas e horários
              relacionados abaixo.
            </>
          ) : (
            <>
              Recebi de <b className="font-semibold">{r.paciente.nome}</b>
              {r.paciente.cpf ? `, CPF ${documento(r.paciente.cpf)},` : ""} a
              importância de <b className="font-semibold">{total}</b>, referente a{" "}
              <b className="font-semibold">{doc.quantidade}</b> atendimento
              {doc.quantidade > 1 ? "s" : ""} psicológico
              {doc.quantidade > 1 ? "s" : ""} prestado
              {doc.quantidade > 1 ? "s" : ""} no período de{" "}
              {porExtenso(doc.periodo_de)} a {porExtenso(doc.periodo_ate)}.
            </>
          )}
        </p>

        <table className="mt-6 w-full text-[13px]">
          <thead>
            <tr className="border-b border-linha2">
              <th className="py-1.5 text-left font-medium text-tinta3">
                {ehDeclaracao ? "data e horário" : "data"}
              </th>
              {!ehDeclaracao && (
                <th className="py-1.5 text-right font-medium text-tinta3">valor</th>
              )}
            </tr>
          </thead>
          <tbody>
            {r.itens.map((item, i) => (
              <tr key={i} className="border-b border-linha">
                <td className="py-1.5 text-tinta tabular-nums">
                  {ehDeclaracao
                    ? DIA_E_HORA.format(new Date(item.inicio))
                    : DIA.format(new Date(item.inicio))}
                </td>
                {!ehDeclaracao && (
                  <td className="py-1.5 text-right font-mono text-tinta tabular-nums">
                    {item.valor ? formatar(paraCentavos(item.valor)) : "—"}
                  </td>
                )}
              </tr>
            ))}
          </tbody>
          {!ehDeclaracao && (
            <tfoot>
              <tr>
                <td className="pt-2 text-[13px] font-semibold text-tinta">Total</td>
                <td className="pt-2 text-right font-mono text-[14px] font-semibold text-tinta tabular-nums">
                  {total}
                </td>
              </tr>
            </tfoot>
          )}
        </table>

        <p className="mt-10 text-[13px] text-tinta2">
          {cidade ? `${cidade}, ` : ""}
          {porExtenso(doc.emitido_em.slice(0, 10))}.
        </p>

        <div className="mt-12">
          <div className="w-64 border-t border-tinta2" />
          <p className="mt-1.5 text-[12.5px] text-tinta">
            {r.profissional?.nome ?? "—"}
          </p>
          {r.profissional?.crp && (
            <p className="text-[11.5px] text-tinta3">CRP {r.profissional.crp}</p>
          )}
        </div>

        {!ehDeclaracao && (
          <p className="mt-10 border-t border-linha pt-3 text-[10.5px] leading-relaxed text-tinta3">
            Este documento comprova o pagamento entre as partes. Ele não substitui
            o recibo emitido no Receita Saúde da Receita Federal, que é o que
            alimenta a declaração de imposto de renda de quem pagou.
          </p>
        )}

        {doc.cancelado_em && (
          <p className="mt-4 text-[11px] font-semibold uppercase tracking-wider text-vaga">
            documento cancelado
          </p>
        )}
      </article>
    </div>
  );
}
