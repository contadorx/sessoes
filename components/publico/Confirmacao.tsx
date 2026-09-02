"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import {
  responderConfirmacao,
  type ResultadoConfirmacao,
} from "@/app/p/agora/[token]/acoes";
import { quando, rotuloDaResposta, esperaResposta, type ItemDeConfirmacao } from "@/lib/pagina-do-paciente";

const INICIAL: ResultadoConfirmacao = { estado: "inicial" };

function Botao({
  rotulo,
  valor,
  principal,
}: {
  rotulo: string;
  valor: "sim" | "nao";
  principal?: boolean;
}) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      name="resposta"
      value={valor}
      disabled={pending}
      className={`flex-1 rounded-full px-4 py-3 text-center text-[14px] font-semibold transition-opacity hover:opacity-90 disabled:opacity-45 ${
        principal
          ? "bg-vaga text-white"
          : "border border-linha2 bg-folha text-tinta2"
      }`}
    >
      {pending ? "enviando…" : rotulo}
    </button>
  );
}

/**
 * Um horário, e as duas respostas possíveis.
 *
 * **Os dois botões têm o mesmo tamanho, e isso é decisão.** "Não vou" menor,
 * mais claro ou escondido atrás de um link transformaria a página num
 * instrumento de pressão — e a resposta que o produto mais precisa receber é
 * justamente a inconveniente: saber com um dia de antecedência que alguém não
 * vem é o que faz a fila existir. Uma tela que dificulta o "não" recebe
 * silêncio, e silêncio não abre vaga para ninguém.
 *
 * O verde do confirmar é o único destaque, e ele diz qual é o caminho comum —
 * não qual é o certo.
 */
export function Confirmacao({ token, item }: { token: string; item: ItemDeConfirmacao }) {
  const [r, despachar] = useActionState(responderConfirmacao, INICIAL);

  const jaRespondeu = !esperaResposta(item.ja);
  const respostaAgora = r.estado === "ok" ? r.resposta : null;

  if (respostaAgora || jaRespondeu) {
    const frase =
      respostaAgora === "sim"
        ? "Você confirmou."
        : respostaAgora === "nao"
          ? "Você avisou que não vai."
          : rotuloDaResposta(item.ja);

    return (
      <div className="rounded-cartao border border-linha bg-folha2 px-5 py-4">
        <p className="text-[15px] leading-relaxed text-tinta">{quando(item.inicio)}</p>
        <p className="mt-1.5 text-[13.5px] leading-relaxed text-tinta2">{frase}</p>
        {respostaAgora === "nao" && (
          <p className="mt-2 text-[12.5px] leading-relaxed text-tinta3">
            Ela vai receber o aviso. Se precisar remarcar, é só falar com ela.
          </p>
        )}
      </div>
    );
  }

  return (
    <div className="rounded-cartao border border-linha bg-folha p-5">
      <p className="text-[15px] leading-relaxed text-tinta">{quando(item.inicio)}</p>
      <p className="mt-1 text-[13px] leading-relaxed text-tinta2">
        Você consegue vir nesse horário?
      </p>

      {r.estado === "erro" && (
        <p className="mt-3 rounded-cartao border border-aviso-linha bg-aviso-bg px-3.5 py-2.5 text-[12.5px] leading-relaxed text-aviso">
          {r.mensagem}
        </p>
      )}

      <form action={despachar} className="mt-4 flex gap-2.5">
        <input type="hidden" name="token" value={token} />
        <input type="hidden" name="sessao" value={item.sessao} />
        <Botao rotulo="Sim, eu vou" valor="sim" principal />
        <Botao rotulo="Não vou poder" valor="nao" />
      </form>
    </div>
  );
}
