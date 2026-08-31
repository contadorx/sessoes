import "server-only";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { diaEmSP, inicioDoDiaSP } from "@/lib/tempo";
import { somarDias } from "@/lib/semana";
import { hoje } from "@/lib/tempo-servidor";

export type SessaoLinha = {
  id: string;
  inicio: string;
  fim: string;
  origem: "recorrencia" | "encaixe" | "avulsa";
  estado:
    | "prevista"
    | "confirmada"
    | "realizada"
    | "falta"
    | "cancelada_cedo"
    | "cancelada_tarde";
  valor: string;
  politica_horas: number;
  politica_percentual: number;
  pacientes: { id: string; nome: string } | null;
};

export type Ausencia = {
  id: string;
  tipo: "ferias" | "feriado" | "bloqueio";
  inicio: string;
  fim: string;
  motivo: string | null;
};

/** As sessões de uma semana civil de São Paulo (segunda a domingo). */
export async function sessoesDaSemana(segunda: string): Promise<SessaoLinha[]> {
  const supabase = await supabaseSessao();

  const de = inicioDoDiaSP(segunda);
  const ate = inicioDoDiaSP(somarDias(segunda, 7));

  const linhas = await db(
    "sessoes.semana",
    supabase
      .from("sessoes")
      .select(
        "id, inicio, fim, origem, estado, valor, politica_horas, politica_percentual, pacientes ( id, nome )",
      )
      .gte("inicio", de.toISOString())
      .lt("inicio", ate.toISOString())
      .order("inicio"),
  );

  return (linhas ?? []) as unknown as SessaoLinha[];
}

export type ResumoSemana = {
  vivas: number;
  previsto: number;
  canceladasTarde: number;
  perdido: number;
  emRisco: number;
};

/**
 * A faixa de números do topo. `perdido` é o que a política **não** recupera:
 * o buraco que a fila da B7 existe para preencher.
 */
export function resumoDaSemana(sessoes: SessaoLinha[]): ResumoSemana {
  let previsto = 0;
  let perdido = 0;
  let emRisco = 0;
  let vivas = 0;
  let canceladasTarde = 0;

  for (const s of sessoes) {
    const valor = Number(s.valor);

    if (s.estado === "cancelada_tarde") {
      canceladasTarde++;
      const multa = Math.round((valor * s.politica_percentual) / 100);
      emRisco += multa;
      perdido += valor - multa;
      continue;
    }

    if (s.estado === "cancelada_cedo") {
      perdido += valor;
      continue;
    }

    vivas++;
    previsto += valor;
  }

  return { vivas, previsto, canceladasTarde, perdido, emRisco };
}

/** Pacientes com combinado aberto, para o encaixe. */
export async function pacientesParaEncaixe(): Promise<
  { id: string; nome: string; valor: string; duracao_min: number }[]
> {
  const supabase = await supabaseSessao();

  const linhas = await db(
    "pacientes.paraEncaixe",
    supabase
      .from("pacientes")
      .select("id, nome, enquadres ( valor, duracao_min )")
      .is("enquadres.vigencia_fim", null)
      .in("estado", ["em_atendimento", "triagem", "interessado"])
      .order("nome"),
  );

  return ((linhas ?? []) as unknown as {
    id: string;
    nome: string;
    enquadres: { valor: string; duracao_min: number }[];
  }[]).map((p) => ({
    id: p.id,
    nome: p.nome,
    valor: p.enquadres?.[0]?.valor ?? "0.00",
    duracao_min: p.enquadres?.[0]?.duracao_min ?? 50,
  }));
}

/** As sessões dos próximos N dias, do mais próximo para o mais distante. */
export async function proximasSessoes(dias = 14): Promise<SessaoLinha[]> {
  const supabase = await supabaseSessao();

  const de = inicioDoDiaSP(hoje());
  const ate = new Date(de.getTime() + dias * 86_400_000);

  const linhas = await db(
    "sessoes.proximas",
    supabase
      .from("sessoes")
      .select(
        "id, inicio, fim, origem, estado, valor, politica_horas, politica_percentual, pacientes ( id, nome )",
      )
      .gte("inicio", de.toISOString())
      .lt("inicio", ate.toISOString())
      .order("inicio"),
  );

  return (linhas ?? []) as unknown as SessaoLinha[];
}

/** Até quando a agenda está materializada — o horizonte da janela rolante. */
export async function horizonte(): Promise<string | null> {
  const supabase = await supabaseSessao();

  const linhas = await db(
    "sessoes.horizonte",
    supabase.from("sessoes").select("inicio").order("inicio", { ascending: false }).limit(1),
  );

  const ultima = (linhas ?? [])[0]?.inicio as string | undefined;
  return ultima ? diaEmSP(new Date(ultima)) : null;
}

export async function listarAusencias(): Promise<Ausencia[]> {
  const supabase = await supabaseSessao();

  const linhas = await db(
    "excecoes.listar",
    supabase
      .from("excecoes_agenda")
      .select("id, tipo, inicio, fim, motivo")
      .gte("fim", hoje())
      .order("inicio"),
  );

  return (linhas ?? []) as unknown as Ausencia[];
}

/** Agrupa por dia civil de São Paulo — não pelo dia do servidor. */
export function porDia(sessoes: SessaoLinha[]): [string, SessaoLinha[]][] {
  const mapa = new Map<string, SessaoLinha[]>();

  for (const s of sessoes) {
    const dia = diaEmSP(new Date(s.inicio));
    const lista = mapa.get(dia);
    if (lista) lista.push(s);
    else mapa.set(dia, [s]);
  }

  return [...mapa.entries()];
}
