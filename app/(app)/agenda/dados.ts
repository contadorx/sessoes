import "server-only";
import type { RespostaBruta } from "@/lib/confirmacao";
import type { HistoricoBruto } from "@/lib/politica";
import type { CockpitBruto, AlertasBrutos } from "@/lib/risco";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { diaEmSP, inicioDoDiaSP } from "@/lib/tempo";
import { somarDias } from "@/lib/semana";
import { hoje } from "@/lib/tempo-servidor";

export type SessaoLinha = {
  id: string;
  inicio: string;
  fim: string;
  origem: "recorrencia" | "encaixe" | "avulsa" | "remarcada" | "importada";
  nota: string | null;
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
  /** Da 0057. Quem respondeu, quem não respondeu, e quem nem foi perguntado. */
  eixo_confirmacao: string;
  pacientes: { id: string; nome: string; telefone: string | null } | null;
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
        "id, inicio, fim, origem, estado, valor, nota, politica_horas, politica_percentual, eixo_confirmacao, pacientes ( id, nome, telefone )",
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
        "id, inicio, fim, origem, estado, valor, nota, politica_horas, politica_percentual, eixo_confirmacao, pacientes ( id, nome, telefone )",
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

export type CobrancaLinha = {
  id: string;
  sessao_id: string | null;
  valor: string;
  motivo: "cancelada_tarde" | "falta" | "avulsa" | "sessao_realizada";
  estado: "aberta" | "paga" | "perdoada" | "cancelada";
  politica_horas: number | null;
  politica_percentual: number | null;
  criado_em: string;
  pix_copia_cola: string | null;
};

/**
 * A cobrança de uma sessão, se existir.
 *
 * Traz também as canceladas para que a tela possa dizer "isto já foi desfeito"
 * em vez de sumir com a informação — o histórico do que quase foi cobrado é
 * parte do que faz alguém confiar na régua automática.
 *
 * Desde a B23 a **realizada** também entra: é ela que carrega o "recebi", e sem
 * a cobrança aqui a tela ofereceria o botão de novo para uma hora já
 * registrada.
 */
export async function cobrancasDaSemana(
  sessoes: SessaoLinha[],
): Promise<Record<string, CobrancaLinha>> {
  const ids = sessoes
    .filter(
      (s) =>
        s.estado === "cancelada_tarde" || s.estado === "falta" || s.estado === "realizada",
    )
    .map((s) => s.id);

  if (ids.length === 0) return {};

  const supabase = await supabaseSessao();

  const linhas = (await db(
    "cobrancas.da_semana",
    supabase
      .from("cobrancas")
      .select("id, sessao_id, valor, motivo, estado, politica_horas, politica_percentual, criado_em, pix_copia_cola")
      .in("sessao_id", ids)
      .neq("estado", "cancelada"),
  )) as unknown as CobrancaLinha[] | null;

  const porSessao: Record<string, CobrancaLinha> = {};
  for (const c of linhas ?? []) {
    if (c.sessao_id) porSessao[c.sessao_id] = c;
  }
  return porSessao;
}

export async function cobrancaDaSessao(sessaoId: string): Promise<CobrancaLinha | null> {
  const supabase = await supabaseSessao();

  const linhas = await db(
    "cobrancas.da_sessao",
    supabase
      .from("cobrancas")
      .select("id, sessao_id, valor, motivo, estado, politica_horas, politica_percentual, criado_em, pix_copia_cola")
      .eq("sessao_id", sessaoId)
      .neq("estado", "cancelada")
      .order("criado_em", { ascending: false })
      .limit(1),
  );

  return ((linhas ?? []) as unknown as CobrancaLinha[])[0] ?? null;
}

import type { LinhaRetorno } from "@/components/app/Retorno";

/**
 * O retorno do mês corrente, em datas civis de São Paulo.
 *
 * Um mês é a janela certa: semana é ruído (uma psicóloga pode passar sete dias
 * sem nenhum cancelamento) e ano esconde a piora. O mês é também o período em
 * que ela pensa o próprio dinheiro.
 */
export async function retornoDoMes(hojeStr: string): Promise<LinhaRetorno> {
  const supabase = await supabaseSessao();

  const primeiro = `${hojeStr.slice(0, 7)}-01`;

  const linhas = (await db(
    "agenda.retorno",
    supabase.rpc("retorno", { p_de: primeiro, p_ate: hojeStr }),
  )) as unknown as LinhaRetorno[] | null;

  return (
    linhas?.[0] ?? {
      canceladas: 0,
      oferecidas: 0,
      preenchidas: 0,
      taxa: null,
      valor_preenchido: "0",
      valor_recebido: "0",
      valor_em_aberto: "0",
      valor_perdoado: "0",
      horas_recuperadas: "0",
    }
  );
}

/**
 * Os dois números que decidem se a confirmação se paga.
 *
 * Trinta dias para trás, e **degrada em silêncio**: se a consulta falhar, a
 * agenda aparece sem o bloco em vez de não aparecer. Instrumento de medição não
 * pode derrubar a tela que ele mede.
 */
export async function respostaDasConfirmacoes(hojeStr: string) {
  const supabase = await supabaseSessao();
  const de = new Date(`${hojeStr}T00:00:00Z`);
  de.setUTCDate(de.getUTCDate() - 30);

  try {
    return (await db("agenda.confirmacoes", supabase.rpc("resposta_das_confirmacoes", {
      p_de: de.toISOString().slice(0, 10),
      p_ate: hojeStr,
    }))) as unknown as RespostaBruta;
  } catch (e) {
    console.error("[agenda] sem os números da confirmação", e);
    return null;
  }
}

// ============================================================ P4 · a decisão

export type DecisaoPendente = {
  id: string;
  paciente_id: string;
  paciente: string;
  sessao_id: string;
  inicio: string;
  motivo: "cancelada_tarde" | "falta";
  valor_sugerido: string;
  politica_horas: number | null;
  politica_percentual: number | null;
  valor_da_sessao: string | null;
  competencia: string;
  criado_em: string;
  dias_esperando: number;
  historico: HistoricoBruto;
};

/**
 * A caixa de decisões (P4).
 *
 * Uma chamada só, e ela já traz o histórico de cada pessoa junto — o doc 30
 * pede a proposta "com a política congelada **e o histórico**", e buscar o
 * histórico numa segunda ida faria a tela mostrar a pergunta antes de ter o que
 * responde a ela.
 *
 * Degrada para lista vazia em vez de derrubar a agenda: uma caixa que não
 * carrega é ruim, uma agenda que não abre é pior.
 */
export async function decisoesPendentes(): Promise<DecisaoPendente[]> {
  const supabase = await supabaseSessao();

  try {
    const linhas = (await db(
      "cobrancas.decisoes_pendentes",
      supabase.rpc("decisoes_pendentes"),
    )) as unknown as DecisaoPendente[] | null;
    return linhas ?? [];
  } catch (e) {
    console.error("[decisoes] falhou carregar", e);
    return [];
  }
}

// ============================================================ P5 · o cockpit

export type CockpitLinha = CockpitBruto;
export type AlertasLinha = AlertasBrutos;

/**
 * Os quatro números do mês (P5).
 *
 * **Uma chamada só, e ela traz os quatro.** Não existe leitura que devolva
 * ocupação sozinha — nem aqui, nem no banco. Ocupação subindo com receita por
 * hora caindo é sintoma, e só se enxerga com os dois lado a lado.
 *
 * Degrada para `null` em vez de derrubar a agenda: a tela que mede não pode
 * quebrar a tela que ela mede.
 */
export async function cockpitDoMes(
  profissionalId: string | null,
  de: string,
  ate: string,
): Promise<CockpitLinha | null> {
  if (!profissionalId) return null;
  const supabase = await supabaseSessao();

  try {
    return (await db(
      "risco.cockpit",
      supabase.rpc("cockpit_do_mes", {
        p_profissional: profissionalId,
        p_de: de,
        p_ate: ate,
      }),
    )) as unknown as CockpitLinha;
  } catch (e) {
    console.error("[risco] falhou o cockpit", e);
    return null;
  }
}

/**
 * Os alertas que apareceram e ninguém usou nos últimos três meses.
 *
 * É medida do **produto**, e o critério de pronto do P5 pede que ela exista
 * desde o primeiro dia — uma feature que não traz consigo o instrumento que a
 * mediria é uma feature que ninguém desliga depois.
 */
export async function alertasARever(
  profissionalId: string | null,
): Promise<AlertasLinha | null> {
  if (!profissionalId) return null;
  const supabase = await supabaseSessao();

  try {
    return (await db(
      "risco.alertas",
      supabase.rpc("alertas_a_rever", { p_profissional: profissionalId }),
    )) as unknown as AlertasLinha;
  } catch (e) {
    console.error("[risco] falhou ler os alertas", e);
    return null;
  }
}
