import Link from "next/link";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { sessaoAtual } from "@/lib/conta";
import { hoje } from "@/lib/tempo-servidor";
import { Horarios } from "@/components/app/Horarios";
import {
  lerCapacidade,
  fraseDaCapacidade,
  duracao,
  emHhmm,
  emMinutos,
  type CapacidadeBruta,
  type Faixa,
  type Destino,
} from "@/lib/capacidade";

export const metadata = { title: "Seus horários" };

type FaixaBruta = {
  id: string;
  dia_semana: number;
  inicio: string;
  fim: string;
  destino: string;
  minutos: number;
};

/** O primeiro e o último dia do mês corrente, em data civil. */
function mesDe(iso: string): { de: string; ate: string; rotulo: string } {
  const [a, m] = iso.slice(0, 10).split("-").map(Number);
  const ultimo = new Date(Date.UTC(a, m, 0)).getUTCDate();
  const MESES = [
    "janeiro", "fevereiro", "março", "abril", "maio", "junho",
    "julho", "agosto", "setembro", "outubro", "novembro", "dezembro",
  ];
  const mm = String(m).padStart(2, "0");
  return {
    de: `${a}-${mm}-01`,
    ate: `${a}-${mm}-${String(ultimo).padStart(2, "0")}`,
    rotulo: `${MESES[m - 1]} de ${a}`,
  };
}

/**
 * A capacidade declarada — quantas horas ela decide disponibilizar, e para quê.
 *
 * Esta tela é o **denominador** do produto inteiro. Sem ela, "quanto da sua
 * capacidade virou receita" não tem como ser respondido: o banco sabia quanto
 * foi vendido (`enquadres`) e nunca soube quanto foi oferecido.
 *
 * Ela mostra o mês corrente e **não mostra ocupação**. Ocupação precisa do
 * numerador, que é o livro-razão do P2 — e meia métrica agora seria um número
 * que muda de significado na próxima build.
 */
export default async function HorariosDeclarados() {
  const sessao = await sessaoAtual();
  const supabase = await supabaseSessao();

  const profs = (await db(
    "capacidade.profissional",
    supabase.from("profissionais").select("id, assina_como").eq("ativo", true).limit(1),
  )) as unknown as { id: string; assina_como: string | null }[];

  const prof = profs[0];

  if (!prof) {
    return (
      <div className="mx-auto max-w-2xl">
        <h1 className="font-serif text-[28px] leading-tight tracking-[-0.015em]">
          Seus horários
        </h1>
        <p className="mt-3 text-[13.5px] leading-relaxed text-tinta2">
          Não encontrei um profissional ativo nesta conta.
        </p>
      </div>
    );
  }

  const mes = mesDe(hoje());

  const [semana, bruta] = await Promise.all([
    db("capacidade.semana_lida", supabase.rpc("semana_declarada", {
      p_profissional: prof.id,
    })) as Promise<unknown>,
    db("capacidade.periodo", supabase.rpc("capacidade_vendavel", {
      p_profissional: prof.id,
      p_de: mes.de,
      p_ate: mes.ate,
    })) as Promise<unknown>,
  ]);

  const faixas: Faixa[] = ((semana ?? []) as FaixaBruta[]).map((f) => ({
    dia: f.dia_semana,
    // O Postgres devolve "09:00:00"; o `<input type="time">` quer "09:00".
    inicio: emHhmm(emMinutos(f.inicio)),
    fim: emHhmm(emMinutos(f.fim)),
    destino: f.destino as Destino,
  }));

  const c = lerCapacidade(bruta as CapacidadeBruta);

  return (
    <div className="mx-auto max-w-2xl">
      <Link href="/perfil" className="text-[12.5px] text-tinta3 hover:text-vaga">
        ← perfil
      </Link>

      <h1 className="mt-2 font-serif text-[28px] leading-tight tracking-[-0.015em]">
        Seus horários
      </h1>

      <p className="mt-3 max-w-[62ch] text-[14px] leading-relaxed text-tinta2">
        Quantas horas por semana você <b className="font-semibold text-tinta">decide</b>{" "}
        disponibilizar — e para quê. É a partir daqui que o sistema consegue dizer
        quanto da sua capacidade virou receita, e é a única resposta que ele não
        tem como adivinhar.
      </p>

      {/* -------------------------------------------------------- o mês corrente */}
      <section className="mt-6 rounded-cartao border border-linha bg-folha2 px-5 py-4">
        <h2 className="rotulo">Em {mes.rotulo}</h2>
        <p className="mt-2 max-w-[60ch] text-[13px] leading-relaxed text-tinta2">
          {fraseDaCapacidade(c)}
        </p>

        {!c.semJanela && (
          <dl className="mt-3 flex flex-wrap gap-x-8 gap-y-2">
            <div>
              <dt className="text-[11.5px] text-tinta3">para atender</dt>
              <dd className="font-mono text-[15px] tabular-nums text-tinta">
                {duracao(c.vendavel)}
              </dd>
            </div>
            <div>
              <dt className="text-[11.5px] text-tinta3">registro e descanso</dt>
              <dd className="font-mono text-[15px] tabular-nums text-tinta2">
                {duracao(c.registro + c.descanso)}
              </dd>
            </div>
            {c.fora.total > 0 && (
              <div>
                <dt className="text-[11.5px] text-tinta3">fora da conta</dt>
                <dd className="font-mono text-[15px] tabular-nums text-tinta2">
                  {duracao(c.fora.total)}
                </dd>
              </div>
            )}
          </dl>
        )}

      </section>

      <div className="mt-8">
        <h2 className="rotulo">A sua semana</h2>
        <p className="mt-1.5 max-w-[62ch] text-[12px] leading-relaxed text-tinta3">
          Declare também o tempo que <b className="font-medium">não</b> é atender.
          Prontuário e descanso são horas de trabalho, e o sistema precisa saber
          disso para não tratar as duas como buraco na agenda.
        </p>
        <div className="mt-3">
          <Horarios profissional={prof.id} faixas={faixas} />
        </div>
      </div>

      <p className="mt-8 max-w-[62ch] border-t border-linha pt-5 text-[11.5px] leading-relaxed text-tinta3">
        Férias, feriados e bloqueios saem desta conta automaticamente — eles vêm
        das exceções da{" "}
        <Link href="/agenda" className="underline underline-offset-2 hover:text-vaga">
          agenda
        </Link>
        . Um mês de férias não derruba a sua ocupação: ele sai do denominador, e
        aparece dizendo que era férias.
        {sessao.papel !== "dona" && " Só a dona da conta altera esta declaração."}
      </p>
    </div>
  );
}
