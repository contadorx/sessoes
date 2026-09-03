"use client";

import { useActionState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { useFormStatus } from "react-dom";
import Link from "next/link";
import { Recado } from "@/components/app/campos";
import {
  oferecerEmCascata,
  responderPorEla,
  expirarOfertas,
  type Resultado,
} from "@/app/(app)/encaixes/acoes";
import type { Evento, OfertaLinha, Vaga } from "@/app/(app)/encaixes/dados";
import { rotuloJanela, tempoDeEspera, type Janela } from "@/lib/janela";
import { formatar, paraCentavos } from "@/lib/dinheiro";

const INICIAL: Resultado = { estado: "inicial" };

export type LinhaDaFila = {
  paciente_id: string;
  nome: string;
  elegivel: boolean;
  motivo: string;
  ordem: number;
  janelas: Janela[];
  ultima_sessao: string | null;
  oferta: OfertaLinha | null;
};

const HORA = new Intl.DateTimeFormat("pt-BR", {
  timeZone: "America/Sao_Paulo",
  hour: "2-digit",
  minute: "2-digit",
});

const QUANDO = new Intl.DateTimeFormat("pt-BR", {
  timeZone: "America/Sao_Paulo",
  weekday: "long",
  day: "numeric",
  month: "long",
  hour: "2-digit",
  minute: "2-digit",
});

const TEXTO_EVENTO: Record<string, string> = {
  vaga_aberta: "Vaga aberta. A fila foi consultada.",
  // Os dois momentos, separados pela 0089. `oferta_preparada` nasce quando a
  // oferta é criada; `oferta_enviada` só quando a mensagem saiu de verdade — e
  // quem grava é quem viu sair. Antes disso a trilha dizia "Oferta enviada" no
  // instante da criação: onze linhas assim no banco, e em nenhuma delas a
  // mensagem havia saído.
  oferta_preparada: "Oferta preparada. A mensagem entrou para sair.",
  oferta_enviada: "Oferta enviada",
  oferta_recusada: "Não pôde. Segue na fila para a próxima.",
  oferta_expirada: "Não respondeu a tempo. A fila andou.",
  oferta_aceita: "Aceitou a vaga.",
  vaga_preenchida: "Horário preenchido.",
  vaga_sem_takers: "Ninguém da fila cabe nesta vaga.",
};

function Botao({ rotulo, tom = "vaga" }: { rotulo: string; tom?: "vaga" | "leve" }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className={
        tom === "vaga"
          ? "rounded-full bg-vaga px-5 py-2.5 text-[13px] font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-45"
          : "rounded-full border border-linha2 px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2 disabled:opacity-45"
      }
    >
      {pending ? "…" : rotulo}
    </button>
  );
}

function Responder({
  ofertaId,
  sessaoId,
  resposta,
  rotulo,
}: {
  ofertaId: string;
  sessaoId: string;
  resposta: "aceita" | "recusada";
  rotulo: string;
}) {
  const [r, despachar] = useActionState(responderPorEla, INICIAL);
  return (
    <form action={despachar} className="inline-flex flex-col gap-1 align-top">
      <input type="hidden" name="oferta_id" value={ofertaId} />
      <input type="hidden" name="sessao_id" value={sessaoId} />
      <input type="hidden" name="resposta" value={resposta} />
      <Botao rotulo={rotulo} tom="leve" />
      {/* Responder pela pessoa é escrita em nome de outro — a recusa do banco
          (oferta que já expirou, vaga que outra pessoa aceitou) tem de aparecer
          aqui, e não no silêncio de um botão que volta a ficar clicável. */}
      <Recado r={r} />
    </form>
  );
}

export function Cascata({
  vaga,
  fila,
  eventos,
  regra,
  temOfertaViva,
  recuperado,
}: {
  vaga: Vaga;
  fila: LinhaDaFila[];
  eventos: Evento[];
  regra: string;
  temOfertaViva: boolean;
  recuperado: string | null;
}) {
  const router = useRouter();
  const [estado, oferecer] = useActionState(oferecerEmCascata, INICIAL);
  const [expEstado, expirar] = useActionState(expirarOfertas, INICIAL);

  // "Ao vivo" honesto: enquanto há oferta pendente, a página se recarrega
  // sozinha. Quando o WhatsApp entrar, é aqui que a resposta aparece.
  useEffect(() => {
    if (!temOfertaViva) return;
    const t = setInterval(() => router.refresh(), 15_000);
    return () => clearInterval(t);
  }, [temOfertaViva, router]);

  // Preparada conta: a pergunta que este sinal responde é "a fila já foi
  // acionada para esta vaga?", e ela foi. Só `oferta_enviada` deixaria a tela
  // oferecer acionar de novo uma cascata que já está de pé esperando as 8h.
  const jaOfertou = eventos.some(
    (e) => e.tipo === "oferta_preparada" || e.tipo === "oferta_enviada",
  );
  const preenchida = eventos.some((e) => e.tipo === "vaga_preenchida");
  const semTakers = eventos.some((e) => e.tipo === "vaga_sem_takers") && !preenchida;

  return (
    <div className="grid gap-5 lg:grid-cols-[minmax(0,1.15fr)_minmax(0,1fr)]">
      {/* ------------------------------------------------ a fila */}
      <div>
        <div className="rounded-cartao border border-linha bg-folha2 px-4 py-3 text-[12.5px] leading-relaxed text-tinta2">
          <b className="font-semibold text-tinta">Regra de prioridade:</b> {regra}.{" "}
          <Link href="/encaixes#regras" className="underline underline-offset-2 hover:text-vaga">
            mudar
          </Link>
          <br />
          A fila nunca vira leilão: dinheiro não compra posição.
        </div>

        {fila.length === 0 ? (
          <p className="mt-3 rounded-cartao border border-dashed border-linha2 bg-folha px-4 py-6 text-center text-[13px] text-tinta2">
            Nenhum paciente na fila.{" "}
            <Link href="/encaixes" className="font-medium text-vaga hover:underline">
              colocar alguém →
            </Link>
          </p>
        ) : (
          <ul className="mt-3 flex flex-col gap-2">
            {fila.map((p, i) => {
              const oferta = p.oferta;
              const estadoOferta = oferta?.estado;

              const caixa =
                estadoOferta === "enviada"
                  ? "border-vaga-linha bg-vaga-bg"
                  : estadoOferta === "aceita"
                    ? "border-cheia-linha bg-cheia-bg"
                    : "border-linha bg-folha";

              const apagado =
                !p.elegivel || estadoOferta === "recusada" || estadoOferta === "expirada"
                  ? "opacity-60"
                  : "";

              const rotulo =
                estadoOferta === "enviada"
                  ? "oferta enviada…"
                  : estadoOferta === "aceita"
                    ? "✓ aceitou a vaga"
                    : estadoOferta === "recusada"
                      ? "não pôde"
                      : estadoOferta === "expirada"
                        ? "não respondeu"
                        : p.elegivel
                          ? "na fila"
                          : `✕ ${p.motivo}`;

              const cor =
                estadoOferta === "enviada"
                  ? "text-vaga"
                  : estadoOferta === "aceita"
                    ? "text-cheia"
                    : "text-tinta3";

              return (
                <li
                  key={p.paciente_id}
                  className={`rounded-cartao border px-3 py-2.5 transition-colors ${caixa} ${apagado}`}
                >
                  <div className="grid grid-cols-[22px_minmax(0,1fr)_auto] items-center gap-3">
                    <span className="font-mono text-[12px] text-tinta3">{i + 1}</span>
                    <span className="min-w-0">
                      <span
                        className={`block truncate text-[13.5px] font-medium leading-tight ${
                          estadoOferta === "aceita" ? "text-cheia" : "text-tinta"
                        }`}
                      >
                        {p.nome}
                      </span>
                      <span className="block truncate text-[11.5px] leading-tight text-tinta3">
                        {rotuloJanela(p.janelas)} · {tempoDeEspera(p.ultima_sessao)}
                      </span>
                    </span>
                    <span className={`whitespace-nowrap text-[11.5px] font-semibold ${cor}`}>
                      {rotulo}
                    </span>
                  </div>

                  {estadoOferta === "enviada" && oferta && (
                    <div className="mt-2.5 flex flex-wrap items-center gap-2 border-t border-vaga-linha/60 pt-2.5">
                      <span className="text-[11.5px] text-tinta2">
                        respondeu por fora?
                      </span>
                      <Responder
                        ofertaId={oferta.id}
                        sessaoId={vaga.id}
                        resposta="aceita"
                        rotulo="Aceitou"
                      />
                      <Responder
                        ofertaId={oferta.id}
                        sessaoId={vaga.id}
                        resposta="recusada"
                        rotulo="Não pôde"
                      />
                      <span className="ml-auto font-mono text-[11px] text-tinta3">
                        vence {HORA.format(new Date(oferta.expira_em))}
                      </span>
                    </div>
                  )}
                </li>
              );
            })}
          </ul>
        )}

        <div className="mt-4 flex flex-wrap items-center gap-3">
          {!preenchida && (
            <form action={oferecer}>
              <input type="hidden" name="sessao_id" value={vaga.id} />
              <Botao rotulo={jaOfertou ? "Oferecer ao próximo" : "Oferecer em cascata"} />
            </form>
          )}

          {temOfertaViva && (
            <form action={expirar}>
              <Botao rotulo="Vencer o prazo agora" tom="leve" />
            </form>
          )}
        </div>

        {estado.estado === "erro" && (
          <p className="mt-3 text-[12.5px] font-medium text-vaga">{estado.erros[0]}</p>
        )}
        {estado.estado === "ok" && (
          <p className="mt-3 text-[12.5px] font-medium text-cheia">{estado.mensagem}</p>
        )}
        {expEstado.estado === "ok" && (
          <p className="mt-2 text-[12.5px] text-tinta2">{expEstado.mensagem}</p>
        )}
      </div>

      {/* ------------------------------------------------ o log */}
      <div className="rounded-cartao border border-linha bg-folha p-5">
        <span className="rotulo">{QUANDO.format(new Date(vaga.inicio))}</span>

        <ul className="mt-3 min-h-[168px]">
          {eventos.length === 0 && (
            <li className="py-2 text-[12.5px] text-tinta3">
              {vaga.pacientes?.nome ?? "Alguém"} desmarcou
              {vaga.cancelada_em &&
                ` às ${HORA.format(new Date(vaga.cancelada_em))}`}
              . O horário está aberto e ninguém foi avisado ainda.
            </li>
          )}

          {eventos.map((e) => {
            const bom = e.tipo === "vaga_preenchida" || e.tipo === "oferta_aceita";
            const nome = typeof e.detalhe?.paciente === "string" ? e.detalhe.paciente : null;

            return (
              <li
                key={e.id}
                className={`grid grid-cols-[46px_minmax(0,1fr)] gap-3 border-t border-dotted border-linha2 py-2 text-[12.5px] first:border-t-0 ${
                  bom ? "font-medium text-cheia" : "text-tinta2"
                }`}
              >
                <span className="font-mono text-[11px] text-tinta3">
                  {HORA.format(new Date(e.em))}
                </span>
                <span>
                  {TEXTO_EVENTO[e.tipo] ?? e.tipo}
                  {nome && ` — ${nome}`}
                </span>
              </li>
            );
          })}
        </ul>

        <div
          className={`mt-1 rounded-cartao border px-4 py-4 transition-colors ${
            preenchida
              ? "border-cheia-linha bg-cheia-bg"
              : semTakers
                ? "border-aviso-linha bg-aviso-bg"
                : "border-linha bg-folha2"
          }`}
        >
          <p className="text-[12.5px] leading-relaxed text-tinta2">
            {preenchida
              ? "Você não pediu nada a ninguém, não mandou mensagem e não negociou. O horário tem dono de novo."
              : semTakers
                ? "Ninguém da fila cabe nesta vaga. O horário continua vazio — e é isso que o número abaixo mostra."
                : temOfertaViva
                  ? "Oferta em aberto. Se ninguém responder até o prazo, a fila anda sozinha."
                  : "A hora vazia continua vazia."}
          </p>
          <span
            className={`tabular mt-2 block font-mono text-[26px] font-medium ${
              preenchida ? "text-cheia" : "text-vaga"
            }`}
          >
            {preenchida
              ? `+ ${formatar(paraCentavos(recuperado ?? vaga.valor))}`
              : `− ${formatar(paraCentavos(vaga.valor))}`}
          </span>
        </div>
      </div>
    </div>
  );
}
