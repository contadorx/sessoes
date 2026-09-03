import "server-only";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { SEM_MEDIDA, type Painel, type ContaNoPainel, type MedidaDoReceitaSaude } from "@/lib/negocio";

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

/**
 * A medida do P8 (0079).
 *
 * Mesma disciplina das duas de cima: sem `conta_id`, `e_operador()` conferido
 * dentro da função, e nada de paciente. O `catch` devolve `SEM_MEDIDA` em vez
 * de derrubar o painel inteiro — este bloco é o menos importante da tela, e
 * uma leitura que falha não pode levar o MRR junto.
 */
export async function lerMedidaDoReceitaSaude(): Promise<MedidaDoReceitaSaude> {
  const supabase = await supabaseSessao();
  try {
    return (
      ((await db<MedidaDoReceitaSaude>(
        "negocio.receita_saude",
        supabase.rpc("receita_saude_do_painel"),
      )) as MedidaDoReceitaSaude | null) ?? SEM_MEDIDA
    );
  } catch (e) {
    console.error("[negocio] falhou a medida do Receita Saúde", e);
    return SEM_MEDIDA;
  }
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

// ============================================ a régua e a retenção (OP6)

import type { AvisoPendente, Retencao } from "@/lib/negocio";

/**
 * Os avisos que ainda não saíram.
 *
 * Enquanto não houver provedor de e-mail, esta lista **é** a régua: eu leio,
 * mando o texto, e marco. É a mesma forma do outbox da B9 — a fila existe, os
 * estados existem, e o adaptador é um arquivo que ainda não foi escrito.
 */
export async function lerAvisos(): Promise<AvisoPendente[]> {
  const supabase = await supabaseSessao();
  return (
    (await db<AvisoPendente[]>("negocio.avisos", supabase.rpc("avisos_pendentes"))) ?? []
  );
}

export async function lerRetencao(desde?: string): Promise<Retencao | null> {
  const supabase = await supabaseSessao();
  return (
    (await db<Retencao>(
      "negocio.retencao",
      supabase.rpc("retencao_do_painel", { p_desde: desde ?? null }),
    )) ?? null
  );
}
