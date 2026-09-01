import Link from "next/link";
import { notFound } from "next/navigation";
import {
  vaga as obterVaga,
  elegiveis,
  eventosDaVaga,
  ofertasDaVaga,
  filaDaConta,
  regrasDaConta,
} from "../dados";
import { Cascata, type LinhaDaFila } from "@/components/app/Cascata";
import { ROTULO_REGRA } from "@/lib/regra";

export const metadata = { title: "A vaga" };

const QUANDO = new Intl.DateTimeFormat("pt-BR", {
  timeZone: "America/Sao_Paulo",
  weekday: "long",
  day: "numeric",
  month: "long",
  hour: "2-digit",
  minute: "2-digit",
});

export default async function PaginaDaVaga({
  params,
}: {
  params: Promise<{ sessao: string }>;
}) {
  const { sessao } = await params;

  const vaga = await obterVaga(sessao);
  if (!vaga) notFound();

  const [lista, eventos, ofertas, fila, regras] = await Promise.all([
    elegiveis(sessao),
    eventosDaVaga(sessao),
    ofertasDaVaga(sessao),
    filaDaConta(),
    regrasDaConta(),
  ]);

  // Junta o que o motor decidiu (elegibilidade e motivo) com o que já aconteceu
  // (as ofertas) e com o que a fila guarda (janela e espera). A tela não recalcula
  // nada — só costura.
  const porPaciente = new Map(fila.map((f) => [f.paciente_id, f]));
  const ofertaDe = new Map(ofertas.map((o) => [o.paciente_id, o]));

  const linhas: LinhaDaFila[] = lista.map((e) => ({
    ...e,
    janelas: porPaciente.get(e.paciente_id)?.janelas ?? [],
    ultima_sessao: porPaciente.get(e.paciente_id)?.ultima_sessao ?? null,
    oferta: ofertaDe.get(e.paciente_id) ?? null,
  }));

  const temOfertaViva = ofertas.some((o) => o.estado === "enviada");
  const preenchida = eventos.find((e) => e.tipo === "vaga_preenchida");
  const recuperado =
    preenchida && typeof preenchida.detalhe?.valor === "string"
      ? (preenchida.detalhe.valor as string)
      : null;

  const ehVaga = vaga.estado.startsWith("cancelada");
  const jaPassou = new Date(vaga.inicio) <= new Date();

  return (
    <div>
      <Link href="/encaixes" className="text-[12.5px] text-tinta3 hover:text-vaga">
        ← fila
      </Link>

      <h1 className="mt-2 font-serif text-[28px] leading-tight tracking-[-0.015em]">
        A hora que vagou
      </h1>
      <p className="mt-2 text-[14px] text-tinta2">
        {QUANDO.format(new Date(vaga.inicio))}
        {vaga.pacientes?.nome && ` · era de ${vaga.pacientes.nome}`}
      </p>

      {!ehVaga || jaPassou ? (
        <div className="mt-6 rounded-cartao border border-aviso-linha bg-aviso-bg px-5 py-4 text-[13.5px] leading-relaxed text-tinta2">
          {!ehVaga
            ? "Este horário não está cancelado, então não é uma vaga. A fila só preenche buraco."
            : "Esta hora já passou. Não dá mais para preencher."}
        </div>
      ) : (
        <div className="mt-6">
          <Cascata
            vaga={vaga}
            fila={linhas}
            eventos={eventos}
            regra={ROTULO_REGRA[regras.regra_prioridade]}
            temOfertaViva={temOfertaViva}
            recuperado={recuperado}
          />
        </div>
      )}
    </div>
  );
}
