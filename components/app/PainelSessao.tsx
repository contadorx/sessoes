"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import Link from "next/link";
import type { SessaoLinha, CobrancaLinha } from "@/app/(app)/agenda/dados";
import {
  cancelarSessao,
  marcarSessao,
  perdoarCobranca,
  marcarCobrancaPaga,
  gerarPix,
  type Resultado,
} from "@/app/(app)/agenda/acoes";
import { rotuloPolitica, multaDeFalta } from "@/lib/enquadre";
import { paraCentavos, formatar } from "@/lib/dinheiro";
import { ROTULO_ESTADO } from "./Semana";
import { Remarcar } from "./Remarcar";

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

/**
 * O copia e cola.
 *
 * Um botão que copia, e o código visível abaixo — porque em celular o botão
 * resolve, e no computador nem sempre a área de transferência está disponível.
 * Deixar o texto à mostra é o plano B que não depende de permissão do navegador.
 */
function Pix({ codigo }: { codigo: string }) {
  const [copiado, setCopiado] = useState(false);

  async function copiar() {
    try {
      await navigator.clipboard.writeText(codigo);
      setCopiado(true);
      setTimeout(() => setCopiado(false), 1800);
    } catch {
      // Sem permissão: o código está logo abaixo, dá para selecionar à mão.
    }
  }

  return (
    <div className="mt-3">
      <div className="flex flex-wrap items-center gap-2">
        <button
          type="button"
          onClick={copiar}
          className={`rounded-full border px-4 py-2 text-[12.5px] font-medium transition-colors ${
            copiado
              ? "border-cheia-linha text-cheia"
              : "border-linha2 text-tinta2 hover:bg-folha2"
          }`}
        >
          {copiado ? "copiado" : "Copiar PIX"}
        </button>
        <span className="text-[11.5px] text-tinta3">
          cola no WhatsApp; o valor já vai junto
        </span>
      </div>
      <p className="mt-2 break-all rounded-cartao border border-linha bg-folha px-3 py-2 font-mono text-[10.5px] leading-relaxed text-tinta3">
        {codigo}
      </p>
    </div>
  );
}

/**
 * A cobrança que nasceu sozinha.
 *
 * Duas coisas de desenho, e as duas são sobre postura:
 *
 *  · **o perdão vem antes do "recebi"** na ordem de leitura, porque a régua
 *    automática só é aceitável se o freio estiver à mão. Quem construiu a régua
 *    tem a obrigação de deixar o desvio fácil;
 *  · **a tela diz quando o aviso sai.** Automação em que a pessoa não sabe o
 *    que vai acontecer nem quando é a definição de perder o controle da própria
 *    relação com o paciente.
 */
function Cobranca({ cobranca }: { cobranca: CobrancaLinha }) {
  const [, perdoar] = useActionState(perdoarCobranca, INICIAL);
  const [, pagar] = useActionState(marcarCobrancaPaga, INICIAL);
  const [rPix, gerar] = useActionState(gerarPix, INICIAL);

  const valor = formatar(paraCentavos(cobranca.valor));

  if (cobranca.estado === "perdoada") {
    return (
      <p className="mt-3 rounded-cartao border border-linha bg-folha2 px-4 py-3 text-[12.5px] leading-relaxed text-tinta2">
        Você perdoou os <b className="font-semibold text-tinta">{valor}</b> desta
        sessão. O aviso não saiu.
      </p>
    );
  }

  if (cobranca.estado === "paga") {
    return (
      <p className="mt-3 rounded-cartao border border-cheia-linha bg-cheia-bg px-4 py-3 text-[12.5px] leading-relaxed text-tinta2">
        <b className="font-semibold text-cheia">{valor}</b> recebidos.
      </p>
    );
  }

  return (
    <div className="mt-3 rounded-cartao border border-vaga-linha bg-vaga-bg px-4 py-3">
      <p className="text-[12.5px] leading-relaxed text-tinta2">
        Pelo combinado desta sessão, ficam{" "}
        <b className="font-semibold text-vaga">{valor}</b> a cobrar. O aviso sai
        sozinho daqui a pouco, no texto neutro — você não precisa escrever nada.
      </p>

      {cobranca.pix_copia_cola ? (
        <Pix codigo={cobranca.pix_copia_cola} />
      ) : (
        <form action={gerar} className="mt-3">
          <input type="hidden" name="cobranca_id" value={cobranca.id} />
          <Acao rotulo="Gerar PIX" />
          {rPix.estado === "erro" && (
            <p className="mt-2 text-[12px] leading-relaxed text-vaga">{rPix.erros[0]}</p>
          )}
        </form>
      )}

      <div className="mt-3 flex flex-wrap gap-2">
        <form action={perdoar}>
          <input type="hidden" name="cobranca_id" value={cobranca.id} />
          <Acao rotulo="Não vou cobrar" />
        </form>
        <form action={pagar}>
          <input type="hidden" name="cobranca_id" value={cobranca.id} />
          <Acao rotulo="Já recebi" destaque="cheia" />
        </form>
      </div>

      <p className="mt-2.5 text-[11.5px] leading-relaxed text-tinta3">
        Perdoar segura o aviso, se ele ainda não tiver saído. Fica registrado —
        quantas vezes você abriu mão é uma informação sua, não uma cobrança.
      </p>
    </div>
  );
}

export function PainelSessao({
  sessao,
  cobranca,
  aoFechar,
}: {
  sessao: SessaoLinha;
  cobranca: CobrancaLinha | null;
  aoFechar: () => void;
}) {
  const politica = {
    horas: sessao.politica_horas,
    percentual: sessao.politica_percentual,
  };

  const jaComecou = new Date(sessao.inicio) <= new Date();
  const cancelada = sessao.estado.startsWith("cancelada");
  const terminal = cancelada || sessao.estado === "realizada" || sessao.estado === "falta";

  // Cobrável é o que o banco cobra: cancelamento tardio **e** falta. Não vir é
  // desmarcar com zero hora de antecedência (0022).
  const cobravel = sessao.estado === "cancelada_tarde" || sessao.estado === "falta";

  const multa = cobravel
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

      {cobranca ? (
        <Cobranca cobranca={cobranca} />
      ) : (
        cobravel && (
          <p className="mt-3 rounded-cartao border border-linha bg-folha2 px-4 py-3 text-[12.5px] leading-relaxed text-tinta2">
            {sessao.politica_percentual === 0 ? (
              <>
                O combinado desta sessão não prevê cobrança em cancelamento — nada
                a fazer.
              </>
            ) : (
              <>
                Pelo combinado, seriam{" "}
                <b className="font-semibold text-tinta">{formatar(multa)}</b>. A
                cobrança ainda não apareceu aqui; se não aparecer, é sinal de que
                algo não rodou — vale me avisar.
              </>
            )}
          </p>
        )
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

        {/* Remarcar vem antes de desmarcar na leitura da tela porque é o que
            se quer que aconteça: desmarcar abre buraco, remarcar tapa um. */}
        {!terminal && !jaComecou && (
          <Remarcar
            sessaoId={sessao.id}
            pacienteNome={sessao.pacientes?.nome ?? ""}
            telefone={sessao.pacientes?.telefone ?? null}
          />
        )}

        {terminal && <Marcar id={sessao.id} estado="prevista" rotulo="Desfazer" />}

        {cancelada && new Date(sessao.inicio) > new Date() && (
          <Link
            href={`/fila/${sessao.id}`}
            className="rounded-full bg-vaga px-4 py-2 text-[12.5px] font-semibold text-white transition-opacity hover:opacity-90"
          >
            Oferecer em cascata →
          </Link>
        )}

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
