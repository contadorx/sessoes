import Link from "next/link";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { PainelVagas } from "@/components/app/Vagas";
import type { VagaLinha } from "@/lib/vagafixa";

export const metadata = { title: "Vagas fixas" };

type Bruta = {
  id: string;
  dia_semana: number;
  hora: string;
  duracao_min: number;
  motivo: string;
  valor_anterior: string | null;
  aberta_em: string;
  fechada_em: string | null;
  fechada_por: string | null;
  novo_paciente: string | null;
  pacientes: { nome: string } | null;
  ofertas_fixas: { estado: string; pacientes: { nome: string } | null }[];
};

export default async function Vagas() {
  const supabase = await supabaseSessao();

  const [brutas, espera] = await Promise.all([
    db(
      "vagas.listar",
      supabase
        .from("vagas_fixas")
        .select(
          "id, dia_semana, hora, duracao_min, motivo, valor_anterior, aberta_em, " +
            "fechada_em, fechada_por, novo_paciente, " +
            "pacientes!vagas_fixas_novo_paciente_fkey ( nome ), " +
            "ofertas_fixas ( estado, pacientes ( nome ) )",
        )
        .order("aberta_em", { ascending: false })
        .limit(40),
    ) as Promise<unknown>,
    db(
      "filaentrada.contar",
      supabase.from("fila_entrada").select("id").eq("ativo", true),
    ) as Promise<unknown>,
  ]);

  const vagas: VagaLinha[] = ((brutas ?? []) as Bruta[]).map((v) => ({
    id: v.id,
    dia_semana: v.dia_semana,
    hora: v.hora,
    duracao_min: v.duracao_min,
    motivo: v.motivo,
    valor_anterior: v.valor_anterior,
    aberta_em: v.aberta_em,
    fechada_em: v.fechada_em,
    fechada_por: v.fechada_por,
    novo_paciente: v.novo_paciente,
    oferecida_a:
      v.ofertas_fixas?.find((o) => o.estado === "enviada")?.pacientes?.nome ?? null,
    ficou_com: v.pacientes?.nome ?? null,
  }));

  const naFila = ((espera ?? []) as { id: string }[]).length;

  return (
    <div className="mx-auto max-w-3xl">
      <h1 className="font-serif text-[28px] leading-tight tracking-[-0.015em]">
        Vagas fixas
      </h1>

      <p className="mt-3 max-w-2xl text-[14px] leading-relaxed text-tinta2">
        A fila de encaixe preenche o buraco <b>de uma semana</b>. Esta preenche o
        buraco <b className="font-semibold text-tinta">para sempre</b>: quando
        alguém recebe alta ou some, o que abre é uma hora <i>toda semana</i> — o
        horário recorrente é o ativo mais valioso do consultório, e é o que
        demora mais para repor sozinho.
      </p>

      <p className="mt-2 text-[13px] text-tinta2">
        {naFila === 0 ? (
          <>
            Sua fila de entrada está vazia. Quem liga e não tem horário entra por{" "}
            <Link href="/pacientes" className="underline underline-offset-2 hover:text-vaga">
              Pacientes
            </Link>
            .
          </>
        ) : (
          <>
            <b className="font-semibold text-tinta">{naFila}</b>{" "}
            {naFila === 1 ? "pessoa espera" : "pessoas esperam"} um horário fixo.
          </>
        )}
      </p>

      <PainelVagas vagas={vagas} />

      {/* --------------------------------------------- o que esta fila não faz */}
      <section className="mt-10 border-t border-linha pt-6">
        <h2 className="rotulo">Como esta fila funciona — e o que ela não decide</h2>
        <ul className="mt-3 max-w-2xl space-y-2 text-[13px] leading-relaxed text-tinta2">
          <li>
            <b className="font-medium text-tinta">Reajustar não abre vaga.</b>{" "}
            Corrigir um valor fecha o combinado e abre outro no mesmo instante.
            Só o <i>encerramento</i> libera o horário — senão a lista de espera
            receberia a terça de quem continua sendo atendida.
          </li>
          <li>
            <b className="font-medium text-tinta">Aceitar reserva, não combina.</b>{" "}
            Um &ldquo;sim&rdquo; aqui não define valor, política de falta nem
            contrato. A vaga fica no nome da pessoa e o próximo passo é seu — a
            conversa que você teria de qualquer jeito.
          </li>
          <li>
            <b className="font-medium text-tinta">Uma pessoa por vez, 24 horas cada.</b>{" "}
            Não é aviso para todo mundo: é fila. O prazo é maior que o do encaixe
            porque a pergunta é maior — quarenta minutos para decidir o próprio
            ano não é escolher, é reagir.
          </li>
          <li>
            <b className="font-medium text-tinta">A ordem é a de chegada.</b>{" "}
            Quem esperou mais vai primeiro. Não existe, e não vai existir, um
            jeito de pagar para furar a fila.
          </li>
        </ul>
      </section>
    </div>
  );
}
