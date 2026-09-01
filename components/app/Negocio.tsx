import Link from "next/link";
import {
  reais,
  fraseDaOrigem,
  rotuloEstado,
  fraseDoLtv,
  sinaisDaConta,
  mesPorExtenso,
  margemDaConta,
  type Painel,
  type ContaNoPainel,
} from "@/lib/negocio";

/**
 * O painel do negócio.
 *
 * Duas regras de desenho, e as duas vêm de ter lido dois painéis parecidos:
 *
 * 1. **Todo número diz de onde veio.** No Enquadria conviviam três fórmulas de
 *    MRR e nenhuma tela dizia qual estava mostrando. Aqui o valor de cada conta
 *    carrega a procedência, e uma divergência entre as fontes aparece como
 *    aviso em vez de ser resolvida em silêncio.
 *
 * 2. **O custo tem o mesmo tamanho da receita na tela.** Nos dois aplicativos
 *    o MRR ocupa o topo e o custo não existe. Um produto cuja maior despesa é
 *    proporcional ao uso precisa das duas colunas lado a lado, senão a margem
 *    é descoberta na fatura.
 *
 * O que esta tela não mostra, e não é omissão: nada de paciente. Ela conta
 * sessões e não sabe de quem — fronteira 9 do doc 11.
 */

function Numero({
  rotulo,
  valor,
  nota,
  fraco,
}: {
  rotulo: string;
  valor: string;
  nota?: string | null;
  fraco?: boolean;
}) {
  return (
    <div className="rounded-cartao border border-linha bg-folha px-4 py-3">
      <p className="rotulo">{rotulo}</p>
      <p
        className={`mt-1 text-[19px] font-semibold tabular-nums ${
          fraco ? "text-tinta3" : "text-tinta"
        }`}
      >
        {valor}
      </p>
      {nota && <p className="mt-0.5 text-[11.5px] leading-relaxed text-tinta3">{nota}</p>}
    </div>
  );
}

export function PainelNegocio({
  painel,
  contas,
}: {
  painel: Painel | null;
  contas: ContaNoPainel[];
}) {
  if (!painel) {
    return (
      <p className="text-[13px] text-tinta2">
        O painel não voltou. Isso é erro, não ausência de dado — vale olhar o log.
      </p>
    );
  }

  const reais_ = painel.assinantes;
  const m = margemDaConta(painel.mrr_centavos, painel.custo_centavos);

  return (
    <>
      <header className="mb-5 flex flex-wrap items-baseline gap-x-4">
        <h1 className="text-[21px] font-semibold text-tinta">O negócio</h1>
        <Link
          href="/negocio/custos"
          className="text-[12.5px] text-tinta2 underline decoration-linha2 underline-offset-4 hover:text-vaga"
        >
          custos e preço por mensagem
        </Link>
        <p className="w-full text-[13px] text-tinta2">
          {mesPorExtenso(painel.mes)} · esta é a única tela do sistema que não é dela, e ela{" "}
          <b className="font-medium text-tinta">não alcança prontuário</b> — conta sessões, não
          sabe de quem.
        </p>
      </header>

      {/* ------------------------------------------------- receita e custo */}
      <section className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Numero
          rotulo="MRR"
          valor={reais(painel.mrr_centavos)}
          nota={`${reais_.ativas} ${reais_.ativas === 1 ? "conta ativa" : "contas ativas"}`}
        />
        <Numero
          rotulo="Custo do mês"
          valor={reais(painel.custo_centavos)}
          nota="mensageria + infra rateada"
        />
        <Numero
          rotulo="Sobra"
          valor={reais(m.sobra)}
          fraco={m.sobra <= 0}
          nota={m.pct === null ? "sem receita para dividir" : `${m.pct}% de margem`}
        />
        <Numero
          rotulo="Ticket"
          valor={reais(painel.ticket_centavos)}
          nota={`ARR ${reais(painel.arr_centavos)}`}
        />
      </section>

      <section className="mt-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Numero
          rotulo="Em teste"
          valor={String(reais_.trial)}
          nota={
            painel.mrr_potencial_centavos > 0
              ? `+ ${reais(painel.mrr_potencial_centavos)} em atraso, fora do MRR`
              : "não entram no MRR"
          }
        />
        <Numero
          rotulo="Em atraso"
          valor={String(reais_.em_atraso)}
          fraco={reais_.em_atraso === 0}
        />
        <Numero
          rotulo="Churn"
          valor={painel.churn.pct === null ? "—" : `${painel.churn.pct}%`}
          nota={
            painel.churn.base_inicial === 0
              ? "sem base no início do mês"
              : `${painel.churn.cancelaram} de ${painel.churn.base_inicial} que começaram o mês`
          }
        />
        <Numero
          rotulo="LTV"
          valor={painel.ltv_centavos === null ? "—" : reais(painel.ltv_centavos)}
          fraco={painel.ltv_centavos === null}
          nota={fraseDoLtv(painel.ltv_centavos)}
        />
      </section>

      {/* ------------------------------------------------------- as contas */}
      <section className="mt-8">
        <h2 className="rotulo">As contas</h2>

        {contas.length === 0 ? (
          <p className="mt-2 text-[13px] text-tinta2">Nenhuma conta ainda.</p>
        ) : (
          <div className="mt-2 overflow-x-auto">
            <table className="w-full min-w-[52rem] border-collapse text-[13px]">
              <thead>
                <tr className="border-b border-linha text-left text-[11px] uppercase tracking-wider text-tinta3">
                  <th className="py-2 pr-3 font-medium">Conta</th>
                  <th className="py-2 pr-3 font-medium">Plano</th>
                  <th className="py-2 pr-3 font-medium">Estado</th>
                  <th className="py-2 pr-3 text-right font-medium">Paga</th>
                  <th className="py-2 pr-3 text-right font-medium">Custa</th>
                  <th className="py-2 pr-3 text-right font-medium">Sobra</th>
                  <th className="py-2 pr-3 text-right font-medium">Sessões</th>
                  <th className="py-2 font-medium">Sinais</th>
                </tr>
              </thead>
              <tbody>
                {contas.map((c) => {
                  const sinais = sinaisDaConta(c);
                  const mm = margemDaConta(c.valor_centavos, c.custo_centavos);
                  return (
                    <tr
                      key={c.conta_id}
                      className={`border-b border-linha align-top ${
                        c.is_teste ? "opacity-45" : ""
                      }`}
                    >
                      <td className="py-2 pr-3">
                        {/* O nome leva à ficha. Era a peça que faltava: o
                            painel dizia "quanto" e não havia para onde clicar
                            quando eu queria saber "o quê". */}
                        <Link
                          href={`/negocio/${c.conta_id}`}
                          className="font-medium text-tinta underline decoration-linha2 underline-offset-4 hover:text-vaga"
                        >
                          {c.nome}
                        </Link>
                        {c.is_teste && (
                          <span className="ml-1.5 rounded-full border border-linha2 px-1.5 py-0.5 text-[10px] uppercase tracking-wider text-tinta3">
                            teste
                          </span>
                        )}
                      </td>
                      <td className="py-2 pr-3 text-tinta2">{c.plano}</td>
                      <td className="py-2 pr-3 text-tinta2">
                        {rotuloEstado(c.estado_assinatura)}
                      </td>
                      <td className="py-2 pr-3 text-right tabular-nums text-tinta">
                        {reais(c.valor_centavos)}
                        {/* A procedência do número, sempre. Um painel em que
                            não dá para desconfiar de um número é um painel em
                            que se acredita. */}
                        <span className="block text-[10.5px] font-normal text-tinta3">
                          {fraseDaOrigem(c.origem_do_valor)}
                        </span>
                      </td>
                      <td className="py-2 pr-3 text-right tabular-nums text-tinta2">
                        {reais(c.custo_centavos)}
                        <span className="block text-[10.5px] text-tinta3">
                          {c.mensagens_no_mes} msg
                        </span>
                      </td>
                      <td
                        className={`py-2 pr-3 text-right tabular-nums ${
                          mm.sobra < 0 ? "text-vaga" : "text-tinta"
                        }`}
                      >
                        {reais(mm.sobra)}
                      </td>
                      <td className="py-2 pr-3 text-right tabular-nums text-tinta2">
                        {c.sessoes_no_mes}
                      </td>
                      <td className="py-2">
                        {sinais.length === 0 ? (
                          <span className="text-tinta3">—</span>
                        ) : (
                          <ul className="space-y-0.5">
                            {sinais.map((s, i) => (
                              <li
                                key={i}
                                className={`text-[11.5px] leading-relaxed ${
                                  s.grave ? "text-vaga" : "text-tinta3"
                                }`}
                              >
                                {s.texto}
                              </li>
                            ))}
                          </ul>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <p className="mt-6 max-w-2xl text-[11.5px] leading-relaxed text-tinta3">
        Os preços de canal são estimativa do doc 10, não fatura — quando chegar a primeira conta
        do provedor, é ela que entra em <span className="font-mono">precos_canal</span>, com
        vigência, para não reescrever o passado. O custo fixo do mês é digitado em{" "}
        <span className="font-mono">custos_fixos</span> e rateado pelas contas pagantes.
      </p>
    </>
  );
}
