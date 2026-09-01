"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import {
  prepararCalendario,
  ajustarCalendario,
  pausarCalendario,
  desligarCalendario,
  importarHistorico,
  type Resultado,
} from "@/app/(app)/perfil/integracoes/acoes";
import {
  tituloDoEvento,
  rotuloDoModo,
  rotuloDaDirecao,
  fraseDaDefasagem,
  fraseDoEstado,
  fraseDaFila,
  lerHistorico,
  comValor,
  rotuloEstadoHistorico,
  diaBr,
  type ModoTitulo,
  type Direcao,
  type PainelCalendario,
} from "@/lib/calendario";
import { formatar } from "@/lib/dinheiro";

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
  if (r.estado === "ok")
    return <p className="mt-2 text-[12.5px] leading-relaxed text-cheia">{r.mensagem}</p>;
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

const MODOS: ModoTitulo[] = ["discreto", "iniciais", "completo"];
const DIRECOES: Direcao[] = ["duas_vias", "ler", "escrever"];

export function PainelDoCalendario({
  painel,
  exemplo,
}: {
  painel: PainelCalendario & { tem_credencial?: boolean; pendentes_antigas?: number };
  exemplo: string;
}) {
  const [rPreparar, preparar] = useActionState(prepararCalendario, INICIAL);
  const [rAjustar, ajustar] = useActionState(ajustarCalendario, INICIAL);
  const [rPausar, pausar] = useActionState(pausarCalendario, INICIAL);
  const [rDesligar, desligar] = useActionState(desligarCalendario, INICIAL);

  const [modo, setModo] = useState<ModoTitulo>(painel.modo_titulo ?? "discreto");
  const [abrirDesligar, setAbrirDesligar] = useState(false);

  const prof = painel.profissional_id ?? "";
  const preparado = painel.ligado;
  const autorizado = Boolean(painel.tem_credencial);

  return (
    <>
      {/* -------------------------------------------------------- o estado */}
      <section className="mt-6 rounded-cartao border border-linha bg-folha2 px-5 py-4">
        <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
          <span className="font-serif text-[17px] text-tinta">
            {autorizado ? "Google Agenda" : "Google Agenda — ainda não autorizada"}
          </span>
          <span className="text-[12px] text-tinta3">{fraseDoEstado(painel)}</span>
        </div>

        {!preparado && (
          <form action={preparar} className="mt-3">
            <input type="hidden" name="profissional_id" value={prof} />
            <p className="max-w-2xl text-[13px] leading-relaxed text-tinta2">
              Guarde primeiro o que você quer que aconteça. A autorização com a Google é o
              último passo, e ela pergunta uma vez só.
            </p>
            <div className="mt-3">
              <Botao rotulo="Preparar a conexão" destaque />
            </div>
            <Recado r={rPreparar} />
          </form>
        )}

        {preparado && !autorizado && (
          <p className="mt-3 max-w-2xl rounded-cartao border border-aviso-linha bg-aviso-bg px-4 py-3 text-[13px] leading-relaxed text-aviso">
            Está tudo configurado e nada sincroniza ainda: falta a autorização da Google, que
            depende do cadastro do aplicativo no console deles. Enquanto isso as sessões ficam
            esperando na fila abaixo, na ordem — nenhuma é perdida, e nenhuma é marcada como
            enviada sem ter saído.
          </p>
        )}

        {preparado && (
          <>
            <p className="mt-3 text-[12.5px] leading-relaxed text-tinta2">
              {fraseDaDefasagem(painel)}
            </p>
            <p className="mt-1 text-[12.5px] leading-relaxed text-tinta2">{fraseDaFila(painel)}</p>
            {(painel.pendentes_antigas ?? 0) > 0 && (
              <p className="mt-1 text-[12.5px] leading-relaxed text-vaga">
                {painel.pendentes_antigas} esperando há mais de um dia — fila que só cresce é
                fila parada.
              </p>
            )}
            {painel.erro && (
              <p className="mt-1 font-mono text-[11.5px] text-vaga">{painel.erro}</p>
            )}
            {(painel.ocupacoes ?? 0) > 0 && (
              <p className="mt-1 text-[12.5px] text-tinta3">
                {painel.ocupacoes} horas suas estão bloqueadas aqui por compromissos de lá. Eu
                sei <i>quando</i>; não sei, e não guardo, <i>o quê</i>.
              </p>
            )}
          </>
        )}
      </section>

      {/* -------------------------------------------------------- o ajuste */}
      {preparado && (
        <section className="mt-8">
          <h2 className="rotulo">O que sincronizar, e o que o evento diz</h2>
          <form
            action={ajustar}
            className="mt-3 rounded-cartao border border-linha bg-folha px-5 py-4"
          >
            <input type="hidden" name="profissional_id" value={prof} />

            <fieldset>
              <legend className="text-[12px] font-medium text-tinta2">Em que sentido</legend>
              <div className="mt-2 space-y-2">
                {DIRECOES.map((d) => {
                  const r = rotuloDaDirecao(d);
                  return (
                    <label key={d} className="flex items-start gap-2 text-[13px] leading-relaxed">
                      <input
                        type="radio"
                        name="direcao"
                        value={d}
                        defaultChecked={(painel.direcao ?? "duas_vias") === d}
                        className="mt-1"
                      />
                      <span>
                        <b className="font-medium text-tinta">{r.titulo}</b>{" "}
                        <span className="text-tinta3">{r.explica}</span>
                      </span>
                    </label>
                  );
                })}
              </div>
            </fieldset>

            <fieldset className="mt-5">
              <legend className="text-[12px] font-medium text-tinta2">
                O que vai escrito no evento
              </legend>
              <div className="mt-2 space-y-2">
                {MODOS.map((m) => {
                  const r = rotuloDoModo(m);
                  return (
                    <label key={m} className="flex items-start gap-2 text-[13px] leading-relaxed">
                      <input
                        type="radio"
                        name="modo_titulo"
                        value={m}
                        checked={modo === m}
                        onChange={() => setModo(m)}
                        className="mt-1"
                      />
                      <span>
                        <b className="font-medium text-tinta">{r.titulo}</b>{" "}
                        <span className="text-tinta3">{r.explica}</span>
                      </span>
                    </label>
                  );
                })}
              </div>

              <p className="mt-3 rounded-cartao border border-linha bg-folha2 px-4 py-3 text-[13px] text-tinta2">
                Na sua agenda vai aparecer:{" "}
                <b className="font-mono font-semibold text-tinta">
                  {tituloDoEvento(modo, exemplo)}
                </b>
              </p>
            </fieldset>

            <p className="mt-3 max-w-2xl text-[11.5px] leading-relaxed text-tinta3">
              Trocar isto reescreve os eventos <b>daqui para a frente</b>. Os que já foram ficam
              como estão — reescrever um ano de agenda é ruído, e apagar o que já está lá é
              decisão sua, no Google.
            </p>

            <div className="mt-3">
              <Botao rotulo="Salvar" destaque />
            </div>
            <Recado r={rAjustar} />
          </form>
        </section>
      )}

      {/* ------------------------------------------------- pausar e desligar */}
      {preparado && (
        <section className="mt-8 flex flex-wrap items-start gap-6">
          <form action={pausar}>
            <input type="hidden" name="profissional_id" value={prof} />
            <input
              type="hidden"
              name="pausar"
              value={painel.estado === "pausado" ? "0" : "1"}
            />
            <Botao rotulo={painel.estado === "pausado" ? "Voltar a sincronizar" : "Pausar"} />
            <Recado r={rPausar} />
          </form>

          <div>
            {!abrirDesligar ? (
              <button
                type="button"
                onClick={() => setAbrirDesligar(true)}
                className="text-[12.5px] text-tinta3 underline underline-offset-2 hover:text-vaga"
              >
                desconectar a agenda
              </button>
            ) : (
              <form action={desligar} className="flex flex-wrap items-end gap-2">
                <input type="hidden" name="profissional_id" value={prof} />
                <div>
                  <label htmlFor="confirma" className="text-[12px] text-tinta2">
                    Escreva <b className="font-mono">desconectar</b>
                  </label>
                  <input id="confirma" name="confirma" className={`mt-1 ${CAMPO} w-52`} />
                </div>
                <Botao rotulo="Desconectar" />
              </form>
            )}
            <Recado r={rDesligar} />
          </div>
        </section>
      )}
    </>
  );
}

// ===================================================== o histórico de fora

export function TrazerHistorico({ hoje }: { hoje: string }) {
  const [r, importar] = useActionState(importarHistorico, INICIAL);
  const [texto, setTexto] = useState("");

  const previa = texto.trim() === "" ? null : lerHistorico(texto, hoje);

  return (
    <form action={importar} className="mt-4">
      <label htmlFor="colagem" className="text-[12px] font-medium text-tinta2">
        Cole aqui — uma sessão por linha
      </label>
      <textarea
        id="colagem"
        name="colagem"
        rows={7}
        value={texto}
        onChange={(e) => setTexto(e.target.value)}
        placeholder={
          "Maria Fernanda; 05/03/2024; 15h; compareceu; 200\nJoão Pedro; 12/03/2024; 16h; faltou\nMaria Fernanda; 12/03/2024; 15h"
        }
        className={`mt-1 ${CAMPO} font-mono text-[12.5px] leading-relaxed`}
      />
      <p className="mt-1 text-[11.5px] leading-relaxed text-tinta3">
        <b className="font-medium text-tinta2">paciente; data; hora; o que houve; valor</b> — da
        hora em diante tudo é opcional. Sem hora, assumo meio-dia. Sem “o que houve”, assumo que
        a sessão aconteceu. Serve ponto e vírgula, vírgula ou o que sai da planilha.
      </p>

      {previa && (
        <div className="mt-4 rounded-cartao border border-linha bg-folha2 px-5 py-4">
          <p className="text-[13px] text-tinta">
            <b className="font-semibold">{previa.sessoes.length}</b>{" "}
            {previa.sessoes.length === 1 ? "sessão lida" : "sessões lidas"}
            {comValor(previa) > 0 && ` · ${comValor(previa)} com valor`}
            {previa.erros.length > 0 && (
              <span className="text-vaga">
                {" "}
                · {previa.erros.length}{" "}
                {previa.erros.length === 1 ? "linha não entendida" : "linhas não entendidas"}
              </span>
            )}
          </p>

          {previa.sessoes.length > 0 && (
            <ul className="mt-3 space-y-1 font-mono text-[12px] text-tinta2">
              {previa.sessoes.slice(0, 8).map((s) => (
                <li key={s.linha}>
                  {diaBr(s.dia)} {s.hora} · {s.paciente} · {rotuloEstadoHistorico(s.estado)}
                  {s.valorCentavos !== null && ` · ${formatar(s.valorCentavos)}`}
                </li>
              ))}
              {previa.sessoes.length > 8 && (
                <li className="text-tinta3">…e mais {previa.sessoes.length - 8}</li>
              )}
            </ul>
          )}

          {previa.erros.length > 0 && (
            <ul className="mt-3 space-y-1 text-[12px] text-vaga">
              {previa.erros.slice(0, 6).map((e) => (
                <li key={e.linha}>
                  linha {e.linha}: {e.motivo} — <span className="font-mono">{e.texto}</span>
                </li>
              ))}
              {previa.erros.length > 6 && (
                <li className="text-tinta3">…e mais {previa.erros.length - 6}</li>
              )}
            </ul>
          )}
        </div>
      )}

      <div className="mt-4">
        <Botao rotulo="Trazer o histórico" destaque />
      </div>
      <Recado r={r} />
    </form>
  );
}
