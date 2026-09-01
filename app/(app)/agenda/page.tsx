import Link from "next/link";
import { sessaoAtual } from "@/lib/conta";
import {
  sessoesDaSemana,
  resumoDaSemana,
  listarAusencias,
  horizonte,
  pacientesParaEncaixe,
  cobrancasDaSemana,
  retornoDoMes,
} from "./dados";
import { Semana } from "@/components/app/Semana";
import { Retorno } from "@/components/app/Retorno";
import { Ausencias } from "@/components/app/Ausencias";
import { Encaixe } from "@/components/app/Encaixe";
import { semanaDe, rotuloSemana, somarDias } from "@/lib/semana";
import { hoje } from "@/lib/tempo-servidor";
import { acessosDa } from "@/lib/conta";
import { prazosDoMes } from "@/app/(app)/prazos";
import { pendencias, fraseDasPendencias } from "@/lib/navegacao";
import { FaixaDePendencias } from "@/components/app/Navegacao";
import { estadoInicial } from "@/app/(app)/comecar/page";

export const metadata = { title: "Agenda" };

const brl = (n: number) =>
  n.toLocaleString("pt-BR", { style: "currency", currency: "BRL", maximumFractionDigits: 0 });

export default async function Agenda({
  searchParams,
}: {
  searchParams: Promise<{ semana?: string }>;
}) {
  const { semana: pedida } = await searchParams;
  const hojeStr = hoje();

  const referencia = /^\d{4}-\d{2}-\d{2}$/.test(pedida ?? "") ? pedida! : hojeStr;
  const semana = semanaDe(referencia);

  const [sessao, sessoes, ausencias, ate, pacientes, retorno, prazos, comeco] =
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

      {/* a faixa de números */}
      <dl className="mt-5 grid gap-px overflow-hidden rounded-cartao border border-linha bg-linha sm:grid-cols-2 lg:grid-cols-4">
        <Numero rotulo="sessões na semana" valor={String(resumo.vivas)} />
        <Numero rotulo="previsto" valor={brl(resumo.previsto)} cor="text-cheia" />
        <Numero
          rotulo={resumo.canceladasTarde === 1 ? "cancelou tarde" : "cancelaram tarde"}
          valor={String(resumo.canceladasTarde)}
          cor={resumo.canceladasTarde > 0 ? "text-aviso" : undefined}
        />
        <Numero
          rotulo="hora vazia"
          valor={brl(resumo.perdido)}
          cor={resumo.perdido > 0 ? "text-vaga" : undefined}
          nota={
            resumo.perdido > 0
              ? "o que a política não recupera — é este buraco que a fila existe para preencher"
              : "nenhum buraco nesta semana"
          }
        />
      </dl>

      <div className="mt-6">
        <Semana semana={semana} sessoes={sessoes}
        cobrancas={cobrancas} hoje={hojeStr} />
      </div>

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

function Numero({
  rotulo,
  valor,
  cor = "text-tinta",
  nota,
}: {
  rotulo: string;
  valor: string;
  cor?: string;
  nota?: string;
}) {
  return (
    <div className="bg-folha px-5 py-4">
      <dt className="rotulo">{rotulo}</dt>
      <dd>
        <span className={`tabular mt-1 block font-mono text-[24px] font-medium leading-none ${cor}`}>
          {valor}
        </span>
        {nota && (
          <span className="mt-1.5 block text-[11px] leading-relaxed text-tinta3">{nota}</span>
        )}
      </dd>
    </div>
  );
}
