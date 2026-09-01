import "server-only";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { sessaoAtual } from "@/lib/conta";
import type { Janela } from "@/lib/janela";
import type { Teto } from "@/lib/teto";

export type NaFila = {
  id: string;
  paciente_id: string;
  topa_antecipar: boolean;
  janelas: Janela[];
  prioridade: number;
  ativo: boolean;
  entrou_em: string;
  pacientes: { nome: string; estado: string; msg_canal: string } | null;
  /** Preenchido por `comEspera()` — não vem do banco. */
  ultima_sessao?: string | null;
};

export type Elegivel = {
  paciente_id: string;
  nome: string;
  elegivel: boolean;
  motivo: string;
  ordem: number;
};

export type Evento = {
  id: number;
  tipo: string;
  detalhe: Record<string, unknown>;
  em: string;
};

export type OfertaLinha = {
  id: string;
  paciente_id: string;
  ordem: number;
  estado: "enviada" | "aceita" | "recusada" | "expirada" | "cancelada";
  enviar_em: string;
  expira_em: string;
  respondida_em: string | null;
  pacientes: { nome: string } | null;
};

export type Vaga = {
  id: string;
  inicio: string;
  fim: string;
  valor: string;
  estado: string;
  cancelada_em: string | null;
  pacientes: { nome: string } | null;
};

export type Regras = {
  regra_prioridade: "mais_tempo_sem_sessao" | "ordem_de_entrada";
  oferta_timeout_min: number;
  silencio_inicio: string;
  silencio_fim: string;
};

const CAMPOS_FILA =
  "id, paciente_id, topa_antecipar, janelas, prioridade, ativo, entrou_em, pacientes ( nome, estado, msg_canal )";

export async function filaDaConta(): Promise<NaFila[]> {
  const supabase = await supabaseSessao();

  const linhas = (await db(
    "fila.listar",
    supabase.from("fila_encaixe").select(CAMPOS_FILA).order("prioridade", { ascending: false }),
  )) as unknown as NaFila[];

  return comEspera(linhas ?? []);
}

/**
 * Acrescenta a última sessão realizada de cada um. É uma segunda consulta em
 * vez de um agregado no select porque o PostgREST não faz `max()` por grupo —
 * e o volume aqui é a fila de um consultório, não um relatório.
 */
async function comEspera(fila: NaFila[]): Promise<NaFila[]> {
  if (fila.length === 0) return fila;

  const supabase = await supabaseSessao();
  const ids = fila.map((f) => f.paciente_id);

  const sessoes = (await db(
    "fila.ultimaSessao",
    supabase
      .from("sessoes")
      .select("paciente_id, inicio")
      .in("paciente_id", ids)
      .eq("estado", "realizada")
      .order("inicio", { ascending: false }),
  )) as unknown as { paciente_id: string; inicio: string }[];

  const ultima = new Map<string, string>();
  for (const s of sessoes ?? []) {
    if (!ultima.has(s.paciente_id)) ultima.set(s.paciente_id, s.inicio);
  }

  return fila.map((f) => ({ ...f, ultima_sessao: ultima.get(f.paciente_id) ?? null }));
}

/** Horários cancelados que ainda estão no futuro — os buracos abertos. */
export async function vagasAbertas(): Promise<(Vaga & { ofertas: number; preenchida: boolean })[]> {
  const supabase = await supabaseSessao();

  const linhas = (await db(
    "vagas.abertas",
    supabase
      .from("sessoes")
      .select("id, inicio, fim, valor, estado, cancelada_em, pacientes ( nome )")
      .in("estado", ["cancelada_cedo", "cancelada_tarde"])
      .gt("inicio", new Date().toISOString())
      .order("inicio"),
  )) as unknown as Vaga[];

  if (!linhas || linhas.length === 0) return [];

  const ofertas = (await db(
    "vagas.ofertas",
    supabase
      .from("ofertas")
      .select("sessao_id, estado")
      .in("sessao_id", linhas.map((v) => v.id)),
  )) as unknown as { sessao_id: string; estado: string }[];

  return linhas.map((v) => {
    const minhas = (ofertas ?? []).filter((o) => o.sessao_id === v.id);
    return {
      ...v,
      ofertas: minhas.length,
      preenchida: minhas.some((o) => o.estado === "aceita"),
    };
  });
}

export async function vaga(sessaoId: string): Promise<Vaga | null> {
  const supabase = await supabaseSessao();

  const linhas = (await db(
    "vaga.obter",
    supabase
      .from("sessoes")
      .select("id, inicio, fim, valor, estado, cancelada_em, pacientes ( nome )")
      .eq("id", sessaoId)
      .limit(1),
  )) as unknown as Vaga[];

  return (linhas ?? [])[0] ?? null;
}

/**
 * A elegibilidade vem da função do banco — com o motivo de cada um. A tela
 * nunca decide quem cabe; ela mostra o que o motor decidiu, e por quê.
 */
export async function elegiveis(sessaoId: string): Promise<Elegivel[]> {
  const supabase = await supabaseSessao();

  const linhas = await db(
    "fila.elegiveis",
    supabase.rpc("elegiveis_para_vaga", { p_sessao: sessaoId }),
  );

  return (linhas ?? []) as unknown as Elegivel[];
}

export async function eventosDaVaga(sessaoId: string): Promise<Evento[]> {
  const supabase = await supabaseSessao();

  const linhas = await db(
    "vaga.eventos",
    supabase
      .from("eventos_fila")
      .select("id, tipo, detalhe, em")
      .eq("sessao_id", sessaoId)
      .order("em")
      .order("id"),
  );

  return (linhas ?? []) as unknown as Evento[];
}

export async function ofertasDaVaga(sessaoId: string): Promise<OfertaLinha[]> {
  const supabase = await supabaseSessao();

  const linhas = await db(
    "vaga.ofertas",
    supabase
      .from("ofertas")
      .select("id, paciente_id, ordem, estado, enviar_em, expira_em, respondida_em, pacientes ( nome )")
      .eq("sessao_id", sessaoId)
      .order("ordem"),
  );

  return (linhas ?? []) as unknown as OfertaLinha[];
}

/** Quem ainda não está na fila, para o formulário de entrada. */
export async function foraDaFila(): Promise<{ id: string; nome: string }[]> {
  const supabase = await supabaseSessao();

  const [pacientes, fila] = await Promise.all([
    db(
      "fila.candidatos",
      supabase
        .from("pacientes")
        .select("id, nome")
        .in("estado", ["interessado", "triagem", "em_atendimento", "pausa"])
        .order("nome"),
    ),
    db("fila.jaNaFila", supabase.from("fila_encaixe").select("paciente_id")),
  ]);

  const dentro = new Set(
    ((fila ?? []) as unknown as { paciente_id: string }[]).map((f) => f.paciente_id),
  );

  return ((pacientes ?? []) as unknown as { id: string; nome: string }[]).filter(
    (p) => !dentro.has(p.id),
  );
}

export async function regrasDaConta(): Promise<Regras> {
  const supabase = await supabaseSessao();

  const linhas = await db(
    "conta.regras",
    supabase
      .from("contas")
      .select("regra_prioridade, oferta_timeout_min, silencio_inicio, silencio_fim")
      .limit(1),
  );

  return ((linhas ?? [])[0] ?? {
    regra_prioridade: "mais_tempo_sem_sessao",
    oferta_timeout_min: 40,
    silencio_inicio: "21:00",
    silencio_fim: "08:00",
  }) as unknown as Regras;
}

/** A métrica norte, no período pedido. */
export async function taxaDePreenchimento(
  de: string,
  ate: string,
): Promise<{ canceladas: number; oferecidas: number; preenchidas: number; taxa: number | null }> {
  const supabase = await supabaseSessao();

  const linhas = await db(
    "metrica.norte",
    supabase.rpc("taxa_de_preenchimento", { p_de: de, p_ate: ate }),
  );

  const l = (linhas ?? [])[0] as
    | { canceladas: number; oferecidas: number; preenchidas: number; taxa: number | null }
    | undefined;

  return l ?? { canceladas: 0, oferecidas: 0, preenchidas: 0, taxa: null };
}

/**
 * O teto do plano da conta.
 *
 * Mora aqui e não em `lib/` porque é leitura de banco, e a tela da fila é a
 * primeira que precisa dele: com o teto estourado, abrir uma vaga não oferece
 * para ninguém, e uma fila parada sem motivo escrito é indistinguível de uma
 * fila com defeito.
 */
export async function tetoDaConta(): Promise<Teto> {
  const supabase = await supabaseSessao();
  const sessao = await sessaoAtual();
  const linhas = await db<Teto[]>(
    "fila.teto",
    supabase.rpc("teto_da_conta", { p_conta: sessao.contaId }),
  );
  return (
    linhas?.[0] ?? {
      tem_teto: false,
      limite: null,
      usadas: 0,
      restantes: null,
      estourou: false,
      pct: 0,
    }
  );
}
