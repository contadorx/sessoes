import Link from "next/link";
import { notFound } from "next/navigation";
import { sessaoAtual } from "@/lib/conta";
import { hoje } from "@/lib/tempo-servidor";
import { lerCustos, lerPrecos } from "../dados";
import { reais, somaDosCustos, mesPorExtenso } from "@/lib/negocio";
import { LancarCusto, DefinirPreco } from "@/components/app/NegocioAcoes";

export const metadata = { title: "Custos" };

/**
 * O que a operação custa, e quanto custa uma mensagem.
 *
 * As duas tabelas tinham RLS ligada e **nenhuma política** desde a OP1 — os
 * advisors reclamavam, e o efeito prático era que nem eu lia. A 0050 trocou
 * isso por duas funções de leitura e duas de escrita, todas com
 * `e_operador()`.
 *
 * A separação entre as duas metades desta tela não é arrumação: **custo fixo é
 * do mês, preço de canal é uma linha do tempo.** Lançar o Supabase de setembro
 * não muda agosto; declarar o preço do WhatsApp muda tudo daquela data em
 * diante e nada antes — e é por isso que a segunda metade recusa vigência no
 * passado, enquanto a primeira aceita qualquer mês.
 */
export default async function Custos({
  searchParams,
}: {
  searchParams: Promise<{ mes?: string }>;
}) {
  const sessao = await sessaoAtual();
  if (!sessao.operador) notFound();

  const params = await searchParams;
  const dia = hoje();
  const mes = /^\d{4}-(0[1-9]|1[0-2])$/.test(params.mes ?? "")
    ? `${params.mes}-01`
    : `${dia.slice(0, 7)}-01`;

  const [custos, precos] = await Promise.all([lerCustos(mes), lerPrecos()]);
  const total = somaDosCustos(custos);

  return (
    <div className="mx-auto max-w-3xl">
      <Link href="/negocio" className="text-[12.5px] text-tinta3 hover:text-vaga">
        ← o negócio
      </Link>

      <h1 className="mt-2 font-serif text-[26px] leading-tight tracking-[-0.015em]">
        O que a operação custa
      </h1>

      {/* --------------------------------------------------------- custo fixo */}
      <section className="mt-8">
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <h2 className="rotulo">Custo fixo · {mesPorExtenso(mes)}</h2>
          <span className="tabular font-mono text-[15px] font-medium text-tinta">
            {reais(total)}
          </span>
        </div>

        {custos.length === 0 ? (
          <p className="mt-3 text-[13px] text-tinta3">
            Nada lançado neste mês. Sem custo fixo declarado, a margem do painel é otimista —
            ela conta só a mensageria.
          </p>
        ) : (
          <ul className="mt-3 grid gap-px overflow-hidden rounded-cartao border border-linha bg-linha">
            {custos.map((c) => (
              <li key={c.rubrica} className="flex items-baseline gap-3 bg-folha px-4 py-2.5">
                <span className="text-[13px] text-tinta">{c.rubrica}</span>
                {c.nota && <span className="text-[11.5px] text-tinta3">{c.nota}</span>}
                <span className="tabular ml-auto font-mono text-[13px] text-tinta2">
                  {reais(c.centavos)}
                </span>
              </li>
            ))}
          </ul>
        )}

        <div className="mt-4 rounded-cartao border border-linha bg-folha2 px-4 py-3.5">
          <LancarCusto mes={mes} />
          <p className="mt-2 text-[11.5px] text-tinta3">
            Relançar a mesma rubrica atualiza o valor em vez de duplicar.
          </p>
        </div>
      </section>

      {/* ------------------------------------------------------ preço de canal */}
      <section className="mt-12">
        <h2 className="rotulo">Preço por mensagem</h2>
        <p className="mt-2 max-w-[64ch] text-[12.5px] leading-relaxed text-tinta3">
          Em milésimos de centavo, porque um e-mail custa 0,2 centavo e arredondar para centavo
          faria mil e-mails custarem nada. Cada linha vale <b className="font-medium">daquela data em
          diante</b> — é o que permite a margem de junho continuar sendo a de junho depois de o
          WhatsApp reajustar.
        </p>

        {precos.length === 0 ? (
          <p className="mt-3 text-[13px] text-tinta3">Nenhum preço declarado.</p>
        ) : (
          <ul className="mt-3 grid gap-px overflow-hidden rounded-cartao border border-linha bg-linha">
            {precos.map((p) => (
              <li
                key={`${p.canal}-${p.vigencia_inicio}`}
                className="flex items-baseline gap-3 bg-folha px-4 py-2.5"
              >
                <span className="w-24 text-[13px] text-tinta">{p.canal}</span>
                <span className="text-[12px] text-tinta3">
                  desde {p.vigencia_inicio.split("-").reverse().join("/")}
                </span>
                {p.fonte && <span className="text-[11.5px] text-tinta3">{p.fonte}</span>}
                <span className="tabular ml-auto font-mono text-[13px] text-tinta2">
                  {(p.centavos_milesimos / 1000).toFixed(3).replace(".", ",")} ¢
                </span>
              </li>
            ))}
          </ul>
        )}

        <div className="mt-4 rounded-cartao border border-linha bg-folha2 px-4 py-3.5">
          <DefinirPreco hoje={dia} />
          <p className="mt-2 text-[11.5px] text-tinta3">
            Vigência no passado é recusada: ela reescreveria a margem de um mês já fechado. Se o
            preço mudou, declare a partir de hoje.
          </p>
        </div>
      </section>
    </div>
  );
}
