"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import type { DecisaoPendente } from "@/app/(app)/agenda/dados";
import { decidirCobranca, type Resultado } from "@/app/(app)/agenda/acoes";
import {
  lerHistorico,
  fraseDoHistorico,
  fraseDaEspera,
  fraseDaCaixa,
  rotuloMotivo,
} from "@/lib/politica";
import { rotuloPolitica } from "@/lib/enquadre";
import { formatar, paraCentavos, deCentavos } from "@/lib/dinheiro";

const INICIAL: Resultado = { estado: "inicial" };

const QUANDO = new Intl.DateTimeFormat("pt-BR", {
  timeZone: "America/Sao_Paulo",
  weekday: "long",
  day: "numeric",
  month: "long",
  hour: "2-digit",
  minute: "2-digit",
});

/**
 * A caixa de decisões (P4).
 *
 * O DESENHO É A DOUTRINA, E VALE ESCREVER
 *
 * **1 · "Não cobrar" não é o botão pequeno.** Os dois têm o mesmo tamanho, a
 * mesma altura e a mesma tipografia; só a cor muda, e nem isso hierarquiza. A
 * B11 tinha uma régua automática com um freio, e a regra de então era que o
 * freio tem de ser mais fácil que o acelerador. Agora não há acelerador — e
 * fazer "Cobrar" parecer o caminho natural seria reintroduzir a régua no
 * desenho depois de tê-la tirado do código.
 *
 * **2 · Nada aqui tem prazo.** Não há contagem regressiva, não há "vence em",
 * não há vermelho crescente com os dias. A proposta não caduca (0058), e uma
 * tela que aparenta urgência produz a decisão apressada que o build existe para
 * evitar. A idade da pergunta aparece porque é informação; ela não aparece como
 * cobrança.
 *
 * **3 · O histórico vem junto, e não conclui nada.** Ele conta ausências,
 * perdões e pagamentos. Não diz "é a quinta vez" com exclamação, não classifica
 * ninguém e não sugere. A fronteira 3 do doc 11 é exatamente aqui: o software
 * não tem como saber se a falta foi trânsito, dia ruim, ou o próprio motivo que
 * traz a pessoa ao consultório — e essa terceira possibilidade é a razão de o
 * P4 existir.
 */
export function CaixaDeDecisoes({ decisoes }: { decisoes: DecisaoPendente[] }) {
  if (decisoes.length === 0) return null;

  return (
    <section className="rounded-cartao border border-vaga-linha bg-folha2 px-5 py-4">
      <h2 className="rotulo">A decidir</h2>

      <p className="mt-2 max-w-[68ch] text-[12.5px] leading-relaxed text-tinta2">
        {fraseDaCaixa(decisoes.length)}
      </p>

      <ul className="mt-4 flex flex-col gap-4">
        {decisoes.map((d) => (
          <li key={d.id}>
            <UmaDecisao d={d} />
          </li>
        ))}
      </ul>
    </section>
  );
}

function Botao({ rotulo, destaque }: { rotulo: string; destaque: "cobrar" | "perdoar" }) {
  const { pending } = useFormStatus();

  // Mesma altura, mesmo peso, mesmo tamanho de fonte. A cor distingue sem
  // hierarquizar: nenhuma das duas é "a certa".
  const cor =
    destaque === "cobrar"
      ? "border-vaga-linha text-vaga hover:bg-vaga-bg"
      : "border-linha2 text-tinta2 hover:bg-folha";

  return (
    <button
      type="submit"
      disabled={pending}
      className={`rounded-full border px-4 py-2 text-[12.5px] font-medium transition-colors disabled:opacity-45 ${cor}`}
    >
      {pending ? "…" : rotulo}
    </button>
  );
}

function UmaDecisao({ d }: { d: DecisaoPendente }) {
  const [resultado, decidir] = useActionState(decidirCobranca, INICIAL);
  const [ajustando, setAjustando] = useState(false);

  const sugerido = paraCentavos(d.valor_sugerido);
  const daSessao = d.valor_da_sessao ? paraCentavos(d.valor_da_sessao) : null;
  const historico = lerHistorico(d.historico);

  return (
    <div className="rounded-cartao border border-linha bg-folha px-4 py-3.5">
      <div className="flex flex-wrap items-baseline gap-x-2 gap-y-1">
        <b className="text-[13.5px] font-medium text-tinta">{d.paciente}</b>
        <span className="text-[12.5px] text-tinta2">{rotuloMotivo(d.motivo)}</span>
        <span className="text-[11.5px] text-tinta3">· {QUANDO.format(new Date(d.inicio))}</span>
        <span className="ml-auto text-[11.5px] text-tinta3">{fraseDaEspera(d.dias_esperando)}</span>
      </div>

      {/* Por que este valor. A pergunta "por que R$ 100?" tem de ter resposta
          **na tela da decisão**, não depois dela — é por isso que o retrato da
          política é congelado na proposta e não lido do combinado de hoje. */}
      <p className="mt-2 text-[12.5px] leading-relaxed text-tinta2">
        Pelo combinado desta sessão —{" "}
        {d.politica_horas !== null && d.politica_percentual !== null
          ? rotuloPolitica({ horas: d.politica_horas, percentual: d.politica_percentual })
          : "a política congelada na sessão"}{" "}
        — daria{" "}
        <b className="font-semibold text-vaga">{formatar(sugerido)}</b>
        {daSessao !== null && <span className="text-tinta3"> (a hora era {formatar(daSessao)})</span>}.
      </p>

      <p className="mt-1.5 max-w-[64ch] text-[11.5px] leading-relaxed text-tinta3">
        {fraseDoHistorico(historico)}
      </p>

      {resultado.estado === "ok" ? (
        <p className="mt-3 rounded-cartao border border-linha bg-folha2 px-3 py-2 text-[12.5px] leading-relaxed text-tinta2">
          {resultado.mensagem}
        </p>
      ) : (
        <>
          <div className="mt-3 flex flex-wrap items-center gap-2">
            <form action={decidir}>
              <input type="hidden" name="proposta_id" value={d.id} />
              <input type="hidden" name="decisao" value="cobrar" />
              <Botao rotulo={`Cobrar ${formatar(sugerido)}`} destaque="cobrar" />
            </form>

            <form action={decidir}>
              <input type="hidden" name="proposta_id" value={d.id} />
              <input type="hidden" name="decisao" value="perdoar" />
              <Botao rotulo="Não cobrar" destaque="perdoar" />
            </form>

            <button
              type="button"
              onClick={() => setAjustando((x) => !x)}
              className="text-[12px] text-tinta3 underline decoration-linha2 underline-offset-4 hover:text-tinta2"
            >
              {ajustando ? "deixa como estava" : "cobrar outro valor"}
            </button>
          </div>

          {ajustando && (
            <form action={decidir} className="mt-3 rounded-cartao border border-linha bg-folha2 px-3 py-3">
              <input type="hidden" name="proposta_id" value={d.id} />
              <input type="hidden" name="decisao" value="cobrar" />
              {daSessao !== null && (
                <input type="hidden" name="valor_da_sessao" value={deCentavos(daSessao)} />
              )}

              <label htmlFor={`valor-${d.id}`} className="text-[11.5px] text-tinta3">
                cobrar quanto
              </label>
              <div className="mt-1 flex flex-wrap items-center gap-2">
                <input
                  id={`valor-${d.id}`}
                  name="valor"
                  inputMode="decimal"
                  defaultValue={deCentavos(sugerido)}
                  className="w-28 rounded-cartao border border-linha2 bg-folha px-2.5 py-1.5 font-mono text-[13px] tabular-nums text-tinta"
                />
                <Botao rotulo="Cobrar este valor" destaque="cobrar" />
              </div>

              <label htmlFor={`motivo-${d.id}`} className="mt-3 block text-[11.5px] text-tinta3">
                por quê (só para você)
              </label>
              <input
                id={`motivo-${d.id}`}
                name="motivo"
                maxLength={200}
                placeholder="ex.: avisou tarde, mas avisou"
                className="mt-1 w-full rounded-cartao border border-linha2 bg-folha px-2.5 py-1.5 text-[12.5px] text-tinta placeholder:text-tinta3"
              />

              {/* O teto do ajuste, dito antes de ela tentar. Multa maior que o
                  serviço não é política de faltas — e nenhum combinado assinado
                  previu isso. */}
              {daSessao !== null && (
                <p className="mt-2 text-[11px] leading-relaxed text-tinta3">
                  Você pode cobrar menos. Mais que {formatar(daSessao)} não — seria
                  cobrar acima do que a hora valia.
                </p>
              )}
            </form>
          )}

          {resultado.estado === "erro" && (
            <p className="mt-2 text-[12px] leading-relaxed text-vaga">{resultado.erros[0]}</p>
          )}
        </>
      )}
    </div>
  );
}
