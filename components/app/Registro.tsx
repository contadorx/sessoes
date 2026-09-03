"use client";

import { useActionState, useEffect, useRef, useState } from "react";
import { useFormStatus } from "react-dom";
import { salvarDemanda, escreverEvolucao, type Resultado } from "@/app/(app)/pacientes/acoes";
import {
  blocos,
  fraseDosBlocos,
  fraseSemEvolucao,
  rotuloModalidade,
  rotuloCamada,
  explicaCamada,
  rotuloEncerramento,
  prazoDeGuarda,
  fraseDoPrazo,
  diaBr,
  MODALIDADES,
  FREQUENCIAS,
  frequenciaNaLista,
  type RegistroDoPaciente,
  type Camada,
} from "@/lib/registro";
import { apagarRascunho, guardarRascunho, lerRascunho } from "@/lib/rascunho";

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
 * A escolha da camada, com a consequência de **cada** opção à vista.
 *
 * Antes só a frase da opção marcada aparecia — e clicar no outro rádio para ler
 * o que ele faz já era escolher. Escolher em que camada o registro nasce é a
 * decisão mais difícil de desfazer desta tela; ela precisa das duas frases
 * antes de decidir, não depois.
 */
function EscolhaDaCamada({ atual }: { atual: Camada }) {
  const [c, setC] = useState<Camada>(atual);
  return (
    <div className="mt-2 grid gap-3 sm:grid-cols-2">
      {(["prontuario", "documental"] as Camada[]).map((v) => (
        <label
          key={v}
          className="flex cursor-pointer gap-2 rounded-cartao border border-linha2 px-3 py-2.5 has-[:checked]:border-vaga has-[:checked]:bg-vaga-bg"
        >
          <input
            type="radio"
            name="camada"
            value={v}
            checked={c === v}
            onChange={() => setC(v)}
            className="mt-0.5"
          />
          <span>
            <span className="block text-[12.5px] text-tinta">{rotuloCamada(v)}</span>
            <span className="mt-0.5 block text-[11.5px] leading-relaxed text-tinta3">
              {explicaCamada(v)}
            </span>
          </span>
        </label>
      ))}
    </div>
  );
}

/**
 * A evolução de uma sessão.
 *
 * Nasce fechada quando já existe texto (para não convidar a reescrever) e
 * aberta quando a hora está sem registro — que é o caso em que a tela está
 * pedindo alguma coisa.
 */
export function Evolucao({
  sessaoId,
  dia,
  texto,
  camada,
  editadoEm,
  comecaAberta,
}: {
  sessaoId: string;
  dia: string;
  texto: string | null;
  camada: Camada;
  editadoEm?: string | null;
  comecaAberta?: boolean;
}) {
  const [r, escrever] = useActionState(escreverEvolucao, INICIAL);
  const [aberta, setAberta] = useState(Boolean(comecaAberta));

  /*
    O rascunho.

    Ela escreve isto de pé, entre uma sessão e outra, num aparelho que descarta
    PWA em segundo plano — e até esta build o produto não tinha rascunho em
    forma nenhuma. Sair da tela perdia o texto, sem aviso.

    A textarea continua **não-controlada**: o rascunho é gravado no `onInput`
    com uma pausa, e o valor nunca volta como prop. Controlar o campo custaria
    re-render a cada tecla numa tela que já faz quinze consultas, e é
    justamente o que o arquivo da build recusa.
  */
  const campo = useRef<HTMLTextAreaElement>(null);
  const relogio = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [recuperado, setRecuperado] = useState(false);

  useEffect(() => {
    const guardado = lerRascunho(
      typeof window === "undefined" ? null : window.localStorage,
      sessaoId,
    );
    // Só recupera o que **acrescenta**: se o rascunho é igual ao que já está
    // salvo, não há nada a recuperar e o aviso seria ruído.
    if (guardado === null || guardado === (texto ?? "")) return;
    if (campo.current) {
      campo.current.value = guardado;
      setRecuperado(true);
    }
  }, [sessaoId, texto]);

  // Gravou: o rascunho serviu e some. Um que sobrevive ao salvamento é texto
  // clínico parado no aparelho sem ninguém precisar dele.
  useEffect(() => {
    if (r.estado !== "ok") return;
    apagarRascunho(typeof window === "undefined" ? null : window.localStorage, sessaoId);
  }, [r, sessaoId]);

  const aoDigitar = (valor: string) => {
    if (relogio.current) clearTimeout(relogio.current);
    relogio.current = setTimeout(() => {
      guardarRascunho(
        typeof window === "undefined" ? null : window.localStorage,
        sessaoId,
        valor,
      );
    }, 600);
  };

  if (!aberta) {
    return (
      <div className="rounded-cartao border border-linha bg-folha px-5 py-3">
        <div className="flex flex-wrap items-baseline gap-x-3">
          <span className="font-mono text-[12.5px] tabular-nums text-tinta2">{diaBr(dia)}</span>
          {camada === "documental" && (
            <span className="rounded-full border border-linha bg-folha2 px-2 py-0.5 text-[10.5px] font-semibold uppercase tracking-wider text-tinta3">
              gaveta
            </span>
          )}
          <button
            type="button"
            onClick={() => setAberta(true)}
            className="ml-auto text-[11.5px] text-tinta3 hover:text-vaga"
          >
            editar
          </button>
        </div>
        <p className="mt-2 whitespace-pre-wrap text-[13px] leading-relaxed text-tinta">{texto}</p>
        {editadoEm && (
          <p className="mt-1 text-[11px] text-tinta3">editada em {diaBr(editadoEm.slice(0, 10))}</p>
        )}
      </div>
    );
  }

  return (
    <form action={escrever} className="rounded-cartao border border-linha bg-folha px-5 py-4">
      <input type="hidden" name="sessao_id" value={sessaoId} />
      <div className="flex flex-wrap items-baseline gap-x-3">
        <span className="font-mono text-[12.5px] tabular-nums text-tinta2">{diaBr(dia)}</span>
        <span className="text-[12px] font-medium text-tinta2">evolução do trabalho</span>
      </div>
      <textarea
        ref={campo}
        name="texto"
        rows={5}
        maxLength={20000}
        defaultValue={texto ?? ""}
        onInput={(e) => aoDigitar(e.currentTarget.value)}
        placeholder="O que foi trabalhado, e como."
        className={`mt-2 ${CAMPO}`}
      />
      {recuperado && r.estado !== "ok" && (
        <p className="mt-1 text-[11.5px] leading-relaxed text-tinta3">
          Recuperei o que você tinha começado a escrever neste aparelho. Ele some
          quando você guardar.
        </p>
      )}
      {/*
        Ditar, sem que o áudio passe por aqui.

        O microfone do teclado do celular escreve neste campo como escreve em
        qualquer outro, e a gravação nunca chega ao produto: ela não sai do
        aparelho dela. Um gravador embutido teria que mandar o áudio de uma
        evolução para um serviço de transcrição de terceiro — e áudio de
        evolução é dado clínico. É a fronteira 9, e ela não se atravessa em nome
        de conveniência.
      */}
      <p className="mt-1 text-[11.5px] leading-relaxed text-tinta3">
        Dá para ditar: o microfone do teclado do seu celular escreve aqui, e o
        áudio não passa pelo Sessões.
      </p>
      <EscolhaDaCamada atual={camada} />
      <div className="mt-3 flex flex-wrap items-center gap-3">
        <Botao rotulo="Guardar" destaque />
        {texto && (
          <button
            type="button"
            onClick={() => setAberta(false)}
            className="text-[12px] text-tinta3 hover:text-tinta2"
          >
            fechar
          </button>
        )}
        <span className="text-[11px] text-tinta3">
          Guarda de cinco anos: o que entra aqui não se apaga.
        </span>
      </div>
      <Recado r={r} />
    </form>
  );
}

/**
 * A frequência, agora em seleção — com uma saída.
 *
 * O campo era texto livre, e o Leandro pediu lista. A lista resolve o problema
 * real (a mesma frequência escrita de quatro jeitos na mesma base) e o campo
 * livre ao lado resolve o que a lista não pode resolver: **o software não opina
 * sobre frequência de atendimento** — doc 07, e é a linha que a B27 guarda com
 * teste. Uma lista fechada transformaria estas cinco opções no conjunto das
 * frequências que existem, e quem decide o ritmo de um caso é quem atende.
 *
 * Por isso "outra" não é enfeite: ela é o que faz a lista ser atalho em vez de
 * vocabulário. E o que já estava escrito na ficha antes desta mudança abre
 * direto em "outra", com o texto intacto — trocar um valor antigo por um da
 * lista seria o software reescrevendo registro clínico para caber num select.
 */
function Frequencia({ atual }: { atual: string | null }) {
  const naLista = frequenciaNaLista(atual);
  const [escolha, setEscolha] = useState(naLista ? atual! : atual ? "outra" : "");

  return (
    <div>
      <label htmlFor="frequencia_escolha" className="text-[12px] font-medium text-tinta2">
        Frequência
      </label>
      <select
        id="frequencia_escolha"
        name={escolha === "outra" ? "frequencia_escolha" : "frequencia"}
        value={escolha}
        onChange={(e) => setEscolha(e.target.value)}
        className={`mt-1 ${CAMPO}`}
      >
        <option value="">não registrada</option>
        {FREQUENCIAS.map((f) => (
          <option key={f} value={f}>
            {f}
          </option>
        ))}
        <option value="outra">outra —&nbsp;escrevo abaixo</option>
      </select>

      {escolha === "outra" && (
        <input
          name="frequencia"
          maxLength={200}
          autoFocus={!atual}
          defaultValue={naLista ? "" : (atual ?? "")}
          placeholder="como está combinado"
          className={`mt-2 ${CAMPO}`}
        />
      )}
    </div>
  );
}

export function PainelRegistro({
  pacienteId,
  registro,
  ultimoRegistro,
  retencaoAnos,
}: {
  pacienteId: string;
  registro: RegistroDoPaciente;
  ultimoRegistro: string;
  retencaoAnos: number;
}) {
  const [rDemanda, salvar] = useActionState(salvarDemanda, INICIAL);
  const [tudo, setTudo] = useState(false);

  const lista = blocos(registro);
  const semEvolucao = fraseSemEvolucao(registro);
  const evolucoes = tudo ? registro.evolucoes : registro.evolucoes.slice(0, 6);
  const prazo = prazoDeGuarda(ultimoRegistro, registro.identificacao?.nascimento ?? null, retencaoAnos);

  return (
    <>
      {/* ------------------------------------------------- os quatro blocos */}
      <div className="mt-3 rounded-cartao border border-linha bg-folha2 px-5 py-4">
        <p className="text-[13.5px] text-tinta">{fraseDosBlocos(registro)}</p>
        <ul className="mt-3 grid gap-1 sm:grid-cols-2">
          {lista.map((b) => (
            <li key={b.n} className="flex items-baseline gap-2 text-[12.5px]">
              <span
                className={
                  b.completo
                    ? "font-mono text-[11px] text-cheia"
                    : "font-mono text-[11px] text-tinta3"
                }
                aria-hidden
              >
                {b.completo ? "●" : "○"}
              </span>
              <span className={b.completo ? "text-tinta2" : "text-tinta3"}>
                {b.n}. {b.nome}
                <span className="text-tinta3"> · {b.onde}</span>
              </span>
            </li>
          ))}
        </ul>
        {semEvolucao && <p className="mt-3 text-[12.5px] text-vaga">{semEvolucao}</p>}
        <p className="mt-3 text-[11.5px] leading-relaxed text-tinta3">{fraseDoPrazo(prazo)}</p>
      </div>

      {/* ------------------------------------------------- bloco 2 · demanda */}
      <section className="mt-6">
        <h3 className="rotulo">2 · Avaliação da demanda</h3>
        <form action={salvar} className="mt-2 rounded-cartao border border-linha bg-folha px-5 py-4">
          <input type="hidden" name="paciente_id" value={pacienteId} />

          <label htmlFor="demanda" className="text-[12px] font-medium text-tinta2">
            Por que procurou
          </label>
          <textarea
            id="demanda"
            name="demanda"
            rows={3}
            maxLength={5000}
            defaultValue={registro.demanda?.texto ?? ""}
            className={`mt-1 ${CAMPO}`}
          />

          <label htmlFor="objetivos" className="mt-3 block text-[12px] font-medium text-tinta2">
            Objetivos do trabalho
          </label>
          <textarea
            id="objetivos"
            name="objetivos"
            rows={3}
            maxLength={5000}
            defaultValue={registro.demanda?.objetivos ?? ""}
            className={`mt-1 ${CAMPO}`}
          />

          <div className="mt-3 grid gap-3 sm:grid-cols-2">
            <Frequencia atual={registro.demanda?.frequencia ?? null} />
            <div>
              <label htmlFor="modalidade" className="text-[12px] font-medium text-tinta2">
                Modalidade
              </label>
              <select
                id="modalidade"
                name="modalidade"
                defaultValue={registro.demanda?.modalidade ?? ""}
                className={`mt-1 ${CAMPO}`}
              >
                <option value="">não registrada</option>
                {MODALIDADES.map((m) => (
                  <option key={m.valor} value={m.valor}>
                    {m.rotulo}
                  </option>
                ))}
              </select>
            </div>
          </div>

          <p className="mt-2 text-[11.5px] leading-relaxed text-tinta3">
            Presencial ou remoto é conteúdo mínimo do registro desde a Res. CFP 09/2024 — hoje
            está como <b className="font-medium">{rotuloModalidade(registro.demanda?.modalidade ?? null)}</b>.
          </p>

          <div className="mt-3">
            <Botao rotulo="Guardar" destaque />
          </div>
          <Recado r={rDemanda} />
        </form>
      </section>

      {/* ------------------------------------------------ bloco 3 · evolução */}
      <section className="mt-8">
        <h3 className="rotulo">3 · Evolução do trabalho</h3>

        {registro.sem_evolucao.length > 0 && (
          <div className="mt-2 space-y-3">
            {registro.sem_evolucao.map((s) => (
              <Evolucao
                key={s.sessao_id}
                sessaoId={s.sessao_id}
                dia={s.dia}
                texto={null}
                camada="prontuario"
                comecaAberta
              />
            ))}
          </div>
        )}

        {registro.evolucoes.length === 0 && registro.sem_evolucao.length === 0 ? (
          <p className="mt-2 rounded-cartao border border-dashed border-linha2 bg-folha px-5 py-4 text-[13px] text-tinta2">
            Nenhuma sessão realizada ainda — a evolução nasce da hora que aconteceu.
          </p>
        ) : (
          <div className="mt-3 space-y-3">
            {evolucoes.map((e) => (
              <Evolucao
                key={e.id}
                sessaoId={e.sessao_id ?? ""}
                dia={e.dia}
                texto={e.texto}
                camada={e.camada}
                editadoEm={e.editado_em}
              />
            ))}
          </div>
        )}

        {registro.evolucoes.length > 6 && (
          <button
            type="button"
            onClick={() => setTudo(!tudo)}
            className="mt-3 text-[12.5px] text-tinta3 underline underline-offset-2 hover:text-vaga"
          >
            {tudo ? "mostrar só as últimas" : `ver as ${registro.evolucoes.length} evoluções`}
          </button>
        )}
      </section>

      {/* -------------------------------------------- bloco 4 · encerramento */}
      <section className="mt-8">
        <h3 className="rotulo">4 · Encaminhamento ou encerramento</h3>
        {registro.encerramento ? (
          <p className="mt-2 rounded-cartao border border-linha bg-folha px-5 py-3 text-[13px] text-tinta2">
            {rotuloEncerramento(registro.encerramento.tipo)} em{" "}
            {diaBr(registro.encerramento.em.slice(0, 10))}.
          </p>
        ) : (
          <p className="mt-2 rounded-cartao border border-dashed border-linha2 bg-folha px-5 py-3 text-[13px] leading-relaxed text-tinta3">
            Em aberto — como tem de estar enquanto o acompanhamento existe. O encerramento
            guiado (alta, abandono ou encaminhamento) entra na próxima build; hoje ele é escrito
            ao arquivar a ficha.
          </p>
        )}
      </section>
    </>
  );
}
