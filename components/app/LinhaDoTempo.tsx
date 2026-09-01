"use client";

import { useState } from "react";
import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import { anotarAusencia, type Resultado } from "@/app/(app)/pacientes/acoes";
import {
  fraseDoTotal,
  fraseDasUltimas,
  fraseDaSequencia,
  fraseDesdeAUltima,
  fraseDaComposicao,
  rotuloDesfecho,
  sinalDoDesfecho,
  rotuloOrigem,
  rotuloCobranca,
  podeAnotar,
  diaCurto,
  porMes,
  nomeDoMes,
  type LinhaDoTempo as Linha,
  type PainelAusencias,
} from "@/lib/ausencias";
import { formatar, paraCentavos } from "@/lib/dinheiro";

const INICIAL: Resultado = { estado: "inicial" };

const HORA = new Intl.DateTimeFormat("pt-BR", {
  timeZone: "America/Sao_Paulo",
  hour: "2-digit",
  minute: "2-digit",
});

function Salvar() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="rounded-full bg-cheia px-4 py-1.5 text-[12.5px] font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-45"
    >
      {pending ? "…" : "Guardar"}
    </button>
  );
}

/**
 * A nota da hora que não houve.
 *
 * Fica fechada por padrão: uma caixa de texto aberta em toda linha da lista
 * convida a preencher, e o que se quer aqui é o contrário — que ela escreva
 * quando **tiver** o que dizer.
 */
function Nota({ linha }: { linha: Linha }) {
  const [r, anotar] = useActionState(anotarAusencia, INICIAL);
  const [aberta, setAberta] = useState(false);

  if (!podeAnotar(linha.estado)) {
    // A sessão que aconteceu não tem caixa. A explicação aparece uma vez, no
    // rodapé da seção — repeti-la em cada linha seria ruído.
    return linha.nota ? (
      <p className="mt-2 whitespace-pre-wrap border-l-2 border-linha2 pl-3 text-[12.5px] leading-relaxed text-tinta2">
        {linha.nota}
      </p>
    ) : null;
  }

  if (!aberta && linha.nota) {
    return (
      <div className="mt-2">
        <p className="whitespace-pre-wrap border-l-2 border-linha2 pl-3 text-[12.5px] leading-relaxed text-tinta2">
          {linha.nota}
        </p>
        <button
          type="button"
          onClick={() => setAberta(true)}
          className="mt-1 pl-3 text-[11.5px] text-tinta3 hover:text-vaga"
        >
          editar
        </button>
      </div>
    );
  }

  if (!aberta) {
    return (
      <button
        type="button"
        onClick={() => setAberta(true)}
        className="mt-2 text-[11.5px] text-tinta3 hover:text-vaga"
      >
        + escrever o que houve
      </button>
    );
  }

  return (
    <form action={anotar} className="mt-2">
      <input type="hidden" name="sessao_id" value={linha.sessao_id} />
      <textarea
        name="nota"
        rows={3}
        maxLength={2000}
        defaultValue={linha.nota ?? ""}
        placeholder="O que aconteceu com esta hora."
        className="w-full rounded-cartao border border-linha2 bg-folha px-3 py-2 text-[13px] leading-relaxed text-tinta focus:border-tinta3 focus:outline-none"
      />
      <div className="mt-2 flex flex-wrap items-center gap-3">
        <Salvar />
        <button
          type="button"
          onClick={() => setAberta(false)}
          className="text-[12px] text-tinta3 hover:text-tinta2"
        >
          fechar
        </button>
        <span className="text-[11px] text-tinta3">
          Apagar é salvar em branco.
        </span>
      </div>
      {r.estado === "erro" &&
        r.erros.map((e, i) => (
          <p key={i} className="mt-1 text-[12px] text-vaga">
            {e}
          </p>
        ))}
    </form>
  );
}

export function LinhaDoTempo({
  linhas,
  ausencias,
  hoje,
}: {
  linhas: Linha[];
  ausencias: PainelAusencias;
  hoje: string;
}) {
  const [tudo, setTudo] = useState(false);
  const mostradas = tudo ? linhas : linhas.slice(0, 12);
  const grupos = porMes(mostradas);
  const sequencia = fraseDaSequencia(ausencias);
  const composicao = fraseDaComposicao(ausencias);

  return (
    <>
      {/* ---------------------------------------------------- a aritmética */}
      <div className="mt-3 rounded-cartao border border-linha bg-folha2 px-5 py-4">
        <p className="text-[13.5px] text-tinta">{fraseDoTotal(ausencias)}</p>

        {ausencias.ultimos.length > 0 && (
          <p className="mt-3 font-mono text-[15px] tracking-[0.35em] text-tinta2">
            {ausencias.ultimos.map(sinalDoDesfecho).join("")}
          </p>
        )}

        <div className="mt-2 space-y-0.5 text-[12.5px] leading-relaxed text-tinta2">
          <p>{fraseDasUltimas(ausencias)}</p>
          {sequencia && <p>{sequencia}</p>}
          {composicao && <p className="text-tinta3">{composicao}</p>}
          <p className="text-tinta3">{fraseDesdeAUltima(ausencias)}</p>
        </div>
      </div>

      {/* -------------------------------------------------------- a lista */}
      {linhas.length === 0 ? (
        <p className="mt-3 rounded-cartao border border-dashed border-linha2 bg-folha px-5 py-4 text-[13px] text-tinta2">
          Nada aconteceu ainda. Se esta pessoa já era sua antes deste sistema, dá para trazer
          o histórico em Calendário.
        </p>
      ) : (
        <div className="mt-4 space-y-6">
          {grupos.map((g) => (
            <section key={g.mes}>
              <h3 className="rotulo">{nomeDoMes(g.mes)}</h3>
              <ul className="mt-2 space-y-3">
                {g.linhas.map((l) => {
                  const origem = rotuloOrigem(l.origem);
                  const dinheiro = rotuloCobranca(l);
                  return (
                    <li
                      key={l.sessao_id}
                      className="rounded-cartao border border-linha bg-folha px-5 py-3"
                    >
                      <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                        <span className="font-mono text-[13px] tabular-nums text-tinta2">
                          {diaCurto(l.dia, hoje)} · {HORA.format(new Date(l.inicio))}
                        </span>
                        <span
                          className={
                            l.estado === "realizada"
                              ? "text-[13px] text-tinta"
                              : "text-[13px] font-medium text-vaga"
                          }
                        >
                          {rotuloDesfecho(l.estado)}
                        </span>
                        {origem && (
                          <span className="text-[11.5px] text-tinta3">· {origem}</span>
                        )}
                        {dinheiro && (
                          <span className="ml-auto font-mono text-[11.5px] text-tinta3">
                            {formatar(paraCentavos(l.cobranca_valor ?? "0"))} {dinheiro}
                          </span>
                        )}
                      </div>
                      <Nota linha={l} />
                    </li>
                  );
                })}
              </ul>
            </section>
          ))}
        </div>
      )}

      {linhas.length > 12 && (
        <button
          type="button"
          onClick={() => setTudo(!tudo)}
          className="mt-4 text-[12.5px] text-tinta3 underline underline-offset-2 hover:text-vaga"
        >
          {tudo ? "mostrar só as últimas" : `ver as ${linhas.length} horas`}
        </button>
      )}
    </>
  );
}
