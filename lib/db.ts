import type { PostgrestError } from "@supabase/supabase-js";

/**
 * A lei nº 1 da engenharia deste projeto (doc 05, cicatriz nº 1 do FinanceiroX).
 *
 * `supabase-js` NÃO lança erro: toda operação devolve `{ data, error }`, e código
 * que ignora `error` falha em silêncio. Foi o defeito mais repetido nas 51 rodadas
 * de auditoria do FinanceiroX.
 *
 * Regra: toda leitura ou escrita passa por aqui. Chamada direta ao client fora
 * deste helper reprova em revisão — e o ESLint reprova antes.
 */

export class ErroDeBanco extends Error {
  readonly contexto: string;
  readonly codigo?: string;
  readonly detalhe?: string;

  constructor(contexto: string, erro: PostgrestError) {
    super(`[${contexto}] ${erro.message}`);
    this.name = "ErroDeBanco";
    this.contexto = contexto;
    this.codigo = erro.code;
    this.detalhe = erro.details;
  }
}

type Resposta<T> = { data: T | null; error: PostgrestError | null };

/** Executa a operação, loga o erro com contexto e **lança**. Nunca devolve null silencioso. */
export async function db<T>(
  contexto: string,
  operacao: PromiseLike<Resposta<T>>,
): Promise<T> {
  const { data, error } = await operacao;

  if (error) {
    console.error("[db] falhou", {
      contexto,
      codigo: error.code,
      mensagem: error.message,
      detalhe: error.details,
      dica: error.hint,
    });
    throw new ErroDeBanco(contexto, error);
  }

  return data as T;
}

/** Variante para operações que não retornam linha (insert sem select, por exemplo). */
export async function dbVoid(
  contexto: string,
  operacao: PromiseLike<Resposta<unknown>>,
): Promise<void> {
  await db(contexto, operacao);
}
