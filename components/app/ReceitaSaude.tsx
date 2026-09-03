"use client";

import Link from "next/link";
import { cpfBr } from "@/lib/formato";
import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import {
  marcarEmitido,
  desmarcar,
  dispensar,
  mudarModo,
  type Resultado,
} from "@/app/(app)/fechamento/receita-saude/acoes";
import {
  fraseDoPrazo,
  frasePisoDaMulta,
  fraseDasFaltas,
  fraseSemCpf,
  diaBr,
  diasParaDesfazer,
  fraseDaJanela,
  LIMITE_LINHAS,
  type Painel,
} from "@/lib/receitasaude";
import { formatar, paraCentavos } from "@/lib/dinheiro";

const INICIAL: Resultado = { estado: "inicial" };

export type AEmitir = {
  id: string;
  paciente_id: string;
  nome: string;
  cpf: string | null;
  pago_em: string;
  valor: string;
  tem_cpf: boolean;
};

export type Registrado = {
  id: string;
  nome: string;
  pago_em: string;
  valor: string;
  estado: string;
  numero_informado: string | null;
  marcado_por_ela_em: string | null;
  dispensa_motivo: string | null;
  divergente_em: string | null;
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
  "w-full rounded-cartao border border-linha2 bg-folha px-3 py-1.5 text-[12.5px] text-tinta focus:border-tinta3 focus:outline-none";

/**
 * A lista de digitação.
 *
 * A ordem das colunas é a ordem dos campos no app da Receita: data, quem pagou,
 * CPF, valor. Não é decoração — é para ela ir descendo a lista com o celular na
 * outra mão sem procurar nada.
 */
export function PainelReceitaSaude({
  painel,
  aEmitir,
  registrados,
  hoje,
  ano,
}: {
  painel: Painel;
  aEmitir: AEmitir[];
  registrados: Registrado[];
  hoje: string;
  ano: number;
}) {
  const [rMarcar, marcar] = useActionState(marcarEmitido, INICIAL);
  const [rDesmarcar, desfazer] = useActionState(desmarcar, INICIAL);
  const [rDispensar, dispensarAcao] = useActionState(dispensar, INICIAL);
  const [rModo, modo] = useActionState(mudarModo, INICIAL);
  const [dispensando, setDispensando] = useState<string | null>(null);

  const pendentes = painel.pendentes.n + painel.vencidos.n;
  const cor =
    painel.fase === "urgente" || painel.fase === "fechado"
      ? "border-vaga-linha bg-vaga-bg"
      : painel.fase === "atencao"
        ? "border-aviso-linha bg-aviso-bg"
        : "border-linha bg-folha2";

  if (!painel.ligado) {
    return (
      <div className="mt-6 rounded-cartao border border-linha bg-folha2 px-5 py-4">
        <p className="text-[13px] leading-relaxed text-tinta2">
          O modo Receita Saúde está <b className="font-medium text-tinta">desligado</b> nesta
          conta. Ele existe para a psicóloga <b className="font-medium text-tinta">autônoma
          pessoa física</b>, que desde 2025 precisa emitir o recibo de cada pagamento no app da
          Receita. Quem atende por CNPJ segue por nota fiscal, e não por aqui.
        </p>
        <form action={modo} className="mt-3">
          <input type="hidden" name="ligar" value="1" />
          <Botao rotulo="Ligar o modo" destaque />
        </form>
        <Recado r={rModo} />
      </div>
    );
  }

  return (
    <>
      {/* -------------------------------------------------------- o prazo */}
      <div className={`mt-6 rounded-cartao border px-5 py-4 ${cor}`}>
        <p className="text-[14px] leading-relaxed text-tinta">
          {fraseDoPrazo(painel.dias, pendentes, painel.prazo)}
        </p>
        {pendentes > 0 && (
          <p className="mt-2 text-[12.5px] leading-relaxed text-tinta2">
            {frasePisoDaMulta(painel.pendentes.n, painel.vencidos.n)}
          </p>
        )}
        <div className="mt-3 flex flex-wrap gap-x-5 gap-y-1 font-mono text-[12px] text-tinta3">
          <span>
            a emitir <b className="font-semibold text-tinta">{painel.pendentes.n}</b> ·{" "}
            {formatar(painel.pendentes.centavos)}
          </span>
          <span>
            emitidos <b className="font-semibold text-tinta">{painel.emitidos.n}</b>
          </span>
          {painel.dispensados.n > 0 && <span>dispensados {painel.dispensados.n}</span>}
          {painel.vencidos.n > 0 && (
            <span className="text-vaga">fora do prazo {painel.vencidos.n}</span>
          )}
        </div>
      </div>

      {/* ------------------------------------------------- o que não dá para nós */}
      <p className="mt-3 max-w-2xl text-[13px] leading-relaxed text-tinta2">
        <b className="font-semibold text-tinta">Quem emite é você, no app da Receita.</b> Não
        existe API pública, então nenhum sistema — este inclusive — consegue emitir por você. O
        que este aqui faz é saber o que falta, pôr na ordem de digitar e guardar o que você já
        fez.
      </p>

      {painel.semCpf > 0 && (
        <p className="mt-3 rounded-cartao border border-aviso-linha bg-aviso-bg px-5 py-3 text-[13px] leading-relaxed text-aviso">
          {fraseSemCpf(painel)}
        </p>
      )}

      {painel.divergentes > 0 && (
        <p className="mt-3 rounded-cartao border border-vaga-linha bg-vaga-bg px-5 py-3 text-[13px] leading-relaxed text-vaga">
          <b className="font-semibold">
            {painel.divergentes} recibo{painel.divergentes > 1 ? "s" : ""} emitido
            {painel.divergentes > 1 ? "s" : ""} sobre pagamento que voltou atrás.
          </b>{" "}
          Existe um recibo na Receita para um dinheiro que não entrou. Cancelar isso é lá, no
          app da Receita — daqui não dá, e por isso o registro fica marcado em vez de sumir.
        </p>
      )}

      {/* ------------------------------------------------ a lista de digitação */}
      <section className="mt-8">
        <h2 className="rotulo">A emitir</h2>
        {aEmitir.length === 0 ? (
          <p className="mt-2 rounded-cartao border border-linha bg-folha2 px-5 py-4 text-[13px] leading-relaxed text-tinta2">
            Nada a emitir neste ano. Quando você registrar um recebimento em{" "}
            <Link href="/recebimentos/movimentacoes" className="underline underline-offset-2 hover:text-vaga">
              Financeiro
            </Link>
            , ele aparece aqui.
          </p>
        ) : (
          <>
            <p className="mt-2 max-w-2xl text-[13px] leading-relaxed text-tinta2">
              Na ordem em que você vai digitar: data, quem pagou, CPF, valor.
            </p>
            <ul className="mt-3 overflow-hidden rounded-cartao border border-linha bg-folha">
              {aEmitir.map((r) => (
                <li key={r.id} className="border-t border-linha px-5 py-3 first:border-t-0">
                  <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                    <span className="font-mono text-[12.5px] tabular-nums text-tinta2">
                      {diaBr(r.pago_em)}
                    </span>
                    <Link
                      href={`/pacientes/${r.paciente_id}`}
                      className="text-[13.5px] text-tinta hover:text-vaga"
                    >
                      {r.nome}
                    </Link>
                    <span
                      className={`font-mono text-[12px] tabular-nums ${
                        r.tem_cpf ? "text-tinta3" : "text-aviso"
                      }`}
                    >
                      {r.tem_cpf ? cpfBr(r.cpf) : "sem CPF"}
                    </span>
                    <span className="ml-auto font-mono text-[13px] tabular-nums text-tinta">
                      {formatar(paraCentavos(r.valor))}
                    </span>
                  </div>

                  <div className="mt-2 flex flex-wrap items-center gap-2">
                    <form action={marcar} className="flex flex-wrap items-center gap-2">
                      <input type="hidden" name="recibo" value={r.id} />
                      {/* Ela está com o app da Receita na outra mão: o teclado
                          que abre aqui tem que ser o de número. */}
                      <input
                        name="numero"
                        inputMode="numeric"
                        autoComplete="off"
                        placeholder="número do recibo (opcional)"
                        maxLength={60}
                        className={`${CAMPO} w-56`}
                      />
                      <Botao rotulo="Emiti na Receita" destaque />
                    </form>

                    {dispensando === r.id ? (
                      <form action={dispensarAcao} className="flex flex-wrap items-center gap-2">
                        <input type="hidden" name="recibo" value={r.id} />
                        <input
                          name="motivo"
                          placeholder="por que não precisa de recibo?"
                          className={`${CAMPO} w-64`}
                        />
                        <Botao rotulo="Dispensar" />
                        <button
                          type="button"
                          onClick={() => setDispensando(null)}
                          className="text-[12px] text-tinta3 hover:text-tinta2"
                        >
                          cancelar
                        </button>
                      </form>
                    ) : (
                      <button
                        type="button"
                        onClick={() => setDispensando(r.id)}
                        className="text-[12px] text-tinta3 underline underline-offset-2 hover:text-tinta2"
                      >
                        não precisa de recibo
                      </button>
                    )}
                  </div>
                </li>
              ))}
            </ul>
          </>
        )}
        <Recado r={rMarcar} />
        <Recado r={rDispensar} />
      </section>

      {/* -------------------------------------------------- o arquivo em lote

          A alternativa a esta seção é a psicóloga digitar uma por uma. Quem
          atende oito por semana tem umas trinta e cinco por mês, e trinta e
          cinco digitações à mão é onde o mês passa e a multa chega.

          O passo "Analisar Arquivo" está escrito porque ele existe e é
          gratuito: é a conferência da própria Receita, feita antes de
          importar. Mandar conferir aqui seria pedir confiança no nosso
          formato; mandar conferir lá é pedir confiança na origem. */}
      {painel.pendentes.n > 0 && (
        <section className="mt-10">
          <h2 className="rotulo">Fazer em lote, em vez de uma por uma</h2>
          <div className="mt-3 rounded-cartao border border-linha bg-folha px-5 py-4">
            <p className="text-[13px] leading-relaxed text-tinta2">
              O carnê-leão do e-CAC importa um arquivo com até {LIMITE_LINHAS} lançamentos de
              uma vez. O arquivo abaixo sai no layout que ele espera, com as{" "}
              {painel.pendentes.n} pendência{painel.pendentes.n > 1 ? "s" : ""} deste ano
              {painel.semCpf > 0 && (
                <> — menos {painel.semCpf} que {painel.semCpf > 1 ? "estão" : "está"} sem CPF</>
              )}
              .
            </p>

            <a
              href={`/fechamento/receita-saude/csv?ano=${ano}`}
              className="mt-3 inline-block rounded-full bg-cheia px-4 py-1.5 text-[12.5px] font-semibold text-white transition-opacity hover:opacity-90"
            >
              Baixar o arquivo de {ano}
            </a>

            <ol className="mt-4 space-y-1.5 text-[12.5px] leading-relaxed text-tinta2">
              <li>
                <b className="font-medium text-tinta">1.</b> No e-CAC, abra Carnê-Leão →
                Escrituração → Importar Escrituração.
              </li>
              <li>
                <b className="font-medium text-tinta">2.</b> Use{" "}
                <b className="font-medium text-tinta">Analisar Arquivo</b> antes de importar.
                É a conferência da própria Receita, e é onde um engano aparece sem custo.
              </li>
              <li>
                <b className="font-medium text-tinta">3.</b> Importado, volte aqui e marque
                como emitido — o sistema não fica sabendo sozinho.
              </li>
            </ol>

            <p className="mt-4 text-[12px] leading-relaxed text-tinta3">
              O arquivo leva data, valor, o seu CPF, o CRP e o CPF de quem pagou. Não leva
              nome de paciente: o campo de descrição vai vazio de propósito, porque é campo
              livre que sai daqui para um terceiro.
            </p>
          </div>
        </section>
      )}

      {/* --------------------------------------------------- o que já foi feito */}
      {registrados.length > 0 && (
        <section className="mt-10">
          <h2 className="rotulo">O que você já resolveu</h2>
          <ul className="mt-3 overflow-hidden rounded-cartao border border-linha bg-folha">
            {registrados.map((r) => (
              <li
                key={r.id}
                className="flex flex-wrap items-baseline gap-x-3 gap-y-1 border-t border-linha px-5 py-3 first:border-t-0"
              >
                <span className="font-mono text-[12px] tabular-nums text-tinta3">
                  {diaBr(r.pago_em)}
                </span>
                <span className="text-[13px] text-tinta2">{r.nome}</span>
                <span className="font-mono text-[12.5px] tabular-nums text-tinta2">
                  {formatar(paraCentavos(r.valor))}
                </span>
                {r.estado === "marcado_por_ela" ? (
                  <span className="text-[11.5px] text-cheia">
                    você marcou {r.marcado_por_ela_em && diaBr(r.marcado_por_ela_em)}
                    {r.numero_informado && ` · nº ${r.numero_informado}`}
                    {r.divergente_em && " · pagamento desfeito depois"}
                  </span>
                ) : (
                  <span className="text-[11.5px] text-tinta3">
                    dispensado{r.dispensa_motivo && ` · ${r.dispensa_motivo}`}
                  </span>
                )}
                <form action={desfazer} className="ml-auto">
                  <input type="hidden" name="recibo" value={r.id} />
                  <Botao rotulo="desfazer" />
                </form>

                {/* A janela de dez dias.

                    "desfazer" aqui só apaga o que ELA anotou nesta tela — o
                    recibo continua de pé na Receita. Quem desfaz lá é ela, no
                    e-CAC, e tem dez dias contados da emissão. Sem esta linha,
                    o botão parece resolver uma coisa que não resolve. */}
                {r.estado === "marcado_por_ela" && (
                  <p className="w-full text-[11.5px] leading-relaxed text-tinta3">
                    {fraseDaJanela(diasParaDesfazer(r.marcado_por_ela_em, hoje))}
                  </p>
                )}
              </li>
            ))}
          </ul>
          <Recado r={rDesmarcar} />
        </section>
      )}

      {/* ------------------------------------------------------ o que fica fora */}
      {painel.faltasDeFora.n > 0 && (
        <p className="mt-8 max-w-2xl rounded-cartao border border-linha bg-folha2 px-5 py-4 text-[13px] leading-relaxed text-tinta2">
          {fraseDasFaltas(painel)}
        </p>
      )}

      <div className="mt-8">
        <form action={modo}>
          <input type="hidden" name="ligar" value="0" />
          <Botao rotulo="Desligar o modo Receita Saúde" />
        </form>
        <p className="mt-2 text-[11.5px] leading-relaxed text-tinta3">
          Desligar não apaga o que já está aqui — só para de criar pendência nova. Se você
          atende por CNPJ, o caminho é a nota fiscal.
        </p>
        <Recado r={rModo} />
      </div>
    </>
  );
}
