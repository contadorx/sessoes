"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { sessaoAtual } from "@/lib/conta";
import { motivoValido, fraseDoMotivoCurto } from "@/lib/negocio";

/**
 * As ações do painel do negócio.
 *
 * Cada uma chama uma função da migração 0050, e **nenhuma delas escreve numa
 * tabela**. É deliberado: as regras deste domínio — uma assinatura viva por
 * conta, cancelamento com motivo, mudar de plano preservando a faixa
 * anterior — não cabem numa cláusula de RLS, e um `PATCH` do PostgREST
 * passaria por cima de todas elas.
 *
 * A conferência de operador aparece **duas vezes**, aqui e no banco, e as duas
 * são necessárias por motivos diferentes: aqui para a tela falhar com frase em
 * português; lá porque é a que vale. Se um dia esta camada sumir, a de lá
 * continua barrando.
 */

export type Resultado = { estado: "ok" | "erro"; mensagem: string };

const OK = (m: string): Resultado => ({ estado: "ok", mensagem: m });
const ERRO = (m: string): Resultado => ({ estado: "erro", mensagem: m });

/** 404 é a resposta da rota; aqui basta recusar. */
async function exigirOperador() {
  const sessao = await sessaoAtual();
  if (!sessao.operador) throw new Error("não autorizado");
  return sessao;
}

function texto(form: FormData, campo: string): string {
  return String(form.get(campo) ?? "").trim();
}

/**
 * Traduz o erro do banco para uma frase que se lê.
 *
 * As exceções da 0050 já foram escritas em português e para serem lidas — "esta
 * conta já tem assinatura viva", "cancelamento sem motivo escrito é churn sem
 * causa". Então o caminho normal é **mostrar a mensagem do banco**, e não
 * substituí-la por um genérico: quem escreveu a regra escreveu a explicação
 * junto, e traduzir de novo aqui só faria as duas divergirem.
 */
function comoErro(e: unknown, generico: string): Resultado {
  const m = e instanceof Error ? e.message : "";
  // Erros de infraestrutura não vão para a tela com o texto do Postgres.
  if (!m || /fetch|network|timeout|JWT/i.test(m)) return ERRO(generico);
  return ERRO(m);
}

// ============================================ assinatura

export async function abrirAssinatura(_a: Resultado, form: FormData): Promise<Resultado> {
  try {
    await exigirOperador();
    const supabase = await supabaseSessao();

    await db("negocio.abrir_assinatura", supabase.rpc("abrir_assinatura", {
      p_conta: texto(form, "conta"),
      p_plano: texto(form, "plano"),
      p_ciclo: texto(form, "ciclo") || "mensal",
      p_origem: texto(form, "origem") || "painel",
      p_valor_centavos: null,
      p_trial: form.get("trial") === "on",
    }));

    revalidatePath("/negocio");
    return OK("Assinatura aberta, e o plano da conta acompanhou.");
  } catch (e) {
    return comoErro(e, "Não consegui abrir a assinatura agora.");
  }
}

export async function cancelarAssinatura(_a: Resultado, form: FormData): Promise<Resultado> {
  const motivo = texto(form, "motivo");
  if (!motivoValido(motivo)) return ERRO(fraseDoMotivoCurto());

  try {
    await exigirOperador();
    const supabase = await supabaseSessao();
    await db("negocio.cancelar_assinatura", supabase.rpc("cancelar_assinatura", {
      p_assinatura: texto(form, "assinatura"),
      p_motivo: motivo,
    }));
    revalidatePath("/negocio");
    return OK("Assinatura cancelada. A conta voltou ao Grátis e continua com tudo o que é registro.");
  } catch (e) {
    return comoErro(e, "Não consegui cancelar agora.");
  }
}

export async function mudarPlano(_a: Resultado, form: FormData): Promise<Resultado> {
  const motivo = texto(form, "motivo");
  if (!motivoValido(motivo)) return ERRO(fraseDoMotivoCurto());

  try {
    await exigirOperador();
    const supabase = await supabaseSessao();
    await db("negocio.mudar_plano", supabase.rpc("mudar_plano", {
      p_conta: texto(form, "conta"),
      p_plano: texto(form, "plano"),
      p_motivo: motivo,
    }));
    revalidatePath("/negocio");
    return OK("Plano trocado. A faixa anterior fica no histórico — o MRR do mês passado não muda.");
  } catch (e) {
    return comoErro(e, "Não consegui mudar o plano agora.");
  }
}

// ============================================ fatura

export async function emitirFatura(_a: Resultado, form: FormData): Promise<Resultado> {
  try {
    await exigirOperador();
    const supabase = await supabaseSessao();
    await db("negocio.emitir_fatura", supabase.rpc("emitir_fatura", {
      p_assinatura: texto(form, "assinatura"),
      p_competencia: texto(form, "competencia") || null,
      p_vencimento: texto(form, "vencimento") || null,
    }));
    revalidatePath("/negocio");
    return OK("Fatura emitida.");
  } catch (e) {
    return comoErro(e, "Não consegui emitir a fatura agora.");
  }
}

export async function baixarFatura(_a: Resultado, form: FormData): Promise<Resultado> {
  try {
    await exigirOperador();
    const supabase = await supabaseSessao();
    await db("negocio.baixar_fatura", supabase.rpc("baixar_fatura", {
      p_fatura: texto(form, "fatura"),
    }));
    revalidatePath("/negocio");
    return OK("Fatura baixada. A data do pagamento é a do servidor.");
  } catch (e) {
    return comoErro(e, "Não consegui baixar a fatura agora.");
  }
}

export async function estornarFatura(_a: Resultado, form: FormData): Promise<Resultado> {
  const motivo = texto(form, "motivo");
  if (!motivoValido(motivo)) return ERRO("Escreva o motivo do estorno — sem ele não se audita depois.");

  try {
    await exigirOperador();
    const supabase = await supabaseSessao();
    await db("negocio.estornar_fatura", supabase.rpc("estornar_fatura", {
      p_fatura: texto(form, "fatura"),
      p_motivo: motivo,
    }));
    revalidatePath("/negocio");
    return OK("Fatura estornada.");
  } catch (e) {
    return comoErro(e, "Não consegui estornar agora.");
  }
}

export async function cancelarFatura(_a: Resultado, form: FormData): Promise<Resultado> {
  try {
    await exigirOperador();
    const supabase = await supabaseSessao();
    await db("negocio.cancelar_fatura", supabase.rpc("cancelar_fatura", {
      p_fatura: texto(form, "fatura"),
    }));
    revalidatePath("/negocio");
    return OK("Fatura cancelada.");
  } catch (e) {
    return comoErro(e, "Não consegui cancelar a fatura agora.");
  }
}

// ============================================ conta, custo e preço

export async function marcarContaDeTeste(_a: Resultado, form: FormData): Promise<Resultado> {
  try {
    await exigirOperador();
    const supabase = await supabaseSessao();
    const marcar = form.get("marcar") === "sim";

    await db("negocio.marcar_teste", supabase.rpc("marcar_conta_de_teste", {
      p_conta: texto(form, "conta"),
      p_e_teste: marcar,
    }));
    revalidatePath("/negocio");
    return OK(
      marcar
        ? "Marcada como teste: sai das métricas e continua na lista."
        : "Desmarcada — volta a contar no MRR.",
    );
  } catch (e) {
    return comoErro(e, "Não consegui mudar a marca agora.");
  }
}

export async function lancarCustoFixo(_a: Resultado, form: FormData): Promise<Resultado> {
  const rubrica = texto(form, "rubrica");
  if (rubrica.length < 2) return ERRO("A rubrica precisa de um nome.");

  // Centavos como inteiro, sempre. O campo da tela é em reais porque é assim
  // que eu leio a fatura do fornecedor; a conversão acontece aqui, uma vez.
  const reais = Number(String(form.get("valor") ?? "").replace(",", "."));
  if (!Number.isFinite(reais) || reais < 0) return ERRO("Valor inválido.");

  try {
    await exigirOperador();
    const supabase = await supabaseSessao();
    await db("negocio.lancar_custo", supabase.rpc("lancar_custo_fixo", {
      p_mes: texto(form, "mes"),
      p_rubrica: rubrica,
      p_centavos: Math.round(reais * 100),
      p_nota: texto(form, "nota") || null,
    }));
    revalidatePath("/negocio/custos");
    return OK("Custo lançado.");
  } catch (e) {
    return comoErro(e, "Não consegui lançar o custo agora.");
  }
}

export async function definirPrecoCanal(_a: Resultado, form: FormData): Promise<Resultado> {
  const milesimos = Number(String(form.get("milesimos") ?? ""));
  if (!Number.isInteger(milesimos) || milesimos < 0) {
    return ERRO("O preço vai em milésimos de centavo — um e-mail a 0,2 centavo é 200.");
  }

  try {
    await exigirOperador();
    const supabase = await supabaseSessao();
    await db("negocio.definir_preco", supabase.rpc("definir_preco_canal", {
      p_canal: texto(form, "canal"),
      p_vigencia: texto(form, "vigencia"),
      p_milesimos: milesimos,
      p_fonte: texto(form, "fonte") || null,
    }));
    revalidatePath("/negocio/custos");
    return OK("Preço declarado a partir dessa vigência. O que já passou fica como estava.");
  } catch (e) {
    return comoErro(e, "Não consegui declarar o preço agora.");
  }
}
