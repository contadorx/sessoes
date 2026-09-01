import "server-only";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import type { Painel, ContaNoPainel } from "@/lib/negocio";

/**
 * As duas leituras do painel do negócio.
 *
 * Nenhuma delas recebe `conta_id` por parâmetro e nenhuma filtra por conta: as
 * funções do banco são `security definer` e conferem `e_operador()` por dentro,
 * levantando exceção para quem não for eu. Se a marca cair, isto para de
 * funcionar em vez de vazar — a mesma disciplina do `sessaoAtual()`.
 *
 * E as duas devolvem exatamente o que a 0045 escreveu por lista de colunas
 * nomeadas: nada de paciente, registro, evolução ou anamnese. A fronteira 9 do
 * doc 11 é cumprida no banco, não aqui — aqui ela só não é desfeita.
 */

export async function lerPainel(mes?: string): Promise<Painel | null> {
  const supabase = await supabaseSessao();
  return (
    (await db<Painel>(
      "negocio.painel",
      supabase.rpc("painel_do_negocio", { p_mes: mes ?? null }),
    )) ?? null
  );
}

export async function lerContas(): Promise<ContaNoPainel[]> {
  const supabase = await supabaseSessao();
  return (
    (await db<ContaNoPainel[]>("negocio.contas", supabase.rpc("contas_do_painel"))) ?? []
  );
}

// ============================================ a operação (OP5)

import type { Plano } from "@/lib/negocio";

export type CustoFixo = { mes: string; rubrica: string; centavos: number; nota: string | null };
export type PrecoCanal = {
  canal: string;
  vigencia_inicio: string;
  centavos_milesimos: number;
  fonte: string | null;
};

export type Ficha = {
  conta: {
    id: string; nome: string; tipo: string; plano: string;
    is_teste: boolean; criado_em: string; cidade: string | null;
  } | null;
  valor: { valor_centavos: number; origem: string; divergencia: string | null } | null;
  custo: { custo_centavos: number } | null;
  assinaturas: {
    id: string; plano: string; estado: string; valor_centavos: number; ciclo: string;
    origem: string; inicio: string; proximo_vencimento: string | null;
    cancelada_em: string | null; motivo_cancelamento: string | null;
  }[];
  faturas: {
    id: string; competencia: string; vencimento: string;
    valor_centavos: number; estado: string; pago_em: string | null;
  }[];
  uso: {
    pacientes_ativos: number; sessoes_no_mes: number; mensagens_no_mes: number;
    usuarios: number; ultima_sessao_criada: string | null;
  };
};

/**
 * A ficha de uma conta.
 *
 * Vale repetir o que ela **não** traz, porque é o ponto: contagem de
 * pacientes, nunca nome; contagem de sessões, nunca horário. A função do banco
 * é escrita com lista de colunas nomeadas e a suíte 0050 planta um nome
 * improvável na base para reprovar se ele aparecer aqui.
 */
export async function lerFicha(conta: string): Promise<Ficha | null> {
  const supabase = await supabaseSessao();
  return (
    (await db<Ficha>("negocio.ficha", supabase.rpc("ficha_da_conta", { p_conta: conta }))) ?? null
  );
}

export async function lerCustos(mes?: string): Promise<CustoFixo[]> {
  const supabase = await supabaseSessao();
  return (
    (await db<CustoFixo[]>("negocio.custos", supabase.rpc("custos_do_mes", { p_mes: mes ?? null }))) ?? []
  );
}

export async function lerPrecos(): Promise<PrecoCanal[]> {
  const supabase = await supabaseSessao();
  return (await db<PrecoCanal[]>("negocio.precos", supabase.rpc("precos_dos_canais"))) ?? [];
}

/** O cardápio, para os seletores de plano. É público — não precisa de operador. */
export async function lerPlanos(): Promise<Plano[]> {
  const supabase = await supabaseSessao();
  return (
    (await db<Plano[]>(
      "negocio.planos",
      supabase
        .from("planos")
        .select("codigo, nome, preco_centavos, ciclo, chamada, recursos")
        .eq("ativo", true)
        .order("ordem"),
    )) ?? []
  );
}
