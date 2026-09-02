"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { supabaseServer } from "@/lib/supabase/server";

export type ResultadoConfirmacao =
  | { estado: "inicial" }
  | { estado: "erro"; mensagem: string }
  | { estado: "ok"; resposta: "sim" | "nao" };

/**
 * Os motivos, traduzidos aqui e nunca vindos do banco.
 *
 * Mesmo padrão da B19 e da B21: a função devolve um código fechado e o
 * TypeScript escolhe a frase. Repassar `sqlerrm` para uma tela pública
 * entregaria nome de função, de coluna e de tabela a quem tem um token — e o
 * dia em que uma mensagem de erro do Postgres vazasse numa página de paciente
 * seria o dia em que a página deixaria de ser transacional.
 */
const MOTIVOS: Record<string, string> = {
  inexistente: "Este link não existe. Confira se ele veio inteiro.",
  expirada: "Este link não vale mais. Peça um novo para quem te enviou.",
  resposta_invalida: "Não entendi a resposta. Tente de novo.",
  // O caso que acontece de verdade: ela mudou a agenda enquanto a página
  // estava aberta. Não é erro de ninguém, e a frase evita essa leitura.
  sessao_nao_encontrada:
    "Esse horário mudou desde que a página abriu. Atualize e veja como ficou.",
};

/**
 * Confirmar ou avisar que não vai — e as duas coisas param aqui.
 *
 * Roda como `anon`: quem clica não tem conta e não vai criar uma para dizer
 * "sim". Toda a proteção é do banco — a função `confirmar_pelo_link` é a única
 * porta, e ela acha a sessão pelo `paciente_id` **do link**, nunca pelo id que
 * veio neste formulário.
 *
 * **O que este arquivo deliberadamente não tem é um terceiro botão.** Cancelar
 * a sessão daqui seria o caminho óbvio e é o que a maioria dos produtos faz —
 * e cobraria a política de falta de alguém por uma decisão que o software
 * tomou sozinho, num clique feito às onze da noite. Recusar diz que ele não
 * vem; o que isso faz com a hora é dela, com a política congelada na sessão.
 */
export async function responderConfirmacao(
  _anterior: ResultadoConfirmacao,
  form: FormData,
): Promise<ResultadoConfirmacao> {
  const token = String(form.get("token") ?? "");
  const sessao = String(form.get("sessao") ?? "");
  const bruta = String(form.get("resposta") ?? "");

  if (bruta !== "sim" && bruta !== "nao") {
    return { estado: "erro", mensagem: MOTIVOS.resposta_invalida };
  }

  const supabase = supabaseServer();

  const r = (await db(
    "paciente.confirmar",
    supabase.rpc("confirmar_pelo_link", {
      p_token: token,
      p_sessao: sessao,
      p_resposta: bruta,
    }),
  )) as unknown as { ok?: boolean; motivo?: string };

  if (!r?.ok) {
    return {
      estado: "erro",
      mensagem: MOTIVOS[r?.motivo ?? ""] ?? "Não consegui responder. Tente de novo.",
    };
  }

  revalidatePath(`/p/agora/${token}`);
  return { estado: "ok", resposta: bruta };
}
