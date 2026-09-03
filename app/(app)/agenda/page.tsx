import Link from "next/link";
import { formatar } from "@/lib/dinheiro";
import { sessaoAtual } from "@/lib/conta";
import {
  sessoesDaSemana,
  respostaDasConfirmacoes,
  resumoDaSemana,
  listarAusencias,
  horizonte,
  pacientesParaEncaixe,
  cobrancasDaSemana,
  retornoDoMes,
  decisoesPendentes,
  naSuaMao,
  resumoDoEnvioManual,
  cockpitDoMes,
  alertasARever,
} from "./dados";
import { Semana } from "@/components/app/Semana";
import { Retorno } from "@/components/app/Retorno";
import { Ausencias } from "@/components/app/Ausencias";
import { Encaixe } from "@/components/app/Encaixe";
import { semanaDe, rotuloSemana, somarDias } from "@/lib/semana";
import { hoje } from "@/lib/tempo-servidor";
import { FaixaDeConfirmacoes, NumerosDaConfirmacao } from "@/components/app/Confirmacoes";
import { CaixaDeDecisoes } from "@/components/app/Decisoes";
import { CaixaNaSuaMao } from "@/components/app/NaSuaMao";
import { adaptadorPara } from "@/lib/mensageria/adaptadores";
import { Cockpit } from "@/components/app/Cockpit";
import { acessosDa } from "@/lib/conta";
import { prazosDoMes } from "@/app/(app)/prazos";
import { pendencias, fraseDasPendencias } from "@/lib/navegacao";
import { FaixaDePendencias } from "@/components/app/Navegacao";
import { estadoInicial } from "@/app/(app)/comecar/page";

export const metadata = { title: "Agenda" };

// O dinheiro da agenda era arredondado para real inteiro, e só aqui: todo o
// resto do produto usa `formatar` sobre centavos. Duas formatações de dinheiro
// divergem — a daqui dizia R$ 1.200 onde a de `/recebimentos` dizia
// R$ 1.199,50, e não havia como saber qual era a certa.

export default async function Agenda({
  searchParams,
}: {
  searchParams: Promise<{ semana?: string }>;
}) {
  const { semana: pedida } = await searchParams;
  const hojeStr = hoje();

  const referencia = /^\d{4}-\d{2}-\d{2}$/.test(pedida ?? "") ? pedida! : hojeStr;
  const semana = semanaDe(referencia);

  const [sessao, sessoes, ausencias, ate, pacientes, retorno, prazos, comeco, confirmacoes, decisoes,
         naMao, resumoManual] =
    await Promise.all([
      sessaoAtual(),
      sessoesDaSemana(semana.inicio),
      listarAusencias(),
      horizonte(),
      pacientesParaEncaixe(),
      retornoDoMes(hojeStr),
      // Os prazos que viraram faixa em vez de item de menu — ver `prazos.ts`.
      prazosDoMes(),
      estadoInicial(),
      // Os dois números do P3. Degradam para `null` sem derrubar a agenda —
      // instrumento de medição não pode quebrar a tela que ele mede.
      respostaDasConfirmacoes(hojeStr),
      // As multas esperando decisão (P4). Some sozinha quando não há nenhuma —
      // e, numa conta sem falta nenhuma, é o estado permanente.
      decisoesPendentes(),
      // O que espera o dedo dela (OP9). As duas degradam sozinhas: a caixa é
      // conveniência, e uma agenda que não abre porque a caixa falhou seria a
      // inversão exata da prioridade.
      naSuaMao(),
      resumoDoEnvioManual(),
    ]);

  // O cockpit do mês (P5). Depende do profissional, então vem depois da sessão
  // — e degrada para `null` sem derrubar a agenda.
  const primeiro = hojeStr.slice(0, 8) + "01";
  const ultimo = (() => {
    const d = new Date(`${primeiro}T12:00:00Z`);
    d.setUTCMonth(d.getUTCMonth() + 1);
    d.setUTCDate(0);
    return d.toISOString().slice(0, 10);
  })();

  const [cockpit, alertas] = await Promise.all([
    cockpitDoMes(sessao.profissionalId, primeiro, ultimo),
    alertasARever(sessao.profissionalId),
  ]);

  // Depois das sessões, porque depende delas — e só busca se houver alguma
  // sessão cobrável na semana.
  const cobrancas = await cobrancasDaSemana(sessoes);

  const resumo = resumoDaSemana(sessoes);
  const ehSemanaAtual = semana.inicio === semanaDe(hojeStr).inicio;

  const acessos = acessosDa(sessao);
  const abertas = pendencias(prazos, acessos);

  // O "Começar" era um item de menu que sumia sozinho — e some ainda, mas
  // agora daqui, que é onde ela já está. Item de navegação para uma lista de
  // três tarefas que se fazem uma vez é entulho permanente por um trabalho
  // temporário.
  const comecando =
    comeco.pacientes === 0 || comeco.na_fila === 0 || comeco.vagas_abertas === 0;

  return (
    <div>
      <div className="flex flex-wrap items-baseline justify-between gap-3">
        <h1 className="font-serif text-[28px] leading-tight tracking-[-0.015em]">
          {sessao.nome ? `Boa, ${sessao.nome.split(" ")[0]}.` : "Sua semana"}
        </h1>

        <nav className="flex items-center gap-1">
          <Semaninha para={somarDias(semana.inicio, -7)} rotulo="←" />
          <span className="min-w-[13rem] px-2 text-center text-[13px] text-tinta2">
            {rotuloSemana(semana)}
          </span>
          <Semaninha para={somarDias(semana.inicio, 7)} rotulo="→" />
          {/* **Hoje é persistente.** Antes ele só aparecia quando ela já
              estava perdida em outra semana — e voltar era o problema mais
              comum da tela que ela abre todo dia. Um botão que aparece só
              quando o erro já aconteceu é um botão que ela não sabe que
              existe. */}
          <Link
            href="/agenda"
            aria-current={ehSemanaAtual ? "page" : undefined}
            className={`ml-2 rounded-full px-3 py-1 text-[12.5px] font-medium transition-colors ${
              ehSemanaAtual
                ? "border border-linha text-tinta3"
                : "border border-vaga-linha text-vaga hover:bg-vaga-bg"
            }`}
          >
            Hoje
          </Link>
        </nav>
      </div>

      {/* Os prazos que vencem. Some sozinha quando não há nenhum — é a troca
          por "Receita" e "Contador" terem sido itens fixos de menu o ano
          inteiro, que é como um alarme vira paisagem. */}
      <div className="mt-5">
        <FaixaDePendencias itens={abertas} frase={fraseDasPendencias(abertas)} />
      </div>

      {comecando && (
        <Link
          href="/comecar"
          className="mt-5 flex flex-wrap items-baseline gap-x-2 rounded-cartao border border-vaga-linha bg-vaga-bg px-4 py-2.5 text-[13px] text-tinta2 transition-opacity hover:opacity-90"
        >
          <b className="font-medium text-vaga">Terminar de configurar</b>
          <span className="text-[12.5px]">
            faltam os pacientes, a fila e o primeiro horário — três passos, uma vez só
          </span>
        </Link>
      )}

      {/*
        A ordem desta tela, e por que ela é esta.

        Ela abre o app **entre uma sessão e outra**, de pé, para ver quem vem às
        15h. Antes desta build vinham dez números de dinheiro e de ocupação
        antes do primeiro nome de paciente — em 375 px, dois polegares de
        rolagem até a agenda. O produto compete com o caderno, e perdia essa
        comparação por rolagem.

        A regra da ordem é uma só: **o que exige decisão hoje vem antes da
        grade; o que descreve o mês vem depois.** Nada foi escondido, nada virou
        aba — aba é onde métrica morre, e o P5 tem razão escrita sobre isso. O
        cockpit continua na primeira tela; ele só deixou de vir antes da agenda.
      */}

      {/* A caixa de decisões vem antes de tudo o que é rotina do dia, e é
          deliberado: **enquanto ela não decidir, nada é cobrado.** Uma pergunta
          que o sistema faz e esconde numa aba é uma cobrança que nunca sai — e
          o P4 trocou o silêncio-que-cobra pelo silêncio-que-não-cobra, o que só
          é honesto se a pergunta estiver à vista. */}
      <div className="mt-6">
        <CaixaDeDecisoes decisoes={decisoes} />
      </div>

      {/* A caixa do que está na mão dela (OP9) vem logo depois das decisões, e
          pela mesma razão: é trabalho que só acontece se ela vir. No plano
          Grátis a fila e a cobrança saem do WhatsApp dela, com um toque — e uma
          oferta que ela não mandou **segura a vaga**, porque o prazo da paciente
          só começa quando alguém é convidado. Escondida numa aba, essa caixa
          seria uma fila parada sem motivo aparente. */}
      <div className="mt-6">
        <CaixaNaSuaMao
          mensagens={naMao}
          resumo={resumoManual}
          envioAutomatico={adaptadorPara("whatsapp").disponivel}
        />
      </div>

      {/* A faixa da confirmação vem **antes** da semana porque ela é sobre
          hoje, e some sozinha quando ninguém foi perguntado. */}
      {ehSemanaAtual && (
        <div className="mt-6">
          <FaixaDeConfirmacoes
            sessoes={sessoes.filter(
              (x) => x.inicio.slice(0, 10) === hojeStr && x.estado !== "cancelada_cedo" && x.estado !== "cancelada_tarde",
            )}
          />
        </div>
      )}

      {ehSemanaAtual && (
        <div className="mt-4">
          <NumerosDaConfirmacao bruta={confirmacoes} />
        </div>
      )}

      <div className="mt-6">
        <Semana
          semana={semana}
          sessoes={sessoes}
          cobrancas={cobrancas}
          hoje={hojeStr}
          acessos={acessos}
        />
      </div>

      {/* a faixa de números */}
      <dl className="mt-5 grid grid-cols-2 gap-px overflow-hidden rounded-cartao border border-linha bg-linha lg:grid-cols-4">
        <Numero rotulo="sessões na semana" valor={String(resumo.vivas)} />
        <Numero
          rotulo="previsto"
          valor={formatar(resumo.previsto)}
          cor="text-cheia"
          href="/recebimentos"
        />
        <Numero
          rotulo={resumo.canceladasTarde === 1 ? "cancelou tarde" : "cancelaram tarde"}
          valor={String(resumo.canceladasTarde)}
          cor={resumo.canceladasTarde > 0 ? "text-aviso" : undefined}
        />
        <Numero
          rotulo="hora vazia"
          valor={formatar(resumo.perdido)}
          cor={resumo.perdido > 0 ? "text-vaga" : undefined}
          href="/encaixes"
          nota={
            resumo.perdido > 0
              ? "horário que abriu e ninguém ocupou — é este buraco que a fila existe para preencher"
              : "nenhum horário aberto nesta semana"
          }
        />
      </dl>

      {/* O cockpit do mês (P5), na primeira tela e não numa aba de relatórios.
          É o critério de pronto do bloco 4 do doc 30, e é o mesmo argumento dos
          dois números do P3: uma métrica que mora onde ninguém abre é uma
          métrica que não muda decisão nenhuma. */}
      {ehSemanaAtual && (
        <div className="mt-6">
          <Cockpit bruto={cockpit} alertas={alertas} mes={mesPorExtenso(hojeStr)} />
        </div>
      )}

      <div className="mt-8">
        <Retorno r={retorno} rotulo={mesPorExtenso(hojeStr)} />
      </div>

      <div className="mt-8">
        <Encaixe pacientes={pacientes} dias={semana.dias} />
      </div>

      <div className="mt-10">
        <Ausencias ausencias={ausencias} hoje={hojeStr} horizonte={ate} />
      </div>
    </div>
  );
}

/** "março de 2026", do dia civil de São Paulo — nunca do relógio do servidor. */
function mesPorExtenso(dia: string): string {
  const [ano, mes] = dia.split("-").map(Number);
  return new Intl.DateTimeFormat("pt-BR", { month: "long", year: "numeric" })
    .format(new Date(Date.UTC(ano, mes - 1, 15)));
}

function Semaninha({ para, rotulo }: { para: string; rotulo: string }) {
  return (
    <Link
      href={`/agenda?semana=${para}`}
      className="rounded-full border border-linha2 px-3 py-1 font-mono text-[13px] text-tinta2 transition-colors hover:border-vaga hover:text-vaga"
    >
      {rotulo}
    </Link>
  );
}

/**
 * Um número da faixa, e para onde ele abre.
 *
 * Nenhum dos números do topo abria em nada — ela lia "R$ 3.400 previsto" e não
 * tinha caminho para as sessões que formam o número, então não tinha como
 * conferir. Número que não abre é número que ela acredita ou não acredita, e o
 * produto não pode depender disso. O padrão é o do `Contador.tsx`, que nomeia a
 * tela de origem em vez de mandar procurar.
 */
function Numero({
  rotulo,
  valor,
  cor = "text-tinta",
  nota,
  href,
}: {
  rotulo: string;
  valor: string;
  cor?: string;
  nota?: string;
  href?: string;
}) {
  const conteudo = (
    <>
      <dt className="rotulo">{rotulo}</dt>
      <dd>
        <span className={`tabular mt-1 block font-mono text-[24px] font-medium leading-none ${cor}`}>
          {valor}
        </span>
        {nota && (
          <span className="mt-1.5 block text-[11px] leading-relaxed text-tinta3">{nota}</span>
        )}
      </dd>
    </>
  );

  if (!href) return <div className="bg-folha px-5 py-4">{conteudo}</div>;

  return (
    <Link href={href} className="block bg-folha px-5 py-4 transition-colors hover:bg-folha2">
      {conteudo}
    </Link>
  );
}
