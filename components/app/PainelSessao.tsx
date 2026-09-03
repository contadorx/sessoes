"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import Link from "next/link";
import type { SessaoLinha, CobrancaLinha } from "@/app/(app)/agenda/dados";
import { podeClinico, podeFinanceiro, type Acessos } from "@/lib/permissao";
import {
  cancelarSessao,
  marcarSessao,
  perdoarCobranca,
  marcarCobrancaPaga,
  gerarPix,
  type Resultado,
} from "@/app/(app)/agenda/acoes";
import { SeloDaConfirmacao } from "@/components/app/Confirmacoes";
import { rotuloPolitica, multaDeFalta } from "@/lib/enquadre";
import { paraCentavos, formatar } from "@/lib/dinheiro";
import { ROTULO_ESTADO } from "./Semana";
import { podeAnotar } from "@/lib/ausencias";
import { Evolucao } from "./Registro";
import { diaEmSP } from "@/lib/tempo";
import { anotarAusencia, type Resultado as ResultadoPaciente } from "@/app/(app)/pacientes/acoes";
import { Remarcar } from "./Remarcar";
import {
  registrarRecebimento,
  desfazerRecebimento,
  type Resultado as ResultadoFinanceiro,
} from "@/app/(app)/recebimentos/movimentacoes/acoes";

const INICIAL: Resultado = { estado: "inicial" };
const INICIAL_FIN: ResultadoFinanceiro = { estado: "inicial" };
const INICIAL_PAC: ResultadoPaciente = { estado: "inicial" };

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
      className={`min-h-11 rounded-full border px-4 py-2 text-[12.5px] font-medium transition-colors disabled:opacity-45 ${cor}`}
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

/**
 * Desmarcar, em duas etapas.
 *
 * Os cinco botões desta fileira — Confirmar · Aconteceu · Não veio · Paciente
 * desmarcou · Eu desmarquei — ficavam num `flex flex-wrap gap-2`, alvos de
 * ~35 px a 8 px um do outro, e **qualquer um deles acontecia no primeiro
 * toque**. Não há `confirm`, `window.confirm` nem `<dialog>` em lugar nenhum
 * do repositório; nunca houve segunda etapa aqui.
 *
 * O que um toque errado faz: desmarcar cancela a sessão e abre a vaga, e "Não
 * veio" leva a sessão para `falta`, que é cobrável e dispara a proposta de
 * multa. Ela faz isso de pé, com o polegar, entre uma sessão e outra.
 *
 * O padrão é o que `components/app/Privacidade.tsx` já usa: estado
 * `confirmando` no próprio componente. Nada de diálogo nativo — o produto não
 * usa nenhum, e não é aqui que ele vai começar.
 *
 * E a saída tem o mesmo peso da ação. Nas duas confirmações que já existiam, o
 * "deixa" era o elemento de menor contraste da fileira: quem se arrependeu
 * precisa achar a saída mais rápido do que achou a entrada.
 */
function Cancelar({ id, por, rotulo }: { id: string; por: string; rotulo: string }) {
  const [, despachar] = useActionState(cancelarSessao, INICIAL);
  const [confirmando, setConfirmando] = useState(false);

  if (!confirmando) {
    return (
      <button
        type="button"
        onClick={() => setConfirmando(true)}
        className="min-h-11 rounded-full border border-vaga-linha px-4 py-2 text-[12.5px] font-medium text-vaga transition-colors hover:bg-vaga-bg"
      >
        {rotulo}
      </button>
    );
  }

  return (
    <form action={despachar} className="flex flex-wrap items-center gap-2">
      <input type="hidden" name="id" value={id} />
      <input type="hidden" name="por" value={por} />
      <span className="text-[12.5px] text-tinta2">Desmarcar esta sessão?</span>
      <Acao rotulo="Sim, desmarcar" destaque="vaga" />
      <button
        type="button"
        onClick={() => setConfirmando(false)}
        className="min-h-11 rounded-full border border-linha2 px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2"
      >
        deixa
      </button>
    </form>
  );
}

/**
 * "Recebi" (B23).
 *
 * Aparece na hora em que a pessoa acabou de sair da sala e o dinheiro trocou de
 * mão — que é quando ela lembra. Registrar aqui é o que permite emitir recibo
 * depois: desde a 0037, recibo só sai sobre dinheiro que entrou.
 */
// `hojeSP` desce do servidor (`hoje()` em `lib/tempo-servidor`), e não do
// relógio do navegador: a lei 3 diz que "dia" se calcula em America/Sao_Paulo,
// e um `toISOString()` às 21h daria o dia seguinte.
function Recebi({ id, hojeSP }: { id: string; hojeSP: string }) {
  const [r, despachar] = useActionState(registrarRecebimento, INICIAL_FIN);
  return (
    <div className="mt-3 rounded-cartao border border-cheia-linha bg-cheia-bg px-4 py-3">
      <p className="text-[12.5px] leading-relaxed text-tinta2">
        A hora aconteceu. Recebeu por ela?{" "}
        <span className="text-tinta3">
          Sem esse registro o recibo não sai — e o mês fica com uma hora sem entrada.
        </span>
      </p>
      {/*
        A data é opcional, e existe para o Pix que caiu três dias depois.

        Vazia, o recebimento entra hoje — o regime de caixa que o resto do
        produto usa, e a mesma data que o botão do Financeiro grava. Antes esta
        tela não mandava nada e a outra mandava o dia da **sessão**: o mesmo
        botão, em duas telas, punha o dinheiro em meses diferentes na virada do
        mês, e o mês é o que vai para o contador.
      */}
      <form action={despachar} className="mt-2 flex flex-wrap items-end gap-2">
        <input type="hidden" name="sessao" value={id} />
        <label className="text-[11.5px] text-tinta3">
          <span className="block">quando entrou</span>
          <input
            type="date"
            name="quando"
            max={hojeSP}
            defaultValue=""
            className="mt-0.5 rounded-[5px] border border-linha2 bg-folha px-2 py-1 text-[12.5px] text-tinta"
          />
        </label>
        <Acao rotulo="Recebi" destaque="cheia" />
      </form>
      <p className="mt-1 text-[11px] leading-relaxed text-tinta3">
        Em branco, entra hoje.
      </p>
      {r.estado === "ok" && (
        <p className="mt-2 text-[12.5px] leading-relaxed text-cheia">{r.mensagem}</p>
      )}
      {r.estado === "erro" && (
        <p className="mt-2 text-[12.5px] leading-relaxed text-vaga">{r.erros[0]}</p>
      )}
    </div>
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
 * A cobrança que **ela** decidiu.
 *
 * O título deste bloco era "a cobrança que nasceu sozinha", e era verdade até a
 * 0058. O P4 tirou a decisão do software: a multa passa pela caixa de decisões
 * na agenda, e o que chega aqui já foi decidido por ela — ou é a cobrança de
 * uma sessão que aconteceu, que segue automática porque hora prestada é preço
 * combinado, e não juízo sobre o motivo de ninguém.
 *
 * Duas coisas de desenho sobreviveram inteiras, e as duas são sobre postura:
 *
 *  · **o perdão vem antes do "recebi"** na ordem de leitura. Vale mesmo depois
 *    da decisão: a pessoa pode ligar amanhã, e desistir de cobrar tem de
 *    continuar sendo um toque;
 *  · **a tela diz quando o aviso sai.** Automação em que a pessoa não sabe o
 *    que vai acontecer nem quando é a definição de perder o controle da própria
 *    relação com o paciente.
 */
function Cobranca({ cobranca }: { cobranca: CobrancaLinha }) {
  const [, perdoar] = useActionState(perdoarCobranca, INICIAL);
  const [, pagar] = useActionState(marcarCobrancaPaga, INICIAL);
  const [rPix, gerar] = useActionState(gerarPix, INICIAL);
  const [rDesfazer, desfazer] = useActionState(desfazerRecebimento, INICIAL_FIN);
  const [desfazendo, setDesfazendo] = useState(false);

  const valor = formatar(paraCentavos(cobranca.valor));

  if (cobranca.estado === "perdoada") {
    return (
      <p className="mt-3 rounded-cartao border border-linha bg-folha2 px-4 py-3 text-[12.5px] leading-relaxed text-tinta2">
        Você decidiu não cobrar os <b className="font-semibold text-tinta">{valor}</b>{" "}
        desta sessão. Ninguém recebeu mensagem nenhuma.
      </p>
    );
  }

  if (cobranca.estado === "paga") {
    return (
      <div className="mt-3 rounded-cartao border border-cheia-linha bg-cheia-bg px-4 py-3">
        <p className="text-[12.5px] leading-relaxed text-tinta2">
          <b className="font-semibold text-cheia">{valor}</b> recebidos.
        </p>
        {/* Desfazer existe porque um clique errado num painel de dinheiro vira
            recibo errado — e recibo errado leva o nome dela.

            E ele acontecia no primeiro toque, calado. A ação devolve **dois
            desfechos materialmente diferentes** — "a cobrança voltou a ficar em
            aberto" e "nada foi cobrado de ninguém, o registro só saiu do caixa"
            —, e nenhum dos dois chegava aqui: o componente só desenhava o erro.
            Pior: assim que dá certo, o estado da cobrança muda e este bloco
            inteiro deixa de existir, então a frase de sucesso **não tem onde
            aparecer**. A informação tem de vir antes, e é o que a segunda etapa
            faz — é o mesmo padrão de `Cancelar`, aqui em cima. */}
        {cobranca.motivo === "sessao_realizada" && cobranca.sessao_id && (
          <div className="mt-2">
            {!desfazendo ? (
              <button
                type="button"
                onClick={() => setDesfazendo(true)}
                className="toque text-[12.5px] text-tinta3 underline underline-offset-2 hover:text-tinta2"
              >
                não recebi ainda
              </button>
            ) : (
              <form action={desfazer}>
                <input type="hidden" name="sessao" value={cobranca.sessao_id} />
                <p className="text-[12.5px] leading-relaxed text-tinta2">
                  Os {valor} saem do caixa e a cobrança volta a ficar em aberto. O
                  recibo emitido, se houver, não é cancelado por aqui.
                </p>
                <div className="mt-2 flex flex-wrap items-center gap-2">
                  <Acao rotulo="Sim, tirar do caixa" destaque="vaga" />
                  <button
                    type="button"
                    onClick={() => setDesfazendo(false)}
                    className="min-h-11 rounded-full border border-linha2 px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2"
                  >
                    deixa
                  </button>
                </div>
              </form>
            )}
            {rDesfazer.estado === "erro" && (
              <p className="mt-2 text-[12px] leading-relaxed text-vaga">{rDesfazer.erros[0]}</p>
            )}
            {rDesfazer.estado === "ok" && (
              <p className="mt-2 text-[12px] leading-relaxed text-cheia">{rDesfazer.mensagem}</p>
            )}
          </div>
        )}
      </div>
    );
  }

  return (
    <div className="mt-3 rounded-cartao border border-vaga-linha bg-vaga-bg px-4 py-3">
      <p className="text-[12.5px] leading-relaxed text-tinta2">
        {cobranca.motivo === "sessao_realizada" || cobranca.motivo === "avulsa" ? (
          <>
            Ficam <b className="font-semibold text-vaga">{valor}</b> a receber por
            esta sessão.
          </>
        ) : (
          <>
            Você decidiu cobrar <b className="font-semibold text-vaga">{valor}</b>{" "}
            desta sessão. O aviso sai no texto neutro — você não precisa escrever
            nada.
          </>
        )}
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
        Mudar de ideia segura o aviso, se ele ainda não tiver saído. Fica
        registrado — quantas vezes você abriu mão é uma informação sua, não uma
        cobrança.
      </p>
    </div>
  );
}

/**
 * A nota da hora que não houve (PR8, B27).
 *
 * Mora **aqui**, e não só na ficha, porque este é o instante em que ela sabe o
 * motivo: acabou de marcar "não veio", a conversa de ontem ainda está fresca.
 * Empurrar isso para uma segunda tela é garantir que a maior parte nunca seja
 * escrita — e o que a PR8 tem de diferente é justamente ter o que ler depois.
 *
 * Nasce fechada. Uma caixa aberta em toda falta pede preenchimento; o que se
 * quer é o contrário.
 */
function NotaDaAusencia({ id, nota }: { id: string; nota: string | null }) {
  const [r, anotar] = useActionState(anotarAusencia, INICIAL_PAC);
  const [aberta, setAberta] = useState(Boolean(nota));

  if (!aberta) {
    return (
      <button
        type="button"
        onClick={() => setAberta(true)}
        className="mt-3 text-[12px] text-tinta3 hover:text-vaga"
      >
        + escrever o que houve
      </button>
    );
  }

  return (
    <form action={anotar} className="mt-3">
      <input type="hidden" name="sessao_id" value={id} />
      <label htmlFor={`nota-${id}`} className="text-[12px] font-medium text-tinta2">
        O que houve com esta hora
      </label>
      <textarea
        id={`nota-${id}`}
        name="nota"
        rows={3}
        maxLength={2000}
        defaultValue={nota ?? ""}
        className="mt-1 w-full rounded-cartao border border-linha2 bg-folha px-3 py-2 text-[13px] leading-relaxed text-tinta focus:border-tinta3 focus:outline-none"
      />
      <div className="mt-2 flex flex-wrap items-center gap-3">
        <Acao rotulo="Guardar" />
        <span className="text-[11px] text-tinta3">
          Fica na ficha dela, e não sai em recibo, mensagem nem pasta do contador.
        </span>
      </div>
      {r.estado === "ok" && (
        <p className="mt-1 text-[12px] text-cheia">{r.mensagem}</p>
      )}
      {r.estado === "erro" &&
        r.erros.map((e, i) => (
          <p key={i} className="mt-1 text-[12px] leading-relaxed text-vaga">
            {e}
          </p>
        ))}
    </form>
  );
}

export function PainelSessao({
  sessao,
  cobranca,
  aoFechar,
  hoje,
  acessos,
}: {
  sessao: SessaoLinha;
  cobranca: CobrancaLinha | null;
  aoFechar: () => void;
  hoje: string;
  /**
   * Quem está olhando este painel.
   *
   * Ele era o mesmo para todo mundo que abre a agenda, e isso era um convite
   * que o banco recusa. Uma **secretária** — que por padrão não tem acesso
   * clínico nem financeiro — marcava "Aconteceu" e recebia, ali mesmo, uma
   * caixa de evolução **já aberta**, com "Guarda de cinco anos: o que entra
   * aqui não se apaga" embaixo, e o bloco "Recebi". As duas escritas são
   * recusadas pela RLS (`le_clinico()` e `ve_financeiro()`, migração 0049).
   *
   * As abas do paciente já faziam certo (`SemAcessoClinico` no prontuário e na
   * anamnese); o painel da agenda tinha ficado de fora. E `lib/permissao.ts` já
   * dizia a frase: *"oferecer e depois recusar é pior do que não oferecer"*.
   * Aqui era pior que oferecer — era convidar quem não pode ler prontuário a
   * escrever num.
   *
   * O que **não** muda: "Aconteceu" continua à vista para todo mundo. Marcar
   * uma sessão como realizada é fato administrativo, e é o que a secretária
   * existe para fazer — tirar isso devolveria o trabalho para a psicóloga, que
   * é o oposto do produto inteiro.
   */
  acessos: Acessos;
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

      {/* A confirmação, quando existe. Ela aparece **acima** da cobrança de
          propósito: quem avisou que não vem precisa ver o custo antes de o
          botão de cancelar estar ao alcance da mão. */}
      <SeloDaConfirmacao eixo={sessao.eixo_confirmacao} />

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
                {/* **Mudou com o P4 (0058).** Este texto dizia que a cobrança
                    "ainda não apareceu" e que, se não aparecesse, algo não
                    tinha rodado. Agora este é o estado normal: a cobrança não
                    nasce sozinha, e a pergunta está esperando você no alto da
                    agenda. Deixar o texto antigo seria o produto chamando de
                    defeito o comportamento que ele acabou de escolher. */}
                Pelo combinado, seriam{" "}
                <b className="font-semibold text-tinta">{formatar(multa)}</b> — e
                nada é cobrado até você decidir. A pergunta está em{" "}
                <b className="font-medium text-tinta">A decidir</b>, no alto da
                agenda.
              </>
            )}
          </p>
        )
      )}

      {sessao.estado === "realizada" && !cobranca && podeFinanceiro(acessos) && (
        <Recebi id={sessao.id} hojeSP={hoje} />
      )}

      {sessao.estado === "cancelada_cedo" && (
        <p className="mt-3 rounded-cartao border border-linha bg-folha2 px-4 py-3 text-[12.5px] leading-relaxed text-tinta2">
          Avisou dentro do prazo — nada a cobrar. O horário está livre.
        </p>
      )}

      {podeAnotar(sessao.estado) && (
        <NotaDaAusencia id={sessao.id} nota={sessao.nota} />
      )}

      {/* A evolução mora aqui pelo mesmo motivo que a nota da B27: é agora que
          ela lembra. Empurrar para a ficha é garantir que a maior parte nunca
          seja escrita — e o registro que não existe é o que falta na fiscalização. */}
      {sessao.estado === "realizada" && podeClinico(acessos) && (
        <div className="mt-4">
          <Evolucao
            sessaoId={sessao.id}
            // `toISOString` daria o dia em UTC: a sessão das 21h viraria a do dia
            // seguinte. O dia de uma sessão é o dia em São Paulo, sempre (lei da B1).
            dia={diaEmSP(new Date(sessao.inicio))}
            texto={null}
            camada="prontuario"
            comecaAberta
          />
        </div>
      )}

      {/*
        A fileira virou três grupos, e a separação é a build.

        "Aconteceu" e "Não veio" eram vizinhos a 8 px, com consequências
        opostas: um fecha a hora, o outro leva a sessão para `falta`, que é
        cobrável e dispara a proposta de multa. Agora eles ficam em blocos
        separados por uma linha, e desmarcar — que abre a vaga — fica no
        terceiro, longe dos dois.
      */}
      <div className="mt-4 flex flex-col gap-3">
        {!terminal && (
          <>
            {sessao.estado === "prevista" && (
              <div className="flex flex-wrap gap-2">
                <Marcar id={sessao.id} estado="confirmada" rotulo="Confirmar" />
              </div>
            )}
            {jaComecou && (
              <div className="flex flex-wrap items-center gap-2 border-t border-linha pt-3">
                <Marcar id={sessao.id} estado="realizada" rotulo="Aconteceu" destaque="cheia" />
                <span className="text-[11.5px] text-tinta3">ou</span>
                <Marcar id={sessao.id} estado="falta" rotulo="Não veio" />
              </div>
            )}
            <div className="flex flex-wrap gap-2 border-t border-linha pt-3">
              <Cancelar id={sessao.id} por="paciente" rotulo="Paciente desmarcou" />
              <Cancelar id={sessao.id} por="profissional" rotulo="Eu desmarquei" />
            </div>
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
            href={`/encaixes/${sessao.id}`}
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
