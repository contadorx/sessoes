"use client";

import Link from "next/link";
import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import { salvarContador, fecharMes, type Resultado } from "@/app/(app)/fechamento/contador/acoes";
import {
  nomeDoMes,
  resumoDoRetrato,
  fraseDoFiscal,
  rotuloEstado,
  type PastaLinha,
} from "@/lib/contador";
import { formatar, paraCentavos } from "@/lib/dinheiro";

const INICIAL: Resultado = { estado: "inicial" };

function Botao({ rotulo, destaque }: { rotulo: string; destaque?: boolean }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className={
        destaque
          ? "rounded-full bg-cheia px-4 py-1.5 text-[12.5px] font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-45"
          : "rounded-full border border-linha2 px-4 py-1.5 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2 disabled:opacity-45"
      }
    >
      {pending ? "…" : rotulo}
    </button>
  );
}

function Recado({ r }: { r: Resultado }) {
  if (r.estado === "ok") return <p className="mt-2 text-[12.5px] leading-relaxed text-cheia">{r.mensagem}</p>;
  if (r.estado === "erro")
    return (
      <ul className="mt-2 space-y-1">
        {r.erros.map((e, i) => (
          <li key={i} className="text-[12.5px] leading-relaxed text-vaga">
            {e}
          </li>
        ))}
      </ul>
    );
  return null;
}

const CAMPO =
  "w-full rounded-cartao border border-linha2 bg-folha px-3 py-2 text-[13px] text-tinta focus:border-tinta3 focus:outline-none";

export function PainelContador({
  email,
  nome,
  dia,
  ativa,
  pastas,
  mesesFechaveis,
  envioPorEmail,
}: {
  email: string | null;
  nome: string | null;
  dia: number;
  ativa: boolean;
  pastas: PastaLinha[];
  mesesFechaveis: string[];
  /**
   * O adaptador de e-mail com anexo existe? (B25 — falta provedor.) Esta tela
   * coleta "e-mail do contador" e "dia do envio", e dizia *"marque o envio
   * automático e o primeiro sai sozinho"*. Sem adaptador nada sai: o que
   * acontece no dia marcado é a pasta **ficar pronta**, e ela mesma manda.
   */
  envioPorEmail: boolean;
}) {
  const [rSalvar, salvar] = useActionState(salvarContador, INICIAL);
  const [rFechar, fechar] = useActionState(fecharMes, INICIAL);
  const [aberta, setAberta] = useState<string | null>(pastas[0]?.id ?? null);

  return (
    <>
      {/* ------------------------------------------------------ quem recebe */}
      <section className="mt-6">
        <h2 className="rotulo">Para quem vai</h2>
        <form action={salvar} className="mt-3 rounded-cartao border border-linha bg-folha2 px-5 py-4">
          <div className="grid gap-3 sm:grid-cols-3">
            <div className="sm:col-span-2">
              <label htmlFor="contador_email" className="text-[12px] font-medium text-tinta2">
                E-mail do contador
              </label>
              <input
                id="contador_email"
                name="contador_email"
                type="email"
                defaultValue={email ?? ""}
                placeholder="contabilidade@exemplo.com.br"
                className={`mt-1 ${CAMPO}`}
              />
            </div>
            <div>
              <label htmlFor="pasta_dia" className="text-[12px] font-medium text-tinta2">
                {envioPorEmail ? "Dia do envio" : "Dia em que a pasta fica pronta"}
              </label>
              <input
                id="pasta_dia"
                name="pasta_dia"
                type="number"
                onWheel={(e) => e.currentTarget.blur()}
                min={1}
                max={28}
                defaultValue={dia}
                className={`mt-1 ${CAMPO}`}
              />
            </div>
          </div>

          <div className="mt-3">
            <label htmlFor="contador_nome" className="text-[12px] font-medium text-tinta2">
              Nome do escritório (opcional)
            </label>
            <input
              id="contador_nome"
              name="contador_nome"
              defaultValue={nome ?? ""}
              maxLength={120}
              className={`mt-1 ${CAMPO}`}
            />
          </div>

          <label className="mt-4 flex items-start gap-2 text-[13px] leading-relaxed text-tinta2">
            <input
              type="checkbox"
              name="pasta_ativa"
              value="1"
              defaultChecked={ativa}
              className="mt-0.5"
            />
            <span>
              Fechar e enviar sozinho, todo mês.{" "}
              <span className="text-tinta3">
                Nasce desligado de propósito: mandar dado para fora é decisão sua, não padrão
                nosso.
              </span>
            </span>
          </label>

          <p className="mt-3 text-[11.5px] leading-relaxed text-tinta3">
            O dia vai até 28 porque fevereiro existe — um envio marcado para o dia 30 nunca
            aconteceria em fevereiro, e ninguém perceberia até o contador cobrar.
          </p>

          <div className="mt-3">
            <Botao rotulo="Salvar" destaque />
          </div>
          <Recado r={rSalvar} />
        </form>
      </section>

      {/* --------------------------------------------------- fechar à mão */}
      {mesesFechaveis.length > 0 && (
        <section className="mt-8">
          <h2 className="rotulo">Fechar um mês agora</h2>
          <form action={fechar} className="mt-3 flex flex-wrap items-end gap-3">
            <div>
              <label htmlFor="competencia" className="text-[12px] font-medium text-tinta2">
                Mês
              </label>
              <select id="competencia" name="competencia" className={`mt-1 ${CAMPO} w-56`}>
                {mesesFechaveis.map((m) => (
                  <option key={m} value={m}>
                    {nomeDoMes(m)}
                  </option>
                ))}
              </select>
            </div>
            <Botao rotulo="Fechar o mês" />
          </form>
          <p className="mt-2 text-[11.5px] leading-relaxed text-tinta3">
            O mês corrente não aparece na lista: fechar um mês que ainda está acontecendo é
            mandar ao contador um número que vai mudar.
          </p>
          <Recado r={rFechar} />
        </section>
      )}

      {/* ------------------------------------------------------- as pastas */}
      <section className="mt-10">
        <h2 className="rotulo">Os fechamentos</h2>

        {pastas.length === 0 ? (
          <p className="mt-2 rounded-cartao border border-linha bg-folha2 px-5 py-4 text-[13px] leading-relaxed text-tinta2">
            {envioPorEmail
              ? "Nenhum mês fechado ainda. Feche um acima, ou marque o envio automático e o primeiro sai sozinho."
              : "Nenhum mês fechado ainda. Feche um acima, ou marque o fechamento automático: no dia marcado a pasta fica pronta aqui, e você manda para o contador."}
          </p>
        ) : (
          <ul className="mt-3 space-y-3">
            {pastas.map((p) => {
              const fiscal = fraseDoFiscal(p.retrato);
              const abertaAgora = aberta === p.id;

              return (
                <li key={p.id} className="rounded-cartao border border-linha bg-folha px-5 py-4">
                  <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                    <span className="font-serif text-[17px] text-tinta">
                      {nomeDoMes(p.retrato.competencia)}
                    </span>
                    {p.versao > 1 && (
                      <span className="rounded-full border border-linha bg-folha2 px-2 py-0.5 text-[10.5px] font-semibold uppercase tracking-wider text-tinta3">
                        v{p.versao}
                      </span>
                    )}
                    <span className="font-mono text-[13px] tabular-nums text-tinta2">
                      {formatar(paraCentavos(p.retrato.receitas.total))} entrou ·{" "}
                      {formatar(paraCentavos(p.retrato.despesas.total))} saiu
                    </span>
                    <span className="ml-auto text-[11.5px] text-tinta3">
                      {rotuloEstado(p, Boolean(email))}
                    </span>
                  </div>

                  {fiscal && <p className="mt-2 text-[12.5px] text-tinta2">{fiscal}</p>}

                  <div className="mt-3 flex flex-wrap items-center gap-3">
                    <a
                      href={`/fechamento/contador/${p.id}/csv`}
                      className="rounded-full border border-linha2 px-4 py-1.5 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2"
                    >
                      Baixar o CSV
                    </a>
                    <button
                      type="button"
                      onClick={() => setAberta(abertaAgora ? null : p.id)}
                      className="text-[12.5px] text-tinta3 hover:text-tinta2"
                    >
                      {abertaAgora ? "esconder o resumo" : "ver o resumo"}
                    </button>
                  </div>

                  {abertaAgora && (
                    <pre className="mt-3 overflow-x-auto whitespace-pre-wrap rounded-cartao border border-linha bg-folha2 px-4 py-3 font-mono text-[11.5px] leading-relaxed text-tinta2">
                      {resumoDoRetrato(p.retrato)}
                    </pre>
                  )}
                </li>
              );
            })}
          </ul>
        )}
      </section>

      {!email && pastas.length > 0 && (
        <p className="mt-4 rounded-cartao border border-aviso-linha bg-aviso-bg px-5 py-3 text-[13px] leading-relaxed text-aviso">
          Sem e-mail configurado eu não mando nada — o arquivo fica aqui e você encaminha. É a
          escolha segura enquanto você decide para quem vai.
        </p>
      )}

      <p className="mt-6 text-[12.5px] text-tinta3">
        Os números vêm de{" "}
        <Link href="/recebimentos/movimentacoes" className="underline underline-offset-2 hover:text-vaga">
          Financeiro
        </Link>{" "}
        e de{" "}
        <Link href="/fechamento/receita-saude" className="underline underline-offset-2 hover:text-vaga">
          Receita Saúde
        </Link>
        . Nada é digitado duas vezes.
      </p>
    </>
  );
}
