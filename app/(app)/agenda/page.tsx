import Link from "next/link";
import { sessaoAtual } from "@/lib/conta";
import {
  sessoesDaSemana,
  resumoDaSemana,
  listarAusencias,
  horizonte,
  pacientesParaEncaixe,
} from "./dados";
import { Semana } from "@/components/app/Semana";
import { Ausencias } from "@/components/app/Ausencias";
import { Encaixe } from "@/components/app/Encaixe";
import { semanaDe, rotuloSemana, somarDias } from "@/lib/semana";
import { hoje } from "@/lib/tempo-servidor";

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

  const [sessao, sessoes, ausencias, ate, pacientes] = await Promise.all([
    sessaoAtual(),
    sessoesDaSemana(semana.inicio),
    listarAusencias(),
    horizonte(),
    pacientesParaEncaixe(),
  ]);

  const resumo = resumoDaSemana(sessoes);
  const ehSemanaAtual = semana.inicio === semanaDe(hojeStr).inicio;

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
          {!ehSemanaAtual && (
            <Link
              href="/agenda"
              className="ml-2 text-[12.5px] font-medium text-vaga hover:underline"
            >
              hoje
            </Link>
          )}
        </nav>
      </div>

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
        <Semana semana={semana} sessoes={sessoes} hoje={hojeStr} />
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
