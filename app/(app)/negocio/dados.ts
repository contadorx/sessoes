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
