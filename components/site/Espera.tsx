"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import { entrarNaLista, type EstadoInscricao } from "@/app/(site)/acoes";

const INICIAL: EstadoInscricao = { estado: "inicial" };

function Botao() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="rounded-full bg-vaga px-6 py-3 text-[13.5px] font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-45"
    >
      {pending ? "Enviando…" : "Entrar na lista"}
    </button>
  );
}

export function Espera() {
  const [estado, acao] = useActionState(entrarNaLista, INICIAL);

  if (estado.estado === "ok") {
    return (
      <div className="sobe rounded-cartao border border-cheia-linha bg-cheia-bg px-5 py-6 text-center">
        <p className="font-serif text-[22px] text-cheia">{estado.mensagem}</p>
        <p className="mt-1.5 text-[13px] text-tinta2">
          Sem newsletter, sem corrente de e-mail. Escrevo uma vez, quando houver
          o que mostrar.
        </p>
      </div>
    );
  }

  return (
    <form action={acao} className="rounded-cartao border border-linha bg-folha p-5 sm:p-6">
      {/* armadilha para robô — invisível para gente */}
      <input
        type="text"
        name="site"
        tabIndex={-1}
        autoComplete="off"
        aria-hidden="true"
        className="absolute left-[-9999px] h-0 w-0 opacity-0"
      />

      <div className="grid gap-3 sm:grid-cols-2">
        <label className="block">
          <span className="rotulo">Seu e-mail</span>
          <input
            type="email"
            name="email"
            required
            autoComplete="email"
            placeholder="voce@exemplo.com.br"
            className="mt-1.5 w-full rounded-[5px] border border-linha2 bg-folha px-3 py-2.5 text-[14px] text-tinta placeholder:text-tinta3/70"
          />
        </label>

        <label className="block">
          <span className="rotulo">Como você atende</span>
          <select
            name="perfil"
            defaultValue="autonoma"
            className="mt-1.5 w-full rounded-[5px] border border-linha2 bg-folha px-3 py-2.5 text-[14px] text-tinta"
          >
            <option value="autonoma">Consultório próprio, sozinha</option>
            <option value="clinica">Clínica ou grupo</option>
            <option value="estudante">Ainda em formação</option>
            <option value="outro">Outro</option>
          </select>
        </label>
      </div>

      <div className="mt-4 flex flex-col items-start gap-3 sm:flex-row sm:items-center sm:justify-between">
        <p className="max-w-[42ch] text-[11.5px] leading-relaxed text-tinta3">
          Guardo só o e-mail e essa resposta, para avisar quando abrir. Nada de
          lista comprada, nada compartilhado.
        </p>
        <Botao />
      </div>

      {estado.estado === "erro" && (
        <p className="mt-3 text-[12.5px] font-medium text-vaga">{estado.mensagem}</p>
      )}
    </form>
  );
}
