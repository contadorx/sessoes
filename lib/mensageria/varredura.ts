import "server-only";
import { db } from "@/lib/db";
import { supabaseServico } from "@/lib/supabase/servico";
import {
  instrumentoConfiavel,
  avaliarDisjuntor,
  podeReenviar,
  JANELA_CONFIRMACAO_MIN,
  type Amostra,
  type Disjuntor,
} from "./entrega";

/**
 * A varredura da entrega — e **a ordem das etapas é a regra de negócio.**
 *
 *   0. confere o instrumento — sem confirmação nenhuma, não conclui nada
 *   1. marca como perdida a aceita e sem notícia além da janela
 *   2. devolve a perdida para a outbox, uma vez, com teto
 *   3. reavalia o disjuntor com a foto já atualizada
 *   4. grava o batimento, **inclusive quando se declarou cega**
 *
 * Trocar a ordem quebra coisas específicas: reavaliar o disjuntor antes de
 * marcar as perdidas mede a foto velha; reenviar antes de conferir o
 * instrumento é o cenário em que um webhook desconfigurado faz a base inteira
 * ser reenviada a cada passada.
 *
 * Ela roda dentro do mesmo cron da mensageria, e não num segundo: um relógio só
 * é um estado só para conferir. A janela de confirmação (20 min) é maior que o
 * intervalo do cron (5 min), então nada fica esperando a passada seguinte.
 */

export type RelatorioDaVarredura = {
  canal: string;
  cega: boolean;
  motivo: string | null;
  amostra: Amostra;
  perdidas: number;
  reenviadas: number;
  disjuntor: Disjuntor["estado"];
};

const NOME = "entrega:email";

export async function varrerEntrega(canal = "email"): Promise<RelatorioDaVarredura> {
  const supabase = supabaseServico();

  const [bruta] = ((await db(
    "entrega.amostra",
    supabase.rpc("amostra_do_canal", { p_canal: canal, p_janela_min: JANELA_CONFIRMACAO_MIN }),
  )) ?? []) as { total: number; confirmadas: number; sem_confirmacao: number }[];

  const amostra: Amostra = {
    total: Number(bruta?.total ?? 0),
    confirmadas: Number(bruta?.confirmadas ?? 0),
    semConfirmacao: Number(bruta?.sem_confirmacao ?? 0),
  };

  const linhas = ((await db(
    "entrega.disjuntor",
    supabase
      .from("canal_disjuntor")
      .select("estado, motivo, desde")
      .eq("canal", canal)
      .is("conta_id", null)
      .limit(1),
  )) ?? []) as { estado: Disjuntor["estado"]; motivo: string; desde: string }[];

  const disjuntor: Disjuntor = linhas[0] ?? { estado: "fechado", motivo: "nunca abriu", desde: null };

  // ---------------------------------------------------------------- etapa 0
  if (!instrumentoConfiavel(amostra)) {
    const motivo =
      `${amostra.total} mensagens saíram na janela e nenhuma confirmou entrega. ` +
      `Isso é o webhook mudo, não perda — e enquanto estiver assim, ninguém é ` +
      `marcado como perdido e o disjuntor não se mexe.`;

    await registrar(true, motivo, { canal, amostra });

    return {
      canal,
      cega: true,
      motivo,
      amostra,
      perdidas: 0,
      reenviadas: 0,
      disjuntor: disjuntor.estado,
    };
  }

  // ---------------------------------------------------------------- etapa 1
  const perdidas =
    (await db<number>("entrega.perdidas", supabase.rpc("marcar_perdidas", {
      p_canal: canal,
      p_janela_min: JANELA_CONFIRMACAO_MIN,
    }))) ?? 0;

  // ---------------------------------------------------------------- etapa 2
  const aReenviar = ((await db(
    "entrega.aReenviar",
    supabase
      .from("mensagens")
      .select("id, tentativas")
      .eq("canal", canal)
      .eq("estado", "perdida")
      .limit(50),
  )) ?? []) as { id: string; tentativas: number }[];

  let reenviadas = 0;
  for (const m of aReenviar) {
    if (!podeReenviar(m.tentativas)) continue;
    try {
      const novo = await db<string | null>(
        "entrega.reenfileirar",
        supabase.rpc("reenfileirar_mensagem", { p_mensagem: m.id }),
      );
      if (novo) reenviadas += 1;
    } catch (e) {
      // Uma que não voltou para a fila não pode derrubar as outras.
      console.error("[entrega] não consegui reenfileirar", { id: m.id, e });
    }
  }

  // ---------------------------------------------------------------- etapa 3
  const [depois] = ((await db(
    "entrega.amostraDepois",
    supabase.rpc("amostra_do_canal", { p_canal: canal, p_janela_min: JANELA_CONFIRMACAO_MIN }),
  )) ?? []) as { total: number; confirmadas: number; sem_confirmacao: number }[];

  const foto: Amostra = {
    total: Number(depois?.total ?? 0),
    confirmadas: Number(depois?.confirmadas ?? 0),
    semConfirmacao: Number(depois?.sem_confirmacao ?? 0),
  };

  const novo = avaliarDisjuntor(disjuntor, foto, new Date().toISOString());

  if (novo.estado !== disjuntor.estado) {
    await db(
      "entrega.gravarDisjuntor",
      supabase
        .from("canal_disjuntor")
        .update({ estado: novo.estado, motivo: novo.motivo, desde: novo.desde, atualizado_em: new Date().toISOString() })
        .eq("canal", canal)
        .is("conta_id", null),
    );
  }

  // ---------------------------------------------------------------- etapa 4
  await registrar(false, null, { canal, amostra: foto, perdidas, reenviadas });

  return {
    canal,
    cega: false,
    motivo: null,
    amostra: foto,
    perdidas,
    reenviadas,
    disjuntor: novo.estado,
  };
}

/** O batimento. Gravado sempre — é o único sintoma de cron parado. */
async function registrar(cega: boolean, motivo: string | null, detalhe: unknown): Promise<void> {
  try {
    const supabase = supabaseServico();
    await db(
      "entrega.batimento",
      supabase.rpc("registrar_varredura", {
        p_nome: NOME,
        p_cega: cega,
        p_detalhe: { motivo, ...(detalhe as Record<string, unknown>) },
      }),
    );
  } catch (e) {
    console.error("[entrega] não consegui gravar o batimento", e);
  }
}
