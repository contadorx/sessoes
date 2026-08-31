import "server-only";
import { db } from "@/lib/db";
import { supabaseServico } from "@/lib/supabase/servico";

/**
 * O que roda uma vez por dia.
 *
 * Três rotinas que existiam e não tinham quem lhes desse corda. Nenhuma é
 * urgente ao minuto — por isso saem do cron de cinco minutos e ficam aqui, numa
 * passada só, de manhã cedo no horário de São Paulo.
 *
 * A ordem importa: **materializar antes de agendar lembrete.** A janela rolante
 * pode criar hoje a sessão de daqui a oito semanas; se o lembrete rodasse antes,
 * a sessão criada nesta mesma execução só seria lembrada amanhã. Não é um bug
 * que apareceria hoje — apareceria no dia em que a agenda encostasse na borda da
 * janela, que é justamente quando ninguém está olhando.
 */

export type RelatorioDiario = {
  materializadas: number;
  lembretes: number;
  expurgadas: number;
};

/** Mensagem entregue não precisa ficar para sempre (LGPD, doc 07). */
const DIAS_DE_RETENCAO = 180;

export async function passadaDiaria(): Promise<RelatorioDiario> {
  const supabase = supabaseServico();

  const materializadas =
    (await db<number>("diario.materializar", supabase.rpc("materializar_tudo"))) ?? 0;

  const lembretes =
    (await db<number>("diario.lembretes", supabase.rpc("agendar_lembretes"))) ?? 0;

  const expurgadas =
    (await db<number>("diario.expurgar", supabase.rpc("expurgar_mensagens", {
      p_dias: DIAS_DE_RETENCAO,
    }))) ?? 0;

  return { materializadas, lembretes, expurgadas };
}
