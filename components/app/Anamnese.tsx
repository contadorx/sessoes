"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import {
  abrirAnamnese,
  salvarAnamnese,
  fecharAnamnese,
  acrescentarAdendo,
  type Resultado,
} from "@/app/(app)/pacientes/acoes";
import {
  roteiroPadrao,
  fraseDoProgresso,
  fraseDoAviso,
  fraseDoLimite,
  rotuloModelo,
  podeFechar,
  diaBr,
  MODELOS,
  AVISO_DE_FECHAMENTO,
  type Anamnese,
  type Aviso,
  type ModeloAnamnese,
  type Secao,
} from "@/lib/anamnese";

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
  if (r.estado === "ok") return <p className="mt-2 text-[12.5px] text-cheia">{r.mensagem}</p>;
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
  "w-full rounded-cartao border border-linha2 bg-folha px-3 py-2 text-[13px] leading-relaxed text-tinta focus:border-tinta3 focus:outline-none";

/**
 * O aviso da terceira (PR5).
 *
 * Fala do registro dela — "a anamnese ainda está aberta" —, nunca do paciente.
 * E diz que o número é provisório: um número que não se apresenta como palpite
 * vira regra por hábito antes de alguém opinar sobre ele.
 */
export function AvisoDaTerceira({ aviso }: { aviso: Aviso }) {
  if (!aviso.mostrar) return null;
  return (
    <div className="mt-3 rounded-cartao border border-aviso-linha bg-aviso-bg px-5 py-3">
      <p className="text-[13px] leading-relaxed text-aviso">{fraseDoAviso(aviso)}</p>
      <p className="mt-1 text-[11.5px] leading-relaxed text-aviso">{fraseDoLimite(aviso)}</p>
    </div>
  );
}

/** A escolha do modelo mostra o roteiro **antes** de abrir. */
function Escolher({ pacienteId }: { pacienteId: string }) {
  const [r, abrir] = useActionState(abrirAnamnese, INICIAL);
  const [modelo, setModelo] = useState<ModeloAnamnese>("adulto");

  return (
    <form action={abrir} className="mt-3 rounded-cartao border border-linha bg-folha px-5 py-4">
      <input type="hidden" name="paciente_id" value={pacienteId} />
      <fieldset>
        <legend className="text-[12px] font-medium text-tinta2">Qual roteiro</legend>
        <div className="mt-2 space-y-2">
          {MODELOS.map((m) => (
            <label key={m.valor} className="flex items-start gap-2 text-[13px] leading-relaxed">
              <input
                type="radio"
                name="modelo"
                value={m.valor}
                checked={modelo === m.valor}
                onChange={() => setModelo(m.valor)}
                className="mt-1"
              />
              <span>
                <b className="font-medium text-tinta">{m.rotulo}</b>{" "}
                <span className="text-tinta3">— {m.quando}</span>
              </span>
            </label>
          ))}
        </div>
      </fieldset>

      <div className="mt-3 rounded-cartao border border-linha bg-folha2 px-4 py-3">
        <p className="text-[11.5px] font-medium text-tinta2">As seções que vão aparecer:</p>
        <ul className="mt-1 space-y-0.5 text-[12.5px] text-tinta2">
          {roteiroPadrao(modelo).map((t) => (
            <li key={t}>· {t}</li>
          ))}
        </ul>
        <p className="mt-2 text-[11px] leading-relaxed text-tinta3">
          São títulos, não perguntas. Você escreve por baixo de cada um, acrescenta seção e tira
          seção — o roteiro é ponto de partida, e ainda vai ser revisto com uma psicóloga.
        </p>
      </div>

      <div className="mt-3">
        <Botao rotulo="Abrir a anamnese" destaque />
      </div>
      <Recado r={r} />
    </form>
  );
}

export function PainelAnamnese({
  pacienteId,
  anamnese,
  aviso,
}: {
  pacienteId: string;
  anamnese: Anamnese | null;
  aviso: Aviso;
}) {
  const [rSalvar, salvar] = useActionState(salvarAnamnese, INICIAL);
  const [rFechar, fechar] = useActionState(fecharAnamnese, INICIAL);
  const [rAdendo, adendar] = useActionState(acrescentarAdendo, INICIAL);

  const [secoes, setSecoes] = useState<Secao[]>(anamnese?.conteudo ?? []);
  const [abrirFechar, setAbrirFechar] = useState(false);

  if (!anamnese) {
    return (
      <>
        <AvisoDaTerceira aviso={aviso} />
        <p className="mt-3 max-w-xl text-[13px] leading-relaxed text-tinta2">
          A anamnese acontece na conversa, e é aqui que ela fica registrada. O sistema{" "}
          <b className="font-semibold text-tinta">não manda formulário para o paciente</b>: pergunta
          clínica não se responde sozinho às onze da noite.
        </p>
        <Escolher pacienteId={pacienteId} />
      </>
    );
  }

  const fechada = anamnese.estado === "fechada";

  return (
    <>
      <AvisoDaTerceira aviso={aviso} />

      <div className="mt-3 flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <span className="rounded-full border border-linha bg-folha2 px-2 py-0.5 text-[10.5px] font-semibold uppercase tracking-wider text-tinta3">
          {rotuloModelo(anamnese.modelo)}
        </span>
        <span className="text-[12.5px] text-tinta2">{fraseDoProgresso(anamnese)}</span>
        {anamnese.fechada_em && (
          <span className="text-[11.5px] text-tinta3">em {diaBr(anamnese.fechada_em)}</span>
        )}
      </div>

      {anamnese.medicacao_atual && (
        <p className="mt-2 rounded-cartao border border-linha bg-folha2 px-4 py-2 text-[12.5px] text-tinta2">
          <b className="font-medium text-tinta">Medicação:</b> {anamnese.medicacao_atual}
        </p>
      )}

      {/* ------------------------------------------------------- as seções */}
      {fechada ? (
        <div className="mt-4 space-y-4">
          {anamnese.conteudo.map((s, i) => (
            <div key={i}>
              <h4 className="text-[12px] font-semibold text-tinta2">{s.titulo}</h4>
              {s.texto.trim() === "" ? (
                <p className="mt-1 text-[12.5px] italic text-tinta3">— sem registro nesta seção</p>
              ) : (
                <p className="mt-1 whitespace-pre-wrap text-[13px] leading-relaxed text-tinta">
                  {s.texto}
                </p>
              )}
            </div>
          ))}
        </div>
      ) : (
        <form action={salvar} className="mt-4">
          <input type="hidden" name="anamnese_id" value={anamnese.id} />
          <input type="hidden" name="conteudo" value={JSON.stringify(secoes)} />

          <div className="space-y-4">
            {secoes.map((s, i) => (
              <div key={i}>
                <input
                  value={s.titulo}
                  onChange={(e) => {
                    const c = [...secoes];
                    c[i] = { ...c[i], titulo: e.target.value };
                    setSecoes(c);
                  }}
                  maxLength={200}
                  className="w-full bg-transparent text-[12px] font-semibold text-tinta2 focus:outline-none"
                />
                <textarea
                  value={s.texto}
                  onChange={(e) => {
                    const c = [...secoes];
                    c[i] = { ...c[i], texto: e.target.value };
                    setSecoes(c);
                  }}
                  rows={3}
                  maxLength={20000}
                  className={`mt-1 ${CAMPO}`}
                />
              </div>
            ))}
          </div>

          <button
            type="button"
            onClick={() => setSecoes([...secoes, { titulo: "Nova seção", texto: "" }])}
            className="mt-3 text-[12px] text-tinta3 hover:text-vaga"
          >
            + acrescentar seção
          </button>

          <div className="mt-4">
            <label htmlFor="medicacao" className="text-[12px] font-medium text-tinta2">
              Medicação em uso
            </label>
            <input
              id="medicacao"
              name="medicacao"
              maxLength={2000}
              defaultValue={anamnese.medicacao_atual ?? ""}
              className={`mt-1 ${CAMPO}`}
            />
            <p className="mt-1 text-[11px] leading-relaxed text-tinta3">
              Fica num campo próprio para ser encontrável — antes de uma sessão ninguém relê seis
              seções para achar isto.
            </p>
          </div>

          <div className="mt-4">
            <Botao rotulo="Guardar" destaque />
          </div>
          <Recado r={rSalvar} />
        </form>
      )}

      {/* -------------------------------------------------------- fechar */}
      {!fechada && (
        <div className="mt-6 border-t border-linha pt-4">
          {!abrirFechar ? (
            <>
              <p className="max-w-xl text-[12.5px] leading-relaxed text-tinta3">
                {AVISO_DE_FECHAMENTO}
              </p>
              <button
                type="button"
                onClick={() => setAbrirFechar(true)}
                disabled={!podeFechar(anamnese)}
                className="mt-2 text-[12.5px] text-tinta3 underline underline-offset-2 hover:text-vaga disabled:no-underline disabled:opacity-45"
              >
                {podeFechar(anamnese)
                  ? "fechar a anamnese"
                  : "escreva ao menos uma seção para poder fechar"}
              </button>
            </>
          ) : (
            <form action={fechar} className="flex flex-wrap items-end gap-2">
              <input type="hidden" name="anamnese_id" value={anamnese.id} />
              <div>
                <label htmlFor="confirma" className="text-[12px] text-tinta2">
                  Escreva <b className="font-mono">fechar</b>
                </label>
                <input id="confirma" name="confirma" className={`mt-1 ${CAMPO} w-40`} />
              </div>
              <Botao rotulo="Fechar" />
              <button
                type="button"
                onClick={() => setAbrirFechar(false)}
                className="text-[12px] text-tinta3 hover:text-tinta2"
              >
                cancelar
              </button>
            </form>
          )}
          <Recado r={rFechar} />
        </div>
      )}

      {/* ------------------------------------------------------- adendos */}
      {fechada && (
        <section className="mt-6 border-t border-linha pt-4">
          <h4 className="rotulo">O que chegou depois</h4>

          {anamnese.adendos.length > 0 && (
            <ul className="mt-2 space-y-3">
              {anamnese.adendos.map((a) => (
                <li key={a.id} className="border-l-2 border-linha2 pl-3">
                  <p className="font-mono text-[11.5px] text-tinta3">{diaBr(a.criado_em)}</p>
                  <p className="mt-0.5 whitespace-pre-wrap text-[13px] leading-relaxed text-tinta">
                    {a.texto}
                  </p>
                </li>
              ))}
            </ul>
          )}

          <form action={adendar} className="mt-4">
            <input type="hidden" name="anamnese_id" value={anamnese.id} />
            <textarea
              name="texto"
              rows={3}
              maxLength={5000}
              placeholder="O que apareceu depois da anamnese fechada."
              className={CAMPO}
            />
            <div className="mt-2 flex flex-wrap items-center gap-3">
              <Botao rotulo="Acrescentar adendo" />
              <span className="text-[11px] text-tinta3">
                Entra com a data de hoje, e não se edita depois.
              </span>
            </div>
            <Recado r={rAdendo} />
          </form>
        </section>
      )}
    </>
  );
}
