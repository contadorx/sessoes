import Link from "next/link";
import {
  rotuloConfirmacao,
  explicaConfirmacao,
  acaoDaConfirmacao,
  apareceNoDia,
  lerResposta,
  fraseDaResposta,
  type RespostaBruta,
} from "@/lib/confirmacao";

/**
 * A faixa da confirmação, no dia.
 *
 * **Ela só existe quando alguém foi perguntado.** Numa conta que não pede
 * confirmação — que é o padrão — esta seção não aparece: uma faixa vazia
 * dizendo "ninguém confirmou" seria acusar de silêncio quem nunca foi
 * perguntado.
 *
 * O QUE ELA MOSTRA, E O QUE ELA SE RECUSA A OFERECER
 *
 * Quem **avisou que não vem** ganha um caminho: o painel da sessão, onde o
 * cancelamento aparece com o valor da política à vista. É o que ela já faz hoje
 * no WhatsApp, e é decisão dela — o botão não cancela daqui, ele leva para onde
 * a consequência está escrita.
 *
 * Quem **não respondeu** não ganha botão nenhum. Silêncio é sinal fraco: quem
 * não respondeu pode estar sem bateria, e a prática de campo é que ela nunca
 * liberou horário por falta de resposta. Oferecer a ação aqui seria ensinar um
 * comportamento que ninguém tem, sobre uma informação que não sustenta a
 * decisão.
 */
export function FaixaDeConfirmacoes({
  sessoes,
}: {
  sessoes: {
    id: string;
    inicio: string;
    eixo_confirmacao: string;
    pacientes: { nome: string } | null;
  }[];
}) {
  const comPergunta = sessoes.filter((s) => apareceNoDia(s.eixo_confirmacao));
  if (comPergunta.length === 0) return null;

  const recusadas = comPergunta.filter((s) => s.eixo_confirmacao === "recusada");
  const silenciosas = comPergunta.filter((s) => s.eixo_confirmacao === "silenciosa");
  const confirmadas = comPergunta.filter((s) => s.eixo_confirmacao === "confirmada");
  const pendentes = comPergunta.filter((s) => s.eixo_confirmacao === "pendente");

  const hora = (iso: string) =>
    new Date(iso).toLocaleTimeString("pt-BR", {
      hour: "2-digit",
      minute: "2-digit",
      timeZone: "America/Sao_Paulo",
    });

  return (
    <section className="rounded-cartao border border-linha bg-folha2 px-5 py-4">
      <h2 className="rotulo">A confirmação de hoje</h2>

      <p className="mt-2 text-[12.5px] leading-relaxed text-tinta2">
        {confirmadas.length > 0 && `${confirmadas.length} confirmou. `}
        {pendentes.length > 0 && `${pendentes.length} ainda não respondeu. `}
        {silenciosas.length > 0 && `${silenciosas.length} não respondeu até agora. `}
        {recusadas.length > 0 && `${recusadas.length} avisou que não vem.`}
      </p>

      {(recusadas.length > 0 || silenciosas.length > 0) && (
        <ul className="mt-3 flex flex-col gap-2.5">
          {[...recusadas, ...silenciosas].map((s) => {
            const acao = acaoDaConfirmacao(s.eixo_confirmacao);
            return (
              <li key={s.id} className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                <span className="font-mono text-[12px] tabular-nums text-tinta3">
                  {hora(s.inicio)}
                </span>
                <span className="text-[13px] text-tinta">{s.pacientes?.nome ?? "—"}</span>
                <span
                  className={`text-[11.5px] ${
                    s.eixo_confirmacao === "recusada" ? "text-vaga" : "text-tinta3"
                  }`}
                >
                  {rotuloConfirmacao(s.eixo_confirmacao)}
                </span>

                {/* Só a recusa tem caminho, e ele leva para onde o custo está
                    escrito. O silêncio fica sem botão — de propósito. */}
                {acao && (
                  <Link
                    href={`/agenda?sessao=${s.id}`}
                    className="toque ml-auto text-[11.5px] text-tinta3 underline decoration-linha2 underline-offset-4 hover:text-vaga"
                  >
                    {acao.rotulo}
                  </Link>
                )}
              </li>
            );
          })}
        </ul>
      )}

      {silenciosas.length > 0 && (
        <p className="mt-3 max-w-[62ch] text-[11.5px] leading-relaxed text-tinta3">
          {explicaConfirmacao("silenciosa")} O horário continua reservado, e o
          sistema não vai fazer nada com ele.
        </p>
      )}
    </section>
  );
}

/** O selo da confirmação, dentro do painel de uma sessão. */
export function SeloDaConfirmacao({ eixo }: { eixo: string }) {
  if (!apareceNoDia(eixo)) return null;

  const cor =
    eixo === "confirmada"
      ? "border-cheia-linha bg-cheia-bg text-cheia"
      : eixo === "recusada"
        ? "border-vaga-linha bg-vaga-bg text-vaga"
        : "border-linha2 bg-folha2 text-tinta2";

  return (
    <div className="mt-3">
      <span className={`inline-block rounded-full border px-3 py-1 text-[11.5px] font-medium ${cor}`}>
        {rotuloConfirmacao(eixo)}
      </span>
      <p className="mt-1.5 max-w-[58ch] text-[11.5px] leading-relaxed text-tinta3">
        {explicaConfirmacao(eixo)}
      </p>
    </div>
  );
}

/**
 * Os dois números que decidem se este bloco se paga.
 *
 * Estão na tela desde o primeiro dia, e não numa aba de relatórios que ninguém
 * abre. O critério de pronto do P3 diz que **se a taxa for baixa, o bloco não
 * se paga, e isso aparece no primeiro mês** — e uma feature que não carrega
 * consigo o instrumento que a mediria é uma feature que ninguém desliga depois.
 *
 * Some quando ninguém foi perguntado: numa conta que não pede confirmação, este
 * bloco seria um zero sobre coisa nenhuma.
 */
export function NumerosDaConfirmacao({ bruta }: { bruta: RespostaBruta | null }) {
  if (!bruta || bruta.pedidas === 0) return null;
  const r = lerResposta(bruta);

  return (
    <section className="rounded-cartao border border-linha bg-folha px-5 py-4">
      <h2 className="rotulo">A confirmação, nos últimos 30 dias</h2>

      <dl className="mt-3 flex flex-wrap gap-x-8 gap-y-3">
        <div>
          <dt className="text-[11.5px] text-tinta3">responderam</dt>
          <dd className="font-mono text-[18px] tabular-nums text-tinta">
            {r.taxa}%
          </dd>
        </div>
        <div>
          <dt className="text-[11.5px] text-tinta3">antecedência média</dt>
          <dd className="font-mono text-[18px] tabular-nums text-tinta2">
            {r.antecedenciaH === null ? "—" : `${String(r.antecedenciaH).replace(".", ",")}h`}
          </dd>
        </div>
        <div>
          <dt className="text-[11.5px] text-tinta3">não responderam</dt>
          <dd className="font-mono text-[18px] tabular-nums text-tinta2">{r.silenciosas}</dd>
        </div>
      </dl>

      <p className="mt-3 max-w-[62ch] text-[12.5px] leading-relaxed text-tinta2">
        {fraseDaResposta(r)}
      </p>

      <p className="mt-2 max-w-[62ch] text-[11.5px] leading-relaxed text-tinta3">
        A confirmação liga no combinado de cada paciente, e desliga do mesmo
        jeito. Ela custa uma mensagem por sessão — e estes dois números existem
        para você conseguir decidir se vale.
      </p>
    </section>
  );
}
