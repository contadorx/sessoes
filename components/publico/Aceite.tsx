"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import { aceitar, type ResultadoAceite } from "@/app/p/contrato/[token]/acoes";

const INICIAL: ResultadoAceite = { estado: "inicial" };

function Confirmar() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="rounded-full bg-tinta px-6 py-2.5 text-[13.5px] font-medium text-papel transition-opacity hover:opacity-90 disabled:opacity-45"
    >
      {pending ? "confirmando…" : "Li e concordo"}
    </button>
  );
}

/**
 * O formulário de quem recebeu o link.
 *
 * Pede o nome e nada mais. Não pede CPF, não pede telefone, não pede e-mail e
 * não pede nada clínico — quem enviou já tem o que precisa, e um formulário
 * público que coleta dado de saúde é a fronteira do doc 07 que não se atravessa.
 * O que este campo faz é uma coisa só: registrar quem digitou o próprio nome
 * antes de clicar.
 */
export function Aceite({ token }: { token: string }) {
  const [r, despachar] = useActionState(aceitar, INICIAL);

  if (r.estado === "ok") {
    return (
      <div className="mt-8 rounded-cartao border border-cheia-linha bg-cheia-bg px-5 py-4">
        <p className="text-[14px] leading-relaxed text-cheia">
          Confirmado. Fica registrado com a data e a hora de agora.
        </p>
        <p className="mt-2 text-[12.5px] leading-relaxed text-tinta2">
          Guarde este link: ele continua abrindo o mesmo texto, com a data em que
          você confirmou.
        </p>
      </div>
    );
  }

  return (
    <form action={despachar} className="mt-8 border-t border-linha pt-6">
      <input type="hidden" name="token" value={token} />

      <div className="grid gap-3 sm:grid-cols-2">
        <div>
          <label htmlFor="nome" className="text-[12.5px] font-medium text-tinta2">
            Seu nome completo
          </label>
          <input
            id="nome"
            name="nome"
            required
            autoComplete="name"
            className="mt-1 w-full rounded-cartao border border-linha2 bg-folha px-3 py-2.5 text-[14px] text-tinta focus:border-tinta3 focus:outline-none"
          />
        </div>
        <div>
          <label htmlFor="parentesco" className="text-[12.5px] font-medium text-tinta2">
            Se você é responsável, qual o parentesco
          </label>
          <input
            id="parentesco"
            name="parentesco"
            placeholder="opcional"
            className="mt-1 w-full rounded-cartao border border-linha2 bg-folha px-3 py-2.5 text-[14px] text-tinta focus:border-tinta3 focus:outline-none"
          />
        </div>
      </div>

      <div className="mt-4">
        <Confirmar />
      </div>

      {r.estado === "erro" && (
        <p className="mt-3 text-[13px] leading-relaxed text-vaga">{r.mensagem}</p>
      )}

      <p className="mt-5 text-[11.5px] leading-relaxed text-tinta3">
        Ao confirmar, ficam registrados o seu nome, a data e a hora, e o texto
        exato desta página — que não muda depois. É uma assinatura eletrônica
        simples entre você e quem te enviou, não um certificado digital. Nada
        além disso é coletado aqui.
      </p>
    </form>
  );
}
