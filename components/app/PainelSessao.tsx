"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import Link from "next/link";
import type { SessaoLinha } from "@/app/(app)/agenda/dados";
import { cancelarSessao, marcarSessao, type Resultado } from "@/app/(app)/agenda/acoes";
import { rotuloPolitica, multaDeFalta } from "@/lib/enquadre";
import { paraCentavos, formatar } from "@/lib/dinheiro";
import { ROTULO_ESTADO } from "./Semana";

const INICIAL: Resultado = { estado: "inicial" };

const QUANDO = new Intl.DateTimeFormat("pt-BR", {
  timeZone: "America/Sao_Paulo",
  weekday: "long",
  day: "numeric",
  month: "long",
  hour: "2-digit",
  minute: "2-digit",
});

function Acao({ rotulo, destaque }: { rotulo: string; destaque?: "vaga" | "cheia" }) {
  const { pending } = useFormStatus();

  const cor =
    destaque === "vaga"
      ? "border-vaga-linha text-vaga hover:bg-vaga-bg"
      : destaque === "cheia"
        ? "border-cheia-linha text-cheia hover:bg-cheia-bg"
        : "border-linha2 text-tinta2 hover:bg-folha2";

  return (
    <button
      type="submit"
      disabled={pending}
      className={`rounded-full border px-4 py-2 text-[12.5px] font-medium transition-colors disabled:opacity-45 ${cor}`}
    >
      {pending ? "…" : rotulo}
    </button>
  );
}

function Marcar({ id, estado, rotulo, destaque }: {
  id: string;
  estado: string;
  rotulo: string;
  destaque?: "vaga" | "cheia";
}) {
  const [, despachar] = useActionState(marcarSessao, INICIAL);
  return (
    <form action={despachar}>
      <input type="hidden" name="id" value={id} />
      <input type="hidden" name="estado" value={estado} />
      <Acao rotulo={rotulo} destaque={destaque} />
    </form>
  );
}

function Cancelar({ id, por, rotulo }: { id: string; por: string; rotulo: string }) {
  const [, despachar] = useActionState(cancelarSessao, INICIAL);
  return (
    <form action={despachar}>
      <input type="hidden" name="id" value={id} />
      <input type="hidden" name="por" value={por} />
      <Acao rotulo={rotulo} destaque="vaga" />
    </form>
  );
}

export function PainelSessao({
  sessao,
  aoFechar,
}: {
  sessao: SessaoLinha;
  aoFechar: () => void;
}) {
  const politica = {
    horas: sessao.politica_horas,
    percentual: sessao.politica_percentual,
  };

  const jaComecou = new Date(sessao.inicio) <= new Date();
  const cancelada = sessao.estado.startsWith("cancelada");
  const terminal = cancelada || sessao.estado === "realizada" || sessao.estado === "falta";

  const multa =
    sessao.estado === "cancelada_tarde"
      ? multaDeFalta(paraCentavos(sessao.valor), "cancelada_tarde", politica)
      : 0;

  return (
    <div className="rounded-cartao border border-linha bg-folha p-5">
      <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <span className="font-serif text-[19px] text-tinta">
          {sessao.pacientes?.nome ?? "—"}
        </span>
        <span className="text-[12.5px] text-tinta3">{QUANDO.format(new Date(sessao.inicio))}</span>
        <span className="rounded-full border border-linha bg-folha2 px-2 py-0.5 text-[10.5px] font-semibold uppercase tracking-wider text-tinta3">
          {ROTULO_ESTADO[sessao.estado]}
        </span>
        <button
          type="button"
          onClick={aoFechar}
          className="ml-auto text-[12px] text-tinta3 hover:text-tinta2"
        >
          fechar
        </button>
      </div>

      <p className="mt-2 text-[12.5px] text-tinta2">
        {formatar(paraCentavos(sessao.valor))} · {rotuloPolitica(politica)}
      </p>

      {sessao.estado === "cancelada_tarde" && (
        <p className="mt-3 rounded-cartao border border-vaga-linha bg-vaga-bg px-4 py-3 text-[12.5px] leading-relaxed text-tinta2">
          Cancelamento tardio pelo combinado desta sessão:{" "}
          <b className="font-semibold text-vaga">{formatar(multa)}</b> a cobrar. Por
          enquanto fica o registro — a cobrança sai sozinha quando o financeiro
          entrar.
        </p>
      )}

      {sessao.estado === "cancelada_cedo" && (
        <p className="mt-3 rounded-cartao border border-linha bg-folha2 px-4 py-3 text-[12.5px] leading-relaxed text-tinta2">
          Avisou dentro do prazo — nada a cobrar. O horário está livre.
        </p>
      )}

      <div className="mt-4 flex flex-wrap gap-2">
        {!terminal && (
          <>
            {sessao.estado === "prevista" && (
              <Marcar id={sessao.id} estado="confirmada" rotulo="Confirmar" />
            )}
            {jaComecou && (
              <>
                <Marcar id={sessao.id} estado="realizada" rotulo="Aconteceu" destaque="cheia" />
                <Marcar id={sessao.id} estado="falta" rotulo="Não veio" />
              </>
            )}
            <Cancelar id={sessao.id} por="paciente" rotulo="Paciente desmarcou" />
            <Cancelar id={sessao.id} por="profissional" rotulo="Eu desmarquei" />
          </>
        )}

        {terminal && <Marcar id={sessao.id} estado="prevista" rotulo="Desfazer" />}

        {sessao.pacientes && (
          <Link
            href={`/pacientes/${sessao.pacientes.id}`}
            className="rounded-full border border-linha2 px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2"
          >
            Ver cadastro
          </Link>
        )}
      </div>

      {!terminal && !jaComecou && (
        <p className="mt-3 text-[11.5px] leading-relaxed text-tinta3">
          Quem decide se o cancelamento foi cedo ou tarde é o servidor, comparando
          o relógio dele com a política gravada nesta sessão. Não há como escolher
          a classificação daqui.
        </p>
      )}
    </div>
  );
}
