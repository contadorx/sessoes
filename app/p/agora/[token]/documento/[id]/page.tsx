import Link from "next/link";
import { notFound } from "next/navigation";
import { db } from "@/lib/db";
import { supabaseServer } from "@/lib/supabase/server";
import { Imprimir } from "@/components/app/Imprimir";
import { dia, rotuloDoDocumento, numeroDoDocumento, valorEmReais, quando } from "@/lib/pagina-do-paciente";

export const metadata = {
  title: "Sua página",
  robots: { index: false, follow: false },
  openGraph: { title: "Sua página", description: "" },
};

export const dynamic = "force-dynamic";

type Retrato = {
  profissional?: { nome?: string; crp?: string; documento?: string };
  conta?: { nome?: string; cidade?: string };
  paciente?: { nome?: string; cpf?: string };
  base?: string;
  itens?: { inicio?: string; dia?: string; valor?: number | string }[];
};

type Visto = {
  estado: "aberta" | "expirada" | "inexistente";
  tipo?: string;
  numero?: number;
  emitido_em?: string;
  periodo_de?: string | null;
  periodo_ate?: string | null;
  valor_total?: number | string | null;
  quantidade?: number | null;
  retrato?: Retrato;
};

/**
 * O documento do paciente, em papel.
 *
 * **O motor de PDF deste produto é o navegador**, e a decisão é da B33: uma
 * biblioteca de PDF em serverless significa posicionar texto à mão, e o
 * conteúdo aqui é de tamanho variável — um mês com duas sessões e outro com
 * dez quebram layouts fixos de formas diferentes, que só aparecem no mês em
 * que quebram. Então é uma página `.papel` com `@media print`, e o botão faz
 * `window.print()`. O paciente salva em PDF ou imprime, do jeito que preferir.
 *
 * **Nada aqui é recalculado.** Tudo sai de `documentos.retrato`, congelado pela
 * 0029 no instante da emissão. Um papel que se recompõe a cada leitura é um
 * papel que muda de conteúdo depois de assinado — e este vai para operadora de
 * plano e para declaração de imposto de renda de duas pessoas.
 *
 * O componente `Imprimir` vem de `components/app/`, e não há problema nisso: ele
 * é um botão de vinte linhas sem estado, sem contexto e sem dependência de
 * sessão. O comportamento de impressão inteiro mora no `@media print` do
 * `globals.css`, que já esconde `.nao-imprime` e tira a moldura de `.papel`.
 */
export default async function DocumentoDoPaciente({
  params,
}: {
  params: Promise<{ token: string; id: string }>;
}) {
  const { token, id } = await params;
  const supabase = supabaseServer();

  const visto = (await db(
    "paciente.documento",
    supabase.rpc("documento_do_link", { p_token: token, p_documento: id }),
  )) as unknown as Visto;

  if (!visto || visto.estado !== "aberta") notFound();

  const r = visto.retrato ?? {};
  const itens = r.itens ?? [];
  const temValor = itens.some((i) => i.valor !== undefined && i.valor !== null);

  return (
    <main className="mx-auto max-w-2xl px-5 py-8 sm:px-8 sm:py-12">
      <div className="nao-imprime">
        <Link
          href={`/p/agora/${token}`}
          className="text-[13px] font-medium text-tinta2 underline decoration-linha2 underline-offset-4 transition-colors hover:text-vaga"
        >
          ← voltar
        </Link>
        <div className="mt-4">
          <Imprimir />
        </div>
      </div>

      <article className="papel mt-6 rounded-cartao border border-linha bg-folha px-6 py-8 sm:px-10 sm:py-12">
        <header>
          <p className="rotulo">{rotuloDoDocumento(visto.tipo ?? "")}</p>
          <h1 className="mt-1 font-serif text-[22px] leading-tight tracking-[-0.015em] text-tinta">
            nº {numeroDoDocumento(visto.numero ?? 0)}
          </h1>
          <p className="mt-1 text-[12.5px] text-tinta3">
            Emitido em {dia(visto.emitido_em)}
          </p>
        </header>

        <dl className="mt-7 grid gap-x-6 gap-y-3 border-t border-linha pt-6 sm:grid-cols-2">
          <div>
            <dt className="text-[11px] uppercase tracking-wider text-tinta3">Emitido por</dt>
            <dd className="mt-0.5 text-[14px] text-tinta">{r.profissional?.nome ?? "—"}</dd>
            {r.profissional?.crp && (
              <dd className="text-[12.5px] text-tinta2">CRP {r.profissional.crp}</dd>
            )}
            {r.profissional?.documento && (
              <dd className="text-[12.5px] text-tinta2">{r.profissional.documento}</dd>
            )}
          </div>
          <div>
            <dt className="text-[11px] uppercase tracking-wider text-tinta3">Para</dt>
            <dd className="mt-0.5 text-[14px] text-tinta">{r.paciente?.nome ?? "—"}</dd>
            {r.paciente?.cpf && (
              <dd className="text-[12.5px] text-tinta2">CPF {r.paciente.cpf}</dd>
            )}
          </div>
          {(visto.periodo_de || visto.periodo_ate) && (
            <div>
              <dt className="text-[11px] uppercase tracking-wider text-tinta3">Período</dt>
              <dd className="mt-0.5 text-[14px] text-tinta">
                {dia(visto.periodo_de)} a {dia(visto.periodo_ate)}
              </dd>
            </div>
          )}
          {visto.quantidade != null && (
            <div>
              <dt className="text-[11px] uppercase tracking-wider text-tinta3">Horários</dt>
              <dd className="mt-0.5 text-[14px] text-tinta">{visto.quantidade}</dd>
            </div>
          )}
        </dl>

        {itens.length > 0 && (
          <div className="mt-7 border-t border-linha pt-6">
            <table className="w-full text-[13px]">
              <thead>
                <tr className="text-left text-[11px] uppercase tracking-wider text-tinta3">
                  <th className="pb-2 font-normal">Data</th>
                  {temValor && <th className="pb-2 text-right font-normal">Valor</th>}
                </tr>
              </thead>
              <tbody>
                {itens.map((i, n) => (
                  <tr key={`${i.dia ?? i.inicio ?? n}-${n}`} className="border-t border-linha">
                    <td className="py-2 text-tinta2">{i.inicio ? quando(i.inicio) : dia(i.dia)}</td>
                    {temValor && (
                      <td className="tabular py-2 text-right font-mono text-tinta">
                        {i.valor != null ? valorEmReais(i.valor) : "—"}
                      </td>
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {visto.valor_total != null && (
          <p className="mt-6 border-t border-linha pt-5 text-right">
            <span className="text-[12px] uppercase tracking-wider text-tinta3">Total</span>{" "}
            <span className="tabular ml-2 font-mono text-[18px] font-medium text-tinta">
              {valorEmReais(visto.valor_total)}
            </span>
          </p>
        )}

        {/* A cidade vem do cadastro da conta e é o que localiza o documento —
            um recibo sem lugar é um recibo que a operadora devolve. */}
        {r.conta?.cidade && (
          <p className="mt-8 text-[12.5px] text-tinta2">
            {r.conta.cidade}, {dia(visto.emitido_em)}.
          </p>
        )}
      </article>

      {/* Fora do papel de propósito: é orientação para quem está lendo na tela,
          e não parte do documento. Imprimir um aviso sobre o próprio documento
          dentro dele confunde quem recebe o papel depois. */}
      <p className="nao-imprime mt-4 text-[12px] leading-relaxed text-tinta3">
        Este é o documento como ele foi emitido. Se algum dado estiver errado,
        fale com quem te enviou o link — um documento emitido não se corrige por
        cima, ele se cancela e outro é emitido no lugar.
      </p>
    </main>
  );
}
