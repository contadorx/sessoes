"use client";

import Link from "next/link";
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
  numero_rfb: string | null;
  emitido_em: string | null;
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

/** O CPF como a Receita pede: 000.000.000-00. */
function cpfBr(cpf: string | null): string {
  if (!cpf || cpf.length !== 11) return "—";
  return `${cpf.slice(0, 3)}.${cpf.slice(3, 6)}.${cpf.slice(6, 9)}-${cpf.slice(9)}`;
}

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
}: {
  painel: Painel;
  aEmitir: AEmitir[];
  registrados: Registrado[];
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
                      <input
                        name="numero"
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
                {r.estado === "emitido" ? (
                  <span className="text-[11.5px] text-cheia">
                    emitido {r.emitido_em && diaBr(r.emitido_em)}
                    {r.numero_rfb && ` · nº ${r.numero_rfb}`}
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
