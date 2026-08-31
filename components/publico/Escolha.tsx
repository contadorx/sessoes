"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import { escolher, type ResultadoEscolha } from "@/app/p/remarcar/[token]/acoes";
import { quando, type Opcao } from "@/lib/remarcacao";

const INICIAL: ResultadoEscolha = { estado: "inicial" };

function Escolher({ rotulo }: { rotulo: string }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="w-full rounded-cartao border border-linha2 bg-folha px-4 py-3.5 text-left text-[15px] text-tinta transition-colors hover:border-tinta3 hover:bg-folha2 disabled:opacity-45"
    >
      {pending ? "confirmando…" : rotulo}
    </button>
  );
}

/**
 * Os dois ou três horários, e nada mais.
 *
 * O que **não** está aqui é a decisão de desenho: não há calendário, não há
 * campo de data, não há "sugerir outro horário". Uma tela que aceita qualquer
 * hora devolve a negociação para o WhatsApp, que é de onde a D11 existe para
 * tirá-la — e o motivo pelo qual cada hora está na lista é informação sobre a
 * agenda de outras pessoas, e fica do lado de lá.
 */
export function Escolha({ token, opcoes }: { token: string; opcoes: Opcao[] }) {
  const [r, despachar] = useActionState(escolher, INICIAL);

  const livres = opcoes.filter((o) => o.livre);

  if (r.estado === "ok") {
    return (
      <div className="mt-8 rounded-cartao border border-cheia-linha bg-cheia-bg px-5 py-4">
        <p className="text-[15px] leading-relaxed text-cheia">
          Pronto. Ficou <b className="font-semibold">{quando(r.inicio)}</b>.
        </p>
        <p className="mt-2 text-[12.5px] leading-relaxed text-tinta2">
          Você pode fechar esta página. Se precisar mudar de novo, é só falar com
          quem te enviou o link.
        </p>
      </div>
    );
  }

  if (livres.length === 0) {
    return (
      <div className="mt-8 rounded-cartao border border-linha bg-folha2 px-5 py-4">
        <p className="text-[14px] leading-relaxed text-tinta2">
          Os horários desta lista já foram preenchidos. Fale com quem te enviou o
          link — ela pode te mandar outra lista em um toque.
        </p>
      </div>
    );
  }

  return (
    <div className="mt-8">
      <ul className="space-y-2.5">
        {livres.map((o) => (
          <li key={o.inicio}>
            <form action={despachar}>
              <input type="hidden" name="token" value={token} />
              <input type="hidden" name="inicio" value={o.inicio} />
              <Escolher rotulo={quando(o.inicio)} />
            </form>
          </li>
        ))}
      </ul>

      {r.estado === "erro" && (
        <p className="mt-3 text-[13px] leading-relaxed text-vaga">{r.mensagem}</p>
      )}

      <p className="mt-5 text-[11.5px] leading-relaxed text-tinta3">
        Escolher aqui já troca o horário — não precisa confirmar por mensagem
        depois. Se nenhum servir, responda a quem te enviou.
      </p>
    </div>
  );
}
