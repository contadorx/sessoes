import "server-only";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import type { LinhaDaTrilha, TamanhoDaTrilha } from "@/lib/trilha";

/**
 * A leitura da trilha — e por que ela tem um estado "recusada".
 *
 * As duas funções da 0063 **levantam exceção** quando quem pergunta não tem
 * acesso clínico, em vez de devolver zero linhas. Aqui isso é preservado: uma
 * lista vazia numa tela de auditoria é indistinguível de "ninguém acessou
 * nada", e transformar a recusa do banco num array vazio seria desfazer no app
 * exatamente a decisão que a migração tomou.
 *
 * Por isso a leitura **não degrada para vazio** — ao contrário de
 * `avaliacaoPendente()`, que degrada porque a pergunta dela é dispensável. Aqui
 * o erro é conteúdo: a tela mostra o que o banco disse.
 */
export type LeituraDaTrilha =
  | { estado: "ok"; linhas: LinhaDaTrilha[]; tamanho: TamanhoDaTrilha }
  | { estado: "recusada"; motivo: string };

/**
 * A mensagem do banco, sem o contexto que o `db()` prefixa.
 *
 * As frases da 0063 foram escritas para serem lidas por quem abre a tela
 * ("a trilha diz quem abriu a ficha de quem…"). O que não pode chegar à tela é
 * falha de rede disfarçada de explicação.
 */
function mensagemDoBanco(e: unknown): string {
  const bruto = e instanceof Error ? e.message : String(e);
  const limpo = bruto.replace(/^\[[^\]]*\]\s*/, "").trim();

  if (limpo === "" || /fetch|network|timeout|JWT|Failed to/i.test(limpo)) {
    return "Não consegui ler a trilha agora. Tente de novo em um instante.";
  }
  return limpo;
}

/**
 * A trilha no período, com o tamanho total junto.
 *
 * O tamanho vem na mesma leitura de propósito: uma tela que mostra as últimas
 * linhas sem dizer quantas existem parece uma tela que esconde, e a trilha é a
 * peça do produto que não pode parecer isso.
 *
 * O limite de 500 é o mesmo padrão da função. Ele aparece na tela quando morde
 * — um corte silencioso aqui seria a mesma falha de zero linhas em silêncio,
 * só que no fim da lista.
 */
export async function lerTrilha(
  de: string,
  ate: string,
  paciente: string | null = null,
  limite = 500,
): Promise<LeituraDaTrilha> {
  const supabase = await supabaseSessao();

  try {
    const [linhas, tamanho] = await Promise.all([
      db<LinhaDaTrilha[]>(
        "trilha.listar",
        supabase.rpc("minha_trilha", {
          p_de: de,
          p_ate: ate,
          p_paciente: paciente,
          p_limite: limite,
        }),
      ),
      db<TamanhoDaTrilha>("trilha.tamanho", supabase.rpc("tamanho_da_trilha")),
    ]);

    return {
      estado: "ok",
      linhas: linhas ?? [],
      tamanho: tamanho ?? { linhas: 0, primeira: null },
    };
  } catch (e) {
    console.error("[trilha] recusada ou indisponível", e);
    return { estado: "recusada", motivo: mensagemDoBanco(e) };
  }
}
