import Link from "next/link";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { hoje } from "@/lib/tempo-servidor";
import {
  lerPainel,
  limitesDoMes,
  nomeDoMes,
  mesAnterior,
  mesSeguinte,
  competenciaDoDia,
  type PainelBruto,
} from "@/lib/financeiro";
import {
  PainelFinanceiro,
  type SemRegistro,
  type DespesaLinha,
} from "@/components/app/Financeiro";

export const metadata = { title: "Financeiro" };

export default async function Movimentacoes({
  searchParams,
}: {
  searchParams: Promise<{ mes?: string }>;
}) {
  const params = await searchParams;
  const atual = competenciaDoDia(hoje());

  // Competência inválida na URL não vira erro nem mês estranho: cai no mês
  // corrente. Ninguém digita isso à mão, e quem digita não merece uma tela
  // quebrada.
  const mes = /^\d{4}-(0[1-9]|1[0-2])$/.test(params.mes ?? "") ? params.mes! : atual;
  const { de, ate } = limitesDoMes(mes);

  const supabase = await supabaseSessao();

  const [bruto, faltando, gastos] = await Promise.all([
    db("financeiro.mes", supabase.rpc("financeiro_do_mes", { p_de: de, p_ate: ate })) as Promise<unknown>,
    db(
      "financeiro.sem_registro",
      supabase.rpc("sessoes_sem_registro", { p_de: de, p_ate: ate }),
    ) as Promise<unknown>,
    db(
      "despesas.listar",
      supabase
        .from("despesas")
        .select("id, paga_em, categoria, descricao, valor")
        .gte("paga_em", de)
        .lte("paga_em", ate)
        .order("paga_em", { ascending: false }),
    ) as Promise<unknown>,
  ]);

  const painel = lerPainel(bruto as PainelBruto);
  const semRegistro = (faltando ?? []) as SemRegistro[];
  const despesas = (gastos ?? []) as DespesaLinha[];

  const anterior = mesAnterior(mes);
  const seguinte = mesSeguinte(mes);

  return (
    <div className="mx-auto max-w-3xl">
      <div className="flex flex-wrap items-baseline gap-x-4 gap-y-1">
        <h1 className="font-serif text-[28px] leading-tight tracking-[-0.015em]">
          {nomeDoMes(mes)}
        </h1>
        <nav className="ml-auto flex items-center gap-3 text-[12.5px]">
          <Link href={`/recebimentos/movimentacoes?mes=${anterior}`} className="text-tinta2 hover:text-vaga">
            ← {nomeDoMes(anterior).split(" de ")[0]}
          </Link>
          {mes !== atual && (
            <Link href="/recebimentos/movimentacoes" className="text-tinta3 hover:text-vaga">
              hoje
            </Link>
          )}
          {seguinte <= atual && (
            <Link href={`/recebimentos/movimentacoes?mes=${seguinte}`} className="text-tinta2 hover:text-vaga">
              {nomeDoMes(seguinte).split(" de ")[0]} →
            </Link>
          )}
        </nav>
      </div>

      <p className="mt-3 max-w-2xl text-[14px] leading-relaxed text-tinta2">
        Nada aqui é digitado duas vezes: <b className="font-semibold text-tinta">a agenda é o
        faturamento</b>. O que você lança à mão é só o que a agenda não sabe — o que saiu.
      </p>

      <PainelFinanceiro
        painel={painel}
        semRegistro={semRegistro}
        despesas={despesas}
        hoje={hoje()}
      />

      {/* ------------------------------------------ o que este painel não é */}
      <section className="mt-10 border-t border-linha pt-6">
        <h2 className="rotulo">O que este painel não faz</h2>
        <ul className="mt-3 max-w-2xl space-y-2 text-[13px] leading-relaxed text-tinta2">
          <li>
            <b className="font-medium text-tinta">Não soma as duas colunas.</b> O que foi
            atendido e o que foi recebido são o mesmo mês visto de dois ângulos. Numa
            mensalidade, as quatro sessões e a mensalidade são o mesmo dinheiro — somar
            inventaria receita.
          </li>
          <li>
            <b className="font-medium text-tinta">Não diz o que abate imposto.</b> As
            categorias organizam; quem decide o que entra no livro caixa é o seu contador. O
            sistema entrega o número certo, não o parecer.
          </li>
          <li>
            <b className="font-medium text-tinta">Não é contas a pagar.</b> Despesa aqui é o
            que já saiu, com a data em que saiu. Sem vencimento, sem parcela, sem cobrança
            de você.
          </li>
          <li>
            <b className="font-medium text-tinta">Não fala de paciente na despesa.</b> A
            tabela nem tem esse campo — é o que garante que a pasta do contador leve dinheiro
            e nunca dado clínico.
          </li>
          <li>
            <b className="font-medium text-tinta">Não substitui o Receita Saúde.</b> Desde
            2025 cada atendimento tem de ser lançado no app ou no e-CAC da Receita Federal, e
            não existe API para fazer isso por você.{" "}
            <Link href="/fechamento/documentos" className="underline underline-offset-2 hover:text-vaga">
              Documentos
            </Link>{" "}
            explica o que sai daqui e o que não sai.
          </li>
        </ul>
      </section>
    </div>
  );
}
