import Link from "next/link";
import { notFound } from "next/navigation";
import { sessaoAtual } from "@/lib/conta";
import { lerFicha, lerPlanos } from "../dados";
import {
  reais,
  fraseDaOrigem,
  rotuloEstado,
  rotuloFatura,
  acoesDaAssinatura,
  margemDaConta,
  type OrigemDoValor,
  type EstadoAssinatura,
  type EstadoFatura,
} from "@/lib/negocio";
import {
  AbrirAssinatura,
  MudarPlano,
  CancelarAssinatura,
  EmitirFatura,
  AcoesDaFatura,
  MarcaDeTeste,
} from "@/components/app/NegocioAcoes";

export const metadata = { title: "Conta" };

/**
 * Uma conta, por dentro.
 *
 * A tabela do painel responde *quanto*; esta tela responde *o quê*: desde
 * quando, em que plano estava antes, se a fatura de agosto saiu, e se a conta
 * está viva.
 *
 * E responde a última pergunta com **contagem**. É aqui que mora a tentação de
 * "deixa eu só ver o que está acontecendo com essa cliente", e a resposta desta
 * tela a essa frase é um número: quantos pacientes, quantas sessões, quantas
 * mensagens. Nome de paciente não passa por aqui — a função do banco é escrita
 * com colunas nomeadas e a suíte 0050 planta um nome improvável na base para
 * reprovar se ele aparecer.
 */
export default async function ContaDoPainel({
  params,
}: {
  params: Promise<{ conta: string }>;
}) {
  const sessao = await sessaoAtual();
  if (!sessao.operador) notFound();

  const { conta: id } = await params;
  const [ficha, planos] = await Promise.all([lerFicha(id), lerPlanos()]);

  if (!ficha?.conta) notFound();

  const c = ficha.conta;
  const viva = ficha.assinaturas.find((a) =>
    ["trial", "ativa", "em_atraso"].includes(a.estado),
  );
  const acoes = acoesDaAssinatura((viva?.estado ?? "sem_assinatura") as EstadoAssinatura);
  const m = margemDaConta(ficha.valor?.valor_centavos ?? 0, ficha.custo?.custo_centavos ?? 0);

  return (
    <div className="mx-auto max-w-3xl">
      <Link href="/negocio" className="text-[12.5px] text-tinta3 hover:text-vaga">
        ← o negócio
      </Link>

      <div className="mt-2 flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <h1 className="font-serif text-[26px] leading-tight tracking-[-0.015em]">{c.nome}</h1>
        <span className="text-[12.5px] text-tinta3">
          {c.tipo} · {c.plano} · desde {c.criado_em.slice(0, 10).split("-").reverse().join("/")}
        </span>
        {c.is_teste && (
          <span className="rounded-full bg-aviso-bg px-2 py-0.5 text-[11px] font-medium text-aviso">
            conta de teste
          </span>
        )}
      </div>

      {/* ------------------------------------------------------------ o dinheiro */}
      <section className="mt-8">
        <h2 className="rotulo">O que ela vale</h2>
        <dl className="mt-3 grid gap-px overflow-hidden rounded-cartao border border-linha bg-linha sm:grid-cols-3">
          {[
            { r: "paga", v: reais(m.receita), n: ficha.valor ? fraseDaOrigem(ficha.valor.origem as OrigemDoValor) : "—" },
            { r: "custa", v: reais(m.custo), n: "mensageria do mês, pelo preço vigente" },
            {
              r: "sobra",
              v: reais(m.sobra),
              n: m.pct === null ? "sem receita para dividir" : `${m.pct}% de margem`,
            },
          ].map((i) => (
            <div key={i.r} className="bg-folha px-5 py-4">
              <dt className="rotulo">{i.r}</dt>
              <dd>
                <span className="tabular mt-1 block font-mono text-[22px] font-medium leading-none text-tinta">
                  {i.v}
                </span>
                <span className="mt-1.5 block text-[11px] leading-relaxed text-tinta3">{i.n}</span>
              </dd>
            </div>
          ))}
        </dl>
        {ficha.valor?.divergencia && (
          <p className="mt-3 rounded-cartao border border-aviso-linha bg-aviso-bg px-4 py-2.5 text-[12.5px] text-aviso">
            {ficha.valor.divergencia}
          </p>
        )}
      </section>

      {/* --------------------------------------------------------- a assinatura */}
      <section className="mt-10">
        <h2 className="rotulo">A assinatura</h2>

        {viva ? (
          <div className="mt-3 rounded-cartao border border-linha bg-folha px-5 py-4">
            <p className="text-[14px] text-tinta">
              <b className="font-medium">{viva.plano}</b> · {rotuloEstado(viva.estado as EstadoAssinatura)} ·{" "}
              {reais(viva.valor_centavos)} {viva.ciclo} · aberta por {viva.origem}
            </p>
            <p className="mt-1 text-[12px] text-tinta3">
              desde {viva.inicio.split("-").reverse().join("/")}
              {viva.proximo_vencimento &&
                ` · próximo vencimento em ${viva.proximo_vencimento.split("-").reverse().join("/")}`}
            </p>

            <div className="mt-4 flex flex-col gap-3 border-t border-linha pt-4">
              {acoes.includes("emitir_fatura") && <EmitirFatura assinatura={viva.id} />}
              {acoes.includes("mudar_plano") && <MudarPlano conta={c.id} planos={planos} />}
              {acoes.includes("cancelar") && <CancelarAssinatura assinatura={viva.id} />}
            </div>
          </div>
        ) : (
          <div className="mt-3 rounded-cartao border border-linha bg-folha px-5 py-4">
            <p className="text-[13.5px] text-tinta2">
              Sem assinatura viva. No Grátis a conta tem tudo o que é registro — o que falta é
              o que economiza tempo.
            </p>
            <div className="mt-3">
              <AbrirAssinatura conta={c.id} planos={planos} />
            </div>
          </div>
        )}

        {/* O histórico é o que faz a mudança de plano não apagar março. */}
        {ficha.assinaturas.length > (viva ? 1 : 0) && (
          <ul className="mt-4 flex flex-col gap-1.5">
            {ficha.assinaturas
              .filter((a) => a.id !== viva?.id)
              .map((a) => (
                <li key={a.id} className="text-[12.5px] text-tinta3">
                  {a.plano} · {reais(a.valor_centavos)} · {a.inicio.split("-").reverse().join("/")}
                  {a.cancelada_em && ` até ${a.cancelada_em.slice(0, 10).split("-").reverse().join("/")}`}
                  {a.motivo_cancelamento && (
                    <span className="text-tinta2"> — {a.motivo_cancelamento}</span>
                  )}
                </li>
              ))}
          </ul>
        )}
      </section>

      {/* ------------------------------------------------------------ as faturas */}
      <section className="mt-10">
        <h2 className="rotulo">As faturas</h2>
        {ficha.faturas.length === 0 ? (
          <p className="mt-3 text-[13px] text-tinta3">Nenhuma emitida ainda.</p>
        ) : (
          <div className="mt-3 overflow-hidden rounded-cartao border border-linha bg-folha">
            <table className="w-full text-[12.5px]">
              <thead>
                <tr className="border-b border-linha text-left text-tinta3">
                  <th className="px-4 py-2 font-medium">competência</th>
                  <th className="px-4 py-2 font-medium">vence</th>
                  <th className="px-4 py-2 text-right font-medium">valor</th>
                  <th className="px-4 py-2 font-medium">estado</th>
                  <th className="px-4 py-2 font-medium"> </th>
                </tr>
              </thead>
              <tbody>
                {ficha.faturas.map((f) => (
                  <tr key={f.id} className="border-b border-linha last:border-0">
                    <td className="px-4 py-2.5 font-mono">{f.competencia.slice(0, 7)}</td>
                    <td className="px-4 py-2.5 text-tinta2">
                      {f.vencimento.split("-").reverse().join("/")}
                    </td>
                    <td className="tabular px-4 py-2.5 text-right font-mono">
                      {reais(f.valor_centavos)}
                    </td>
                    <td className="px-4 py-2.5">
                      <span
                        className={
                          f.estado === "paga"
                            ? "text-cheia"
                            : f.estado === "vencida"
                              ? "text-vaga"
                              : "text-tinta2"
                        }
                      >
                        {rotuloFatura(f.estado as EstadoFatura)}
                      </span>
                    </td>
                    <td className="px-4 py-2.5">
                      <AcoesDaFatura fatura={f.id} estado={f.estado} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      {/* ------------------------------------------------------- os sinais de vida */}
      <section className="mt-10">
        <h2 className="rotulo">Se a conta está viva</h2>
        <p className="mt-2 max-w-[62ch] text-[12.5px] leading-relaxed text-tinta3">
          Contagem, e só. Nome de paciente, horário e conteúdo de sessão não passam por esta
          tela — nem por acidente, nem por curiosidade minha num dia de suporte.
        </p>
        <dl className="mt-3 grid gap-px overflow-hidden rounded-cartao border border-linha bg-linha sm:grid-cols-4">
          {[
            { r: "pacientes ativos", v: ficha.uso.pacientes_ativos },
            { r: "sessões no mês", v: ficha.uso.sessoes_no_mes },
            { r: "mensagens no mês", v: ficha.uso.mensagens_no_mes },
            { r: "pessoas na conta", v: ficha.uso.usuarios },
          ].map((i) => (
            <div key={i.r} className="bg-folha px-4 py-3.5">
              <dt className="rotulo">{i.r}</dt>
              <dd className="tabular mt-1 font-mono text-[20px] font-medium leading-none text-tinta">
                {i.v}
              </dd>
            </div>
          ))}
        </dl>
      </section>

      <section className="mt-10 border-t border-linha pt-6">
        <MarcaDeTeste conta={c.id} marcada={c.is_teste} />
        <p className="mt-2 max-w-[62ch] text-[11.5px] leading-relaxed text-tinta3">
          Conta de teste sai das métricas e <b className="font-medium">continua na lista</b> —
          senão eu marcaria por engano e nunca mais desmarcaria pela tela.
        </p>
      </section>
    </div>
  );
}
