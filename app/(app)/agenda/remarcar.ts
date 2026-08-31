"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import type { Custo, Opcao } from "@/lib/remarcacao";

/**
 * As ações da remarcação guiada (B21).
 *
 * Separadas de `acoes.ts` porque devolvem outra coisa: a de abrir não termina
 * numa mensagem, e sim **num link com opções e um aviso de custo** — que é o
 * conteúdo inteiro desta feature.
 */

export type ResultadoRemarcar =
  | { estado: "inicial" }
  | { estado: "erro"; erros: string[] }
  | { estado: "aberta"; token: string; opcoes: Opcao[]; custo: Custo | null }
  | { estado: "trocada"; mensagem: string };

type LinhaOpcao = { inicio: string; fim: string; motivo: string };

/**
 * Abre (ou renova) a remarcação e devolve o que a tela precisa mostrar.
 *
 * A ordem das duas leituras importa pouco tecnicamente e muito na tela: o custo
 * vem junto para que ela leia "isto vai gerar cobrança de R$ 100" **antes** de
 * mandar o link, e não depois de a pessoa já ter escolhido.
 */
export async function abrirRemarcacao(
  _anterior: ResultadoRemarcar,
  form: FormData,
): Promise<ResultadoRemarcar> {
  const sessao = String(form.get("sessao") ?? "");
  const supabase = await supabaseSessao();

  let token: string;
  try {
    token = (await db(
      "remarcacao.abrir",
      supabase.rpc("abrir_remarcacao", { p_sessao: sessao }),
    )) as unknown as string;
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  const [linhas, custo] = await Promise.all([
    db("remarcacao.opcoes", supabase.rpc("opcoes_de_remarcacao", { p_sessao: sessao, p_max: 3 })),
    db("remarcacao.custo", supabase.rpc("custo_da_remarcacao", { p_sessao: sessao })),
  ]);

  const opcoes = ((linhas ?? []) as unknown as LinhaOpcao[]).map((o) => ({
    inicio: o.inicio,
    motivo: o.motivo,
    livre: true,
  }));

  revalidatePath("/agenda");
  return {
    estado: "aberta",
    token,
    opcoes,
    custo: (custo ?? null) as unknown as Custo | null,
  };
}

/**
 * Ela remarca ali mesmo, com a pessoa na frente.
 *
 * Vai pela mesma porta do link: `remarcar_presencial` abre e escolhe numa
 * transação, e o gatilho carimba a origem como presencial porque há sessão
 * autenticada. Não existe caminho em que a hora seja escolhida sem passar pela
 * lista que o sistema ofereceu.
 */
export async function remarcarAgora(
  _anterior: ResultadoRemarcar,
  form: FormData,
): Promise<ResultadoRemarcar> {
  const sessao = String(form.get("sessao") ?? "");
  const inicio = String(form.get("inicio") ?? "");

  const supabase = await supabaseSessao();

  let r: { ok?: boolean; motivo?: string };
  try {
    r = (await db(
      "remarcacao.presencial",
      supabase.rpc("remarcar_presencial", { p_sessao: sessao, p_inicio: inicio }),
    )) as unknown as { ok?: boolean; motivo?: string };
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  if (!r?.ok) {
    return { estado: "erro", erros: [MOTIVOS[r?.motivo ?? ""] ?? "Não consegui trocar."] };
  }

  revalidatePath("/agenda");
  return {
    estado: "trocada",
    mensagem:
      "Trocado. A hora que vagou já foi para a fila — se alguém da lista de espera aceitar, ela nem chega a ficar vazia.",
  };
}

export async function cancelarRemarcacao(
  _anterior: ResultadoRemarcar,
  form: FormData,
): Promise<ResultadoRemarcar> {
  const id = String(form.get("remarcacao") ?? "");
  const supabase = await supabaseSessao();

  try {
    await db("remarcacao.cancelar", supabase.rpc("cancelar_remarcacao", { p_id: id }));
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath("/agenda");
  return { estado: "trocada", mensagem: "Link cancelado. Ninguém consegue mais usá-lo." };
}

const MOTIVOS: Record<string, string> = {
  ocupada: "Essa hora acabou de ser ocupada — a fila foi mais rápida. Escolha outra.",
  nao_oferecida: "Essa hora não estava na lista.",
  expirada: "O link venceu. Abra outro.",
  cancelada: "Esta troca já tinha sido cancelada.",
  passou: "Essa hora já passou.",
  sessao_mudou: "A sessão mudou de estado — recarregue a agenda.",
  inexistente: "Não achei esta troca.",
};

/**
 * A mensagem do Postgres já é escrita em português e para gente (0035). Levar
 * isso à tela é melhor do que traduzir de novo aqui e ter duas versões da mesma
 * frase envelhecendo em lugares diferentes.
 */
function legivel(e: unknown): string {
  const m = e instanceof Error ? e.message : String(e);
  const limpo = m.replace(/^.*?:\s*/, "").trim();
  return limpo.length > 3 && limpo.length < 240
    ? limpo.charAt(0).toUpperCase() + limpo.slice(1)
    : "Não consegui. Tente de novo.";
}
