import "server-only";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { sessaoAtual } from "@/lib/conta";

/**
 * Quando esta conta foi exportada pela última vez (0062).
 *
 * A função lê a **trilha**, e não uma coluna: a trilha é append-only e
 * carimbada pelo servidor, e uma coluna `exportada_em` em `contas` seria
 * editável pela mesma pessoa de quem a trava protege.
 */
export type Exportacao =
  | { estado: "ok"; quando: string | null; recente: boolean }
  | { estado: "indisponivel"; motivo: string };

const VINTE_E_QUATRO_HORAS = 24 * 60 * 60 * 1000;

export async function ultimaExportacao(): Promise<Exportacao> {
  const supabase = await supabaseSessao();
  const sessao = await sessaoAtual();

  try {
    const quando = await db<string | null>(
      "conta.exportacao_recente",
      supabase.rpc("exportacao_recente", { p_conta: sessao.contaId }),
    );

    // Esta conta de 24 horas é **da tela**, e serve só para dizer o estado e
    // desabilitar o campo. Quem decide é `eliminar_conta`, que refaz a mesma
    // pergunta no banco com o relógio do banco. Se as duas discordarem por um
    // minuto de relógio, a que vale é a de lá — e o erro que volta já vem
    // escrito para ser lido.
    const recente =
      quando !== null && Date.now() - Date.parse(quando) < VINTE_E_QUATRO_HORAS;

    return { estado: "ok", quando, recente };
  } catch (e) {
    console.error("[encerrar] não consegui ler a última exportação", e);

    // Não degrada para "nunca exportou": isso apagaria a diferença entre não
    // ter exportado e não ter conseguido perguntar, numa tela em que essa
    // diferença é a única coisa que separa a pessoa da operação irreversível.
    return {
      estado: "indisponivel",
      motivo: "Não consegui verificar a sua última exportação agora.",
    };
  }
}
