import Link from "next/link";
import { notFound } from "next/navigation";
import { obterPaciente, enquadreAberto } from "../dados";
import { atualizarPaciente } from "../acoes";
import { FormPaciente } from "@/components/app/FormPaciente";
import { NovoEnquadre } from "@/components/app/NovoEnquadre";
import { rotuloHorario, rotuloPolitica } from "@/lib/enquadre";
import { Privacidade } from "@/components/app/Privacidade";

const brl = (v: string) =>
  Number(v).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });

const MOTIVO: Record<string, string> = {
  reajuste: "reajuste",
  mudanca_horario: "mudança de horário",
  encerramento: "encerramento",
};

export default async function Paciente({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const paciente = await obterPaciente(id);
  if (!paciente) notFound();

  const aberto = enquadreAberto(paciente);
  const historico = paciente.enquadres.filter((e) => e.vigencia_fim !== null);

  return (
    <div className="mx-auto max-w-3xl">
      <Link href="/pacientes" className="text-[12.5px] text-tinta3 hover:text-vaga">
        ← pacientes
      </Link>

      <h1 className="mt-2 font-serif text-[28px] leading-tight tracking-[-0.015em]">
        {paciente.nome}
      </h1>

      {/* o combinado vigente */}
      <section className="mt-6">
        <h2 className="rotulo">O combinado</h2>
        {aberto ? (
          <div className="mt-2 rounded-cartao border border-cheia-linha bg-cheia-bg px-5 py-4">
            <p className="font-mono text-[16px] text-cheia">
              {rotuloHorario(aberto.dia_semana, aberto.hora)} · {aberto.duracao_min} min ·{" "}
              {brl(aberto.valor)}
              {aberto.social && " · social"}
            </p>
            <p className="mt-1 text-[13px] text-tinta2">
              {rotuloPolitica({
                horas: aberto.politica_horas,
                percentual: aberto.politica_percentual,
              })}
              {aberto.modelo_cobranca !== "avulso" && ` · ${aberto.modelo_cobranca}`}
            </p>
            <p className="mt-2 font-mono text-[11.5px] text-tinta3">
              vigente desde {aberto.vigencia_inicio}
            </p>
          </div>
        ) : (
          <p className="mt-2 rounded-cartao border border-dashed border-vaga-linha bg-vaga-bg px-5 py-4 text-[13.5px] text-vaga">
            Sem combinado aberto. Sem ele não há sessão, cobrança nem fila.
          </p>
        )}

        <NovoEnquadre pacienteId={paciente.id} aberto={aberto} />
      </section>

      {historico.length > 0 && (
        <section className="mt-8">
          <h2 className="rotulo">Histórico do combinado</h2>
          <ul className="mt-2 overflow-hidden rounded-cartao border border-linha bg-folha">
            {historico.map((e) => (
              <li
                key={e.id}
                className="flex flex-wrap items-baseline gap-x-3 gap-y-1 border-t border-linha px-5 py-3 first:border-t-0"
              >
                <span className="font-mono text-[13px] text-tinta2">
                  {rotuloHorario(e.dia_semana, e.hora)} · {brl(e.valor)}
                </span>
                <span className="font-mono text-[11.5px] text-tinta3">
                  {e.vigencia_inicio} → {e.vigencia_fim}
                </span>
                {e.motivo_fim && (
                  <span className="ml-auto text-[11.5px] text-tinta3">
                    {MOTIVO[e.motivo_fim] ?? e.motivo_fim}
                  </span>
                )}
              </li>
            ))}
          </ul>
          <p className="mt-2 text-[11.5px] leading-relaxed text-tinta3">
            Valor de sessão nunca é editado no lugar: reajustar fecha o combinado
            atual e abre outro. É o que mantém de pé o que foi acertado, e quando.
          </p>
        </section>
      )}

      <section className="mt-8">
        <h2 className="rotulo">Cadastro</h2>
        {paciente.arquivado_em ? (
          <div className="mt-2 rounded-cartao border border-linha bg-folha2 px-5 py-4">
            <p className="text-[12.5px] leading-relaxed text-tinta2">
              Ficha arquivada — só leitura. Encerramento registrado:
            </p>
            <p className="mt-2 whitespace-pre-wrap text-[13px] leading-relaxed text-tinta">
              {paciente.encerramento}
            </p>
          </div>
        ) : (
          <div className="mt-2">
            <FormPaciente
              acao={atualizarPaciente}
              paciente={paciente}
              rotuloBotao="Salvar cadastro"
            />
          </div>
        )}
      </section>

      <Privacidade
        pacienteId={paciente.id}
        nome={paciente.nome}
        arquivado={Boolean(paciente.arquivado_em)}
        contatoEsquecidoEm={paciente.contato_esquecido_em}
        restricaoJudicial={paciente.restricao_judicial}
      />
    </div>
  );
}
