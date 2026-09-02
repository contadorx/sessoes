"use server";

import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";

export type Resultado =
  | { estado: "inicial" }
  | { estado: "erro"; erros: string[] }
  | { estado: "ok"; mensagem: string };

/**
 * Encerrar a conta (B41).
 *
 * **Esta ação não valida nada, e isso é a decisão.** A função `eliminar_conta`
 * recusa em três casos — só a dona, o nome da conta digitado, e exportação nas
 * últimas 24 horas — e cada recusa vem com a frase que explica por quê. Repetir
 * as três aqui criaria dois lugares onde a regra mora, e o dia em que eles
 * discordarem é o dia em que a tela deixa alguém tentar o que o banco recusa,
 * ou recusa o que o banco deixaria passar.
 *
 * O que a tela faz é **mostrar o estado**: quando foi a última exportação, e
 * qual é o nome exato a digitar. Mostrar o estado e validar o estado não são a
 * mesma coisa.
 *
 * A confirmação vai crua, sem `trim`: a função faz `btrim` dos dois lados. Um
 * corte a mais aqui seria um comportamento a mais para ninguém conferir.
 */
export async function encerrarConta(
  _anterior: Resultado,
  form: FormData,
): Promise<Resultado> {
  const confirmacao = String(form.get("confirmacao") ?? "");

  try {
    const supabase = await supabaseSessao();

    // A frase que volta fala da guarda e da data até quando ela continua
    // responsável. É o último texto do produto que essa pessoa lê, e ele é do
    // banco — que é o único lugar onde ainda havia como contar as sessões.
    const frase = await db<string>(
      "conta.eliminar",
      supabase.rpc("eliminar_conta", { p_confirmacao: confirmacao }),
    );

    return {
      estado: "ok",
      mensagem:
        frase ??
        "Conta encerrada. A guarda do prontuário continua sendo sua: o arquivo que você exportou é a sua cópia.",
    };
  } catch (e) {
    const bruto = e instanceof Error ? e.message : String(e);
    const limpo = bruto.replace(/^\[[^\]]*\]\s*/, "").trim();

    console.error("[encerrar] recusado", { motivo: bruto });

    if (limpo === "" || /fetch|network|timeout|JWT|Failed to/i.test(limpo)) {
      return { estado: "erro", erros: ["Não consegui encerrar agora. Nada foi apagado."] };
    }

    // As mensagens da 0062 já foram escritas para serem lidas — inclusive a
    // que diz o nome exato da conta e a que diz a data da última exportação.
    return { estado: "erro", erros: [limpo] };
  }
}
