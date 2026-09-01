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
  mensalidades: number;
  regua: number;
  vencidos: number;
  pastas: number;
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

  // A régua depois dos lembretes de sessão, e as duas antes do expurgo. Ordem
  // sem consequência hoje — mas o expurgo apaga mensagens antigas, e a régua
  // conta quantos lembretes já saíram. Deixar a contagem acontecer antes de
  // qualquer apagamento evita que um expurgo futuro reabra uma régua encerrada.
  // A mensalidade do mês (B20). Vem antes da régua para que, no dia 1º, a
  // cobrança já esteja na tela "Em aberto" quando ela abrir o sistema — e não
  // só no dia seguinte.
  //
  // Nascer no mesmo dia não a coloca na régua de hoje: a régua conta os dias a
  // partir da abertura da cobrança, e o primeiro degrau é de uma semana. Quem
  // acabou de ser cobrado não é lembrado no mesmo minuto.
  const mensalidades =
    (await db<number>("diario.mensalidades", supabase.rpc("agendar_mensalidades"))) ?? 0;

  const regua =
    (await db<number>("diario.regua", supabase.rpc("agendar_regua"))) ?? 0;

  // O retroativo do Receita Saúde fecha no último dia de fevereiro do ano
  // seguinte (B24). Depois disso a pendência vira `vencido` — e é essa mudança
  // que faz a tela parar de oferecer "emiti na Receita" para algo que a Receita
  // já não aceita. Uma vez por dia basta: o prazo é anual, não horário.
  const vencidos =
    (await db<number>("diario.vencer_recibos", supabase.rpc("vencer_recibos_rfb"))) ?? 0;

  // A pasta do contador (B25): fecha o mês anterior para quem marcou hoje como
  // o dia. Vem depois de tudo o que produz número — materialização,
  // mensalidade, régua — porque um fechamento é uma fotografia, e fotografar
  // antes de a cena estar montada é o jeito de mandar ao contador um mês pela
  // metade. Rodar duas vezes no mesmo dia não gera duas pastas.
  const pastas =
    (await db<number>("diario.pastas", supabase.rpc("gerar_pastas_do_dia"))) ?? 0;

  const expurgadas =
    (await db<number>("diario.expurgar", supabase.rpc("expurgar_mensagens", {
      p_dias: DIAS_DE_RETENCAO,
    }))) ?? 0;

  return { materializadas, lembretes, mensalidades, regua, vencidos, pastas, expurgadas };
}
