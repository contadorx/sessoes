import Link from "next/link";
import { notFound } from "next/navigation";
import { sessaoAtual } from "@/lib/conta";
import { lerRetencao, lerAvisos } from "../dados";
import {
  reais,
  rotuloCausa,
  fraseDaRetencao,
  causaQueMaisPesa,
  proximoPassoDaRegua,
  oQueASuspensaoNaoTira,
  CAUSAS,
} from "@/lib/negocio";
import { AvisoDaRegua } from "@/components/app/NegocioAcoes";

export const metadata = { title: "Retenção" };

const br = (iso: string | null) =>
  iso ? iso.slice(0, 10).split("-").reverse().join("/") : "—";

/**
 * A retenção — o que a OP5 deixou escrito como pendência.
 *
 * *"Hoje o churn é um número sozinho no painel."* Um número sozinho não muda
 * decisão nenhuma: "cancelou porque parou de atender" e "cancelou porque achou
 * caro" mandam construir coisas opostas, e as duas somam 1 no mesmo lugar.
 *
 * **Esta tela mostra inteiro, e não porcentagem.** Com uma dúzia de contas,
 * "33% saíram por preço" são duas pessoas — um número que parece saber mais do
 * que sabe. É a mesma disciplina do LTV que devolve nulo com churn zero em vez
 * de devolver infinito.
 *
 * E a lista traz **a frase junto com a categoria**, porque é a frase que diz o
 * que construir. A categoria é o que dá para contar.
 */
export default async function Retencao() {
  const sessao = await sessaoAtual();
  if (!sessao.operador) notFound();

  const [r, avisos] = await Promise.all([lerRetencao(), lerAvisos()]);
  if (!r) notFound();

  const pesa = causaQueMaisPesa(r);

  return (
    <div className="mx-auto max-w-3xl">
      <Link href="/negocio" className="text-[12.5px] text-tinta3 hover:text-vaga">
        ← o negócio
      </Link>

      <h1 className="mt-2 font-serif text-[26px] leading-tight tracking-[-0.015em]">
        Quem saiu, e por quê
      </h1>
      <p className="mt-3 max-w-[64ch] text-[13px] leading-relaxed text-tinta2">
        {fraseDaRetencao(r)}
      </p>
      {pesa && (
        <p className="mt-1 max-w-[64ch] text-[13px] leading-relaxed text-tinta2">
          A causa que mais aparece é <b className="font-medium">{rotuloCausa(pesa)}</b>.
        </p>
      )}

      {/* ------------------------------------------------------ a régua em curso */}
      <section className="mt-9">
        <h2 className="rotulo">A régua correndo</h2>

        {avisos.length === 0 ? (
          <p className="mt-2 text-[13px] leading-relaxed text-tinta3">
            Nenhum aviso na fila. Nenhuma fatura está vencida — ou as que estão
            são de conta de teste ou de cortesia, que a régua não alcança.
          </p>
        ) : (
          <>
            <p className="mt-2 max-w-[64ch] text-[12.5px] leading-relaxed text-tinta3">
              Estes textos ainda não saíram. Não há provedor de e-mail ligado, e
              por isso quem manda sou eu — o botão registra que saiu, e não
              finge que o sistema enviou.
            </p>
            <ul className="mt-3 grid gap-px overflow-hidden rounded-cartao border border-linha bg-linha">
              {avisos.map((a) => (
                <li key={a.id} className="bg-folha px-5 py-4">
                  <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                    <Link
                      href={`/negocio/${a.conta_id}`}
                      className="text-[14px] font-medium text-tinta hover:text-vaga"
                    >
                      {a.conta}
                    </Link>
                    <span className="rounded-full bg-aviso-bg px-2 py-0.5 text-[11px] font-medium text-aviso">
                      degrau {a.degrau}
                    </span>
                    <span className="ml-auto font-mono text-[11.5px] text-tinta3">
                      venceu em {br(a.vencimento)} · {a.dias}{" "}
                      {a.dias === 1 ? "dia" : "dias"}
                    </span>
                    <span className="w-full text-[11.5px] text-tinta3">
                      {proximoPassoDaRegua(a.dias)}
                    </span>
                  </div>
                  <div className="mt-2">
                    <AvisoDaRegua aviso={a.id} assunto={a.assunto} corpo={a.corpo} />
                  </div>
                </li>
              ))}
            </ul>
          </>
        )}

        <p className="mt-4 max-w-[64ch] rounded-cartao border border-linha bg-folha2 px-4 py-3 text-[11.5px] leading-relaxed text-tinta2">
          {oQueASuspensaoNaoTira()}
        </p>
      </section>

      {/* ---------------------------------------------------------- por causa */}
      <section className="mt-10">
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <h2 className="rotulo">Por causa · desde {br(r.desde)}</h2>
          <span className="tabular font-mono text-[13px] text-tinta2">
            {reais(r.mrr_perdido_centavos)} de MRR
          </span>
        </div>

        {r.por_causa.length === 0 ? (
          <p className="mt-2 text-[13px] text-tinta3">Nada a contar ainda.</p>
        ) : (
          <ul className="mt-3 grid gap-px overflow-hidden rounded-cartao border border-linha bg-linha">
            {r.por_causa.map((c) => (
              <li key={c.causa} className="bg-folha px-5 py-3">
                <div className="flex flex-wrap items-baseline gap-3">
                  <span className="text-[13.5px] text-tinta">{rotuloCausa(c.causa)}</span>
                  <span className="tabular font-mono text-[13px] font-medium text-tinta">
                    {c.quantas}
                  </span>
                  <span className="tabular ml-auto font-mono text-[12.5px] text-tinta2">
                    {reais(c.mrr_perdido_centavos)}
                  </span>
                </div>
                <p className="mt-1 max-w-[62ch] text-[11.5px] leading-relaxed text-tinta3">
                  {CAUSAS.find((x) => x.valor === c.causa)?.explica}
                </p>
              </li>
            ))}
          </ul>
        )}

        <p className="mt-3 max-w-[64ch] text-[11.5px] leading-relaxed text-tinta3">
          São contagens, não porcentagens. Com esta base, &ldquo;33% saíram por
          preço&rdquo; são duas pessoas — e um número que parece saber mais do
          que sabe é pior que nenhum. A porcentagem entra quando a base
          sustentar uma.
        </p>
      </section>

      {/* -------------------------------------------------------------- a lista */}
      <section className="mt-10">
        <h2 className="rotulo">Uma a uma</h2>

        {r.lista.length === 0 ? (
          <p className="mt-2 text-[13px] text-tinta3">Ninguém saiu no período.</p>
        ) : (
          <ul className="mt-3 flex flex-col gap-3">
            {r.lista.map((s) => (
              <li
                key={`${s.conta_id}-${s.cancelada_em}`}
                className="rounded-cartao border border-linha bg-folha px-5 py-4"
              >
                <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                  <Link
                    href={`/negocio/${s.conta_id}`}
                    className="text-[14px] font-medium text-tinta hover:text-vaga"
                  >
                    {s.conta}
                  </Link>
                  <span className="text-[12px] text-tinta3">
                    {s.plano} · {reais(s.valor_centavos)}
                  </span>
                  <span className="ml-auto text-[12px] text-tinta2">
                    {rotuloCausa(s.causa)}
                  </span>
                </div>

                {/* A frase, com destaque de citação: é dela, e não minha. */}
                {s.motivo && (
                  <p className="mt-2 border-l-2 border-linha2 pl-3 text-[13px] leading-relaxed text-tinta">
                    {s.motivo}
                  </p>
                )}

                <p className="mt-2 font-mono text-[11px] text-tinta3">
                  {br(s.inicio)} → {br(s.cancelada_em)} · {s.dias_de_vida}{" "}
                  {s.dias_de_vida === 1 ? "dia" : "dias"}
                </p>
              </li>
            ))}
          </ul>
        )}
      </section>

      <p className="mt-8 max-w-[64ch] text-[11.5px] leading-relaxed text-tinta3">
        Troca de plano não aparece aqui, e é a correção que a 0052 trouxe:{" "}
        <code>mudar_plano</code> cancela a assinatura antiga para preservar a
        faixa anterior no histórico, e o churn contava essa linha — toda
        promoção registrava uma perda.
      </p>
    </div>
  );
}
