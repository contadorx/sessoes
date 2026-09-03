"use client";

import { useState } from "react";

const MSG = {
  discreto: {
    de: "Agenda",
    texto:
      "Olá, João. Abriu um horário hoje às 15h. Responde SIM até 14h30 para confirmar.",
  },
  comum: {
    de: "Dra. Renata Alves · Psicologia",
    texto:
      "Olá, João Pedro! Abriu um horário para a sua sessão de psicoterapia hoje às 15h. Podemos antecipar o seu atendimento desta semana?",
  },
} as const;

type Modo = keyof typeof MSG;

/**
 * O remetente neutro é metade promessa de texto e metade promessa de número.
 *
 * A primeira o produto cumpre sempre: o texto não leva o nome profissional nem
 * a natureza do atendimento. A segunda depende de haver provedor — sem ele a
 * mensagem sai do WhatsApp dela, e o remetente é o número dela. Afirmar as
 * duas sem condição é prometer o que hoje não acontece, na página que ela lê
 * antes de assinar.
 */
export function Discricao({ envioAutomatico }: { envioAutomatico: boolean }) {
  const [modo, setModo] = useState<Modo>("discreto");
  const msg = MSG[modo];
  const exposto = modo === "comum";

  return (
    <div className="grid items-start gap-6 lg:grid-cols-[minmax(0,1fr)_280px]">
      <div>
        <div className="inline-flex gap-1 rounded-full border border-linha bg-folha2 p-1">
          {(["discreto", "comum"] as const).map((m) => (
            <button
              key={m}
              type="button"
              onClick={() => setModo(m)}
              aria-pressed={modo === m}
              className={`rounded-full px-3.5 py-1.5 text-[12.5px] font-medium transition-colors ${
                modo === m
                  ? "bg-folha text-tinta shadow-sm"
                  : "text-tinta3 hover:text-tinta2"
              }`}
            >
              {m === "discreto" ? "Modo discreto (padrão)" : "Como os outros fazem"}
            </button>
          ))}
        </div>

        <div
          className={`mt-4 rounded-cartao border-l-[3px] px-4 py-3.5 text-[13px] leading-relaxed ${
            exposto
              ? "border border-aviso-linha border-l-aviso bg-aviso-bg text-tinta2"
              : "border border-cheia-linha border-l-cheia bg-cheia-bg text-tinta2"
          }`}
        >
          {exposto ? (
            <>
              <b className="font-semibold text-tinta">
                Isso pode custar o emprego ou o casamento de alguém.
              </b>{" "}
              O nome profissional e a palavra “psicoterapia” aparecem na tela
              bloqueada — que pode estar na mão do marido, do pai, do chefe. É
              como praticamente todo lembrete automático do mercado é enviado
              hoje.
            </>
          ) : (
            <>
              <b className="font-semibold text-tinta">
                {envioAutomatico
                  ? "Remetente neutro, sem a natureza do atendimento e sem o seu nome profissional."
                  : "Texto neutro, sem a natureza do atendimento e sem o seu nome profissional — e ele sai do seu WhatsApp, com um toque seu."}
              </b>{" "}
              Quem passar pela mesa da cozinha lê um lembrete de agenda — não
              descobre que a pessoa faz terapia. Esta é a posição padrão do
              produto, não uma caixinha escondida nas configurações.
            </>
          )}
        </div>
      </div>

      <div>
        <div className="mx-auto w-[280px] rounded-[34px] border border-[#2A302D] bg-[#0C100E] p-3 shadow-[0_24px_48px_-28px_rgba(0,0,0,.6)]">
          <div className="flex min-h-[300px] flex-col items-center rounded-[24px] bg-[linear-gradient(168deg,#38474B_0%,#1E2A2C_55%,#141C1E_100%)] px-3.5 pb-8 pt-7 text-[#EDF1EE]">
            <div className="tabular font-mono text-[44px] font-normal leading-none tracking-[-0.02em]">
              14:26
            </div>
            <div className="mt-1 text-[11.5px] opacity-60">
              terça-feira, 1º de setembro
            </div>

            <div
              className={`mt-6 w-full rounded-[13px] border p-3 text-left backdrop-blur transition-colors duration-300 ${
                exposto
                  ? "border-[rgba(242,116,158,.55)] bg-[rgba(171,39,88,.24)]"
                  : "border-[rgba(245,248,246,.14)] bg-[rgba(245,248,246,.14)]"
              }`}
            >
              <div className="flex justify-between text-[10.5px] uppercase tracking-[.05em] opacity-70">
                <span>{msg.de}</span>
                <span>agora</span>
              </div>
              <div className="mt-1.5 text-[12.5px] leading-snug">{msg.texto}</div>
            </div>
          </div>
        </div>
        <p className="mt-3 text-center text-[11.5px] text-tinta3">
          Tela bloqueada do celular do paciente
        </p>
      </div>
    </div>
  );
}
