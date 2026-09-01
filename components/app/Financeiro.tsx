"use client";

import Link from "next/link";
import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import {
  registrarRecebimento,
  lancarDespesa,
  apagarDespesa,
  type Resultado,
} from "@/app/(app)/financeiro/acoes";
import {
  CATEGORIAS,
  rotuloCategoria,
  rotuloTipo,
  fraseDasDuasColunas,
  fraseDoRecuperado,
  fraseSemRegistro,
  type Painel,
} from "@/lib/financeiro";
import { formatar, paraCentavos } from "@/lib/dinheiro";
import { diaBr } from "@/lib/cobranca";

const INICIAL: Resultado = { estado: "inicial" };

export type SemRegistro = {
  sessao_id: string;
  paciente_id: string;
  nome: string;
  dia: string;
  valor: string;
};

export type DespesaLinha = {
  id: string;
  paga_em: string;
  categoria: string;
  descricao: string;
  valor: string;
};

function Botao({ rotulo, destaque }: { rotulo: string; destaque?: boolean }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className={
        destaque
          ? "rounded-full bg-cheia px-4 py-1.5 text-[12.5px] font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-45"
          : "rounded-full border border-linha2 px-3 py-1 text-[12px] font-medium text-tinta3 transition-colors hover:bg-folha2 hover:text-tinta2 disabled:opacity-45"
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

/**
 * As duas colunas.
 *
 * Elas ficam lado a lado, do mesmo tamanho, com a frase que explica a diferença
 * **entre** as duas — não num rodapé. Não há, em lugar nenhum desta tela, um
 * número que some as duas: seria contar a mesma hora duas vezes.
 */
export function PainelFinanceiro({
  painel,
  semRegistro,
  despesas,
  hoje,
}: {
  painel: Painel;
  semRegistro: SemRegistro[];
  despesas: DespesaLinha[];
  hoje: string;
}) {
  const [rReceber, receber] = useActionState(registrarRecebimento, INICIAL);
  const [rLancar, lancar] = useActionState(lancarDespesa, INICIAL);
  const [rApagar, apagar] = useActionState(apagarDespesa, INICIAL);
  const [lancando, setLancando] = useState(false);

  const recuperado = fraseDoRecuperado(painel);
  const faltando = fraseSemRegistro(painel);

  return (
    <>
      {/* ------------------------------------------------- as duas colunas */}
      <div className="mt-6 grid gap-3 sm:grid-cols-2">
        <div className="rounded-cartao border border-linha bg-folha2 px-5 py-4">
          <h2 className="rotulo">O que aconteceu</h2>
          <p className="mt-2 font-mono text-[24px] tabular-nums text-tinta">
            {formatar(painel.realizado.centavos)}
          </p>
          <p className="mt-1 text-[12.5px] text-tinta2">
            {painel.realizado.sessoes} sessão{painel.realizado.sessoes === 1 ? "" : "ões"} realizada
            {painel.realizado.sessoes === 1 ? "" : "s"}, pelo valor combinado de cada uma.
          </p>
        </div>

        <div className="rounded-cartao border border-cheia-linha bg-cheia-bg px-5 py-4">
          <h2 className="rotulo">O que entrou</h2>
          <p className="mt-2 font-mono text-[24px] tabular-nums text-cheia">
            {formatar(painel.recebido.centavos)}
          </p>
          <p className="mt-1 text-[12.5px] text-tinta2">
            {painel.recebido.porTipo.length === 0
              ? "Nenhum pagamento registrado neste mês."
              : painel.recebido.porTipo
                  .map((t) => `${formatar(t.centavos)} em ${rotuloTipo(t.tipo)}`)
                  .join(" · ")}
          </p>
        </div>
      </div>

      <p className="mt-3 max-w-2xl text-[13px] leading-relaxed text-tinta2">
        {fraseDasDuasColunas(painel)}{" "}
        <span className="text-tinta3">
          A primeira coluna é a data do atendimento; a segunda, a data do pagamento — é a
          segunda que bate com o extrato.
        </span>
      </p>

      {/* ----------------------------------------------------- o que voltou */}
      {recuperado && (
        <p className="mt-4 rounded-cartao border border-vaga-linha bg-vaga-bg px-5 py-3 text-[13px] leading-relaxed text-vaga">
          <b className="font-semibold">O sistema trouxe de volta:</b> {recuperado}
        </p>
      )}

      {/* --------------------------------------------- em aberto e perdoado */}
      {(painel.emAberto.cobrancas > 0 || painel.perdoado.cobrancas > 0) && (
        <p className="mt-3 text-[12.5px] text-tinta2">
          {painel.emAberto.cobrancas > 0 && (
            <>
              <b className="font-medium text-tinta">{formatar(painel.emAberto.centavos)}</b> em
              aberto —{" "}
              <Link href="/em-aberto" className="underline underline-offset-2 hover:text-vaga">
                ver quem
              </Link>
              .{" "}
            </>
          )}
          {painel.perdoado.cobrancas > 0 && (
            <>
              {formatar(painel.perdoado.centavos)} perdoado
              {painel.perdoado.cobrancas > 1 ? "s" : ""} neste mês.
            </>
          )}
        </p>
      )}

      {/* --------------------------------------------------- sem registro */}
      <section className="mt-8">
        <h2 className="rotulo">Horas sem recebimento registrado</h2>
        {semRegistro.length === 0 ? (
          <p className="mt-2 rounded-cartao border border-linha bg-folha2 px-5 py-4 text-[13px] leading-relaxed text-tinta2">
            Nada pendente: toda hora que aconteceu neste mês tem um recebimento
            registrado, ou está numa mensalidade ou pacote.
          </p>
        ) : (
          <>
            <p className="mt-2 max-w-2xl text-[13px] leading-relaxed text-tinta2">
              {faltando} Um painel que só mostra o que entrou mente por omissão — por isso
              estas aparecem aqui. Registrar é o que permite emitir recibo depois.
            </p>
            <ul className="mt-3 overflow-hidden rounded-cartao border border-linha bg-folha">
              {semRegistro.map((s) => (
                <li
                  key={s.sessao_id}
                  className="flex flex-wrap items-baseline gap-x-3 gap-y-2 border-t border-linha px-5 py-3 first:border-t-0"
                >
                  <Link
                    href={`/pacientes/${s.paciente_id}`}
                    className="text-[13.5px] text-tinta hover:text-vaga"
                  >
                    {s.nome}
                  </Link>
                  <span className="font-mono text-[12px] text-tinta3">{diaBr(s.dia)}</span>
                  <span className="font-mono text-[13px] tabular-nums text-tinta2">
                    {formatar(paraCentavos(s.valor))}
                  </span>
                  <form action={receber} className="ml-auto">
                    <input type="hidden" name="sessao" value={s.sessao_id} />
                    <input type="hidden" name="quando" value={s.dia <= hoje ? s.dia : hoje} />
                    <Botao rotulo="Recebi" destaque />
                  </form>
                </li>
              ))}
            </ul>
            <p className="mt-2 text-[11.5px] leading-relaxed text-tinta3">
              O recebimento é lançado na data da sessão. Se o dinheiro entrou em outro dia,
              corrija na cobrança — a data do pagamento é a que conta para o caixa.
            </p>
          </>
        )}
        <Recado r={rReceber} />
      </section>

      {/* ------------------------------------------------------- despesas */}
      <section className="mt-10">
        <div className="flex flex-wrap items-baseline gap-x-3">
          <h2 className="rotulo">O que saiu</h2>
          <span className="font-mono text-[13px] tabular-nums text-tinta2">
            {formatar(painel.despesas.centavos)}
          </span>
          <span className="text-[12px] text-tinta3">
            {painel.despesas.lancamentos} lançamento
            {painel.despesas.lancamentos === 1 ? "" : "s"}
          </span>
        </div>

        {painel.despesas.porCategoria.length > 0 && (
          <p className="mt-2 text-[12.5px] text-tinta2">
            {painel.despesas.porCategoria
              .map((c) => `${rotuloCategoria(c.categoria)} ${formatar(c.centavos)}`)
              .join(" · ")}
          </p>
        )}

        {despesas.length > 0 && (
          <ul className="mt-3 overflow-hidden rounded-cartao border border-linha bg-folha">
            {despesas.map((d) => (
              <li
                key={d.id}
                className="flex flex-wrap items-baseline gap-x-3 gap-y-1 border-t border-linha px-5 py-3 first:border-t-0"
              >
                <span className="font-mono text-[12px] text-tinta3">{diaBr(d.paga_em)}</span>
                <span className="text-[13px] text-tinta">{d.descricao}</span>
                <span className="text-[11.5px] text-tinta3">{rotuloCategoria(d.categoria)}</span>
                <span className="ml-auto font-mono text-[13px] tabular-nums text-tinta2">
                  {formatar(paraCentavos(d.valor))}
                </span>
                <form action={apagar}>
                  <input type="hidden" name="despesa" value={d.id} />
                  <Botao rotulo="apagar" />
                </form>
              </li>
            ))}
          </ul>
        )}
        <Recado r={rApagar} />

        <div className="mt-4">
          {!lancando ? (
            <button
              type="button"
              onClick={() => setLancando(true)}
              className="text-[12.5px] font-medium text-vaga hover:underline"
            >
              Lançar uma despesa →
            </button>
          ) : (
            <form action={lancar} className="rounded-cartao border border-linha bg-folha2 px-5 py-4">
              <p className="text-[12.5px] leading-relaxed text-tinta2">
                Só o que <b className="font-medium text-tinta">já saiu</b>. Não há vencimento,
                parcela nem lembrete: contas a pagar é outro sistema, e de propósito.
              </p>
              <div className="mt-3 grid gap-3 sm:grid-cols-4">
                <div>
                  <label htmlFor="paga_em" className="text-[12px] font-medium text-tinta2">
                    Quando saiu
                  </label>
                  <input
                    id="paga_em"
                    name="paga_em"
                    type="date"
                    max={hoje}
                    defaultValue={hoje}
                    className={`mt-1 ${CAMPO}`}
                  />
                </div>
                <div>
                  <label htmlFor="categoria" className="text-[12px] font-medium text-tinta2">
                    Categoria
                  </label>
                  <select id="categoria" name="categoria" defaultValue="aluguel" className={`mt-1 ${CAMPO}`}>
                    {CATEGORIAS.map((c) => (
                      <option key={c.valor} value={c.valor}>
                        {c.rotulo}
                      </option>
                    ))}
                  </select>
                </div>
                <div>
                  <label htmlFor="descricao" className="text-[12px] font-medium text-tinta2">
                    O que foi
                  </label>
                  <input
                    id="descricao"
                    name="descricao"
                    maxLength={120}
                    placeholder="Sala compartilhada"
                    className={`mt-1 ${CAMPO}`}
                  />
                </div>
                <div>
                  <label htmlFor="valor" className="text-[12px] font-medium text-tinta2">
                    Valor
                  </label>
                  <input
                    id="valor"
                    name="valor"
                    inputMode="decimal"
                    placeholder="900,00"
                    className={`mt-1 ${CAMPO}`}
                  />
                </div>
              </div>
              <div className="mt-3 flex items-center gap-3">
                <Botao rotulo="Lançar" destaque />
                <button
                  type="button"
                  onClick={() => setLancando(false)}
                  className="text-[12.5px] text-tinta3 hover:text-tinta2"
                >
                  cancelar
                </button>
              </div>
              <Recado r={rLancar} />
            </form>
          )}
        </div>
      </section>

      {/* ----------------------------------------------------------- a sobra */}
      <section className="mt-8 border-t border-linha pt-5">
        <div className="flex flex-wrap items-baseline gap-x-3">
          <h2 className="rotulo">Sobrou no mês</h2>
          <span
            className={`font-mono text-[20px] tabular-nums ${
              painel.sobra < 0 ? "text-vaga" : "text-tinta"
            }`}
          >
            {formatar(painel.sobra)}
          </span>
        </div>
        <p className="mt-2 max-w-2xl text-[12.5px] leading-relaxed text-tinta3">
          É o que entrou menos o que saiu, nas datas em que entrou e saiu. Não é lucro
          contábil, não é base de imposto e não substitui o seu contador — é o número que
          você usaria para saber como foi o mês.
        </p>
      </section>
    </>
  );
}
