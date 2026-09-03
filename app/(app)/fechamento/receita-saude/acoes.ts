"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { sessaoAtual } from "@/lib/conta";

export type Resultado =
  | { estado: "inicial" }
  | { estado: "erro"; erros: string[] }
  | { estado: "ok"; mensagem: string };

/**
 * "Emiti na Receita."
 *
 * O nome importa: não é "emitir". O sistema não emite e não tem como emitir —
 * não existe API pública. Isto **registra o que ela fez** no app da Receita, e
 * a diferença entre as duas coisas é a diferença entre um produto honesto e um
 * que faz alguém levar multa por confiar nele.
 */
export async function marcarEmitido(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const recibo = String(form.get("recibo") ?? "");
  const numero = String(form.get("numero") ?? "").trim();

  if (numero !== "" && (numero.length < 3 || numero.length > 60)) {
    return { estado: "erro", erros: ["O número do recibo tem de 3 a 60 caracteres."] };
  }

  const supabase = await supabaseSessao();
  try {
    await db(
      "rfb.marcar",
      supabase.rpc("marcar_recibo_rfb", {
        p_recibo: recibo,
        p_numero: numero === "" ? null : numero,
      }),
    );
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath("/fechamento/receita-saude");
  return {
    estado: "ok",
    mensagem: numero
      ? "Registrado, com o número. É ele que responde a pergunta daqui a três anos."
      : "Registrado. Se puder, volte e anote o número do recibo — ele vale numa conferência futura.",
  };
}

export async function desmarcar(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const recibo = String(form.get("recibo") ?? "");
  const supabase = await supabaseSessao();

  try {
    await db("rfb.desmarcar", supabase.rpc("desmarcar_recibo_rfb", { p_recibo: recibo }));
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath("/fechamento/receita-saude");
  return { estado: "ok", mensagem: "Voltou para a lista." };
}

/**
 * "Este não precisa de recibo da Receita Saúde."
 *
 * O caso real: repasse de clínica (PJ), que fica fora do Receita Saúde e vai
 * direto ao carnê-leão. Pede motivo porque quem dispensa uma obrigação fiscal
 * precisa poder explicar a si mesma, dois anos depois, por que dispensou.
 */
export async function dispensar(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const recibo = String(form.get("recibo") ?? "");
  const motivo = String(form.get("motivo") ?? "").trim();

  if (motivo.length < 5) {
    return {
      estado: "erro",
      erros: ["Escreva o motivo — é ele que responde à pergunta daqui a dois anos."],
    };
  }

  const supabase = await supabaseSessao();
  try {
    await db(
      "rfb.dispensar",
      supabase.rpc("dispensar_recibo_rfb", { p_recibo: recibo, p_motivo: motivo }),
    );
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath("/fechamento/receita-saude");
  return { estado: "ok", mensagem: "Dispensado, com o motivo registrado." };
}

/** Liga e desliga o modo. Desligar não apaga nada — só para de gerar pendência nova. */
export async function mudarModo(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const ligar = String(form.get("ligar") ?? "") === "1";

  const sessao = await sessaoAtual();
  const supabase = await supabaseSessao();

  try {
    await db(
      "rfb.modo",
      supabase.from("contas").update({ receita_saude: ligar }).eq("id", sessao.contaId),
    );
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath("/fechamento/receita-saude");
  return {
    estado: "ok",
    mensagem: ligar
      ? "Modo ligado. Cada pagamento registrado passa a virar uma pendência de recibo."
      : "Modo desligado. O que já estava na lista continua lá — desligar não apaga histórico.",
  };
}

/**
 * O cartão de emissão: os seis campos do app da Receita, um a um.
 *
 * Vem do banco (`cartao_de_emissao`, migração 0067) e **não é montado aqui**,
 * mesmo com quatro dos seis já carregados na página. A razão é a de sempre:
 * dois lugares montando o mesmo cartão discordariam no dia em que a ocupação
 * mudasse, e o número que ela colaria no app da Receita Federal seria o do
 * lugar errado.
 *
 * A função também recusa conta PJ com a frase escrita — o caminho fiscal de
 * quem atende como pessoa jurídica é a NFS-e, e o cartão não existe para ela.
 */
export type Cartao = {
  cpf: string | null;
  nome: string;
  pago_em: string;
  valor: string;
  ocupacao: string;
  descricao: string;
  estado: string;
  competencia: string;
  sem_cpf: boolean;
};

export type ResultadoCartao =
  | { estado: "inicial" }
  | { estado: "erro"; erros: string[] }
  | { estado: "ok"; cartao: Cartao };

export async function lerCartao(recibo: string): Promise<ResultadoCartao> {
  const supabase = await supabaseSessao();
  try {
    const c = (await db(
      "rfb.cartao",
      supabase.rpc("cartao_de_emissao", { p_recibo: recibo }),
    )) as unknown as Cartao;
    return { estado: "ok", cartao: c };
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }
}

/**
 * O pagador pessoa jurídica.
 *
 * O caso que ninguém no mercado resolve: quando quem paga é uma empresa, o app
 * da Receita **não tem campo de CNPJ**. Hoje isso vira uma dispensa com motivo
 * escrito à mão, diferente toda vez — e daqui a dois anos ninguém sabe por que
 * aquele mês tem um buraco.
 *
 * O motivo passa a ser pré-escrito e continua **obrigatório e gravado**, que é
 * o que responde a pergunta lá na frente. `relatorio_do_pagador_pj` junta o ano
 * inteiro.
 */
export async function dispensarPorPagadorPj(
  _anterior: Resultado,
  form: FormData,
): Promise<Resultado> {
  const recibo = String(form.get("recibo") ?? "");
  if (!recibo) return { estado: "erro", erros: ["Recibo não identificado."] };

  const supabase = await supabaseSessao();
  try {
    await db(
      "rfb.pagador_pj",
      supabase.rpc("dispensar_por_pagador_pj", { p_recibo: recibo }),
    );
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath("/fechamento/receita-saude");
  return {
    estado: "ok",
    mensagem: "Registrado: quem pagou é pessoa jurídica, e o lançamento vai pelo caminho da empresa.",
  };
}

/**
 * O ritmo com que ela quer ser lembrada — e ele **se declara provisório na
 * tela**.
 *
 * O default é `mensal`, e mensal é **palpite**: ele sai da pergunta V3 da
 * conversa com a psicóloga, que ainda não aconteceu. Um número que não se
 * apresenta como palpite vira regra por hábito antes de alguém opinar sobre
 * ele — é a mesma manobra do "3" da anamnese, que este projeto já registrou
 * como antipadrão.
 *
 * Mudar o ritmo **não reenvia nada do passado**: ele decide quando o próximo
 * lembrete sai, e não recalcula pendência nenhuma.
 */
export async function mudarRitmo(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const ritmo = String(form.get("ritmo") ?? "");
  if (!["sessao", "semanal", "mensal", "fevereiro"].includes(ritmo)) {
    return { estado: "erro", erros: ["Ritmo desconhecido."] };
  }

  const sessao = await sessaoAtual();
  const supabase = await supabaseSessao();

  try {
    await db(
      "rfb.ritmo",
      supabase.from("contas").update({ ritmo_recibo: ritmo }).eq("id", sessao.contaId),
    );
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath("/fechamento/receita-saude");
  return {
    estado: "ok",
    mensagem: "Ritmo mudado. Nada do que já passou foi reenviado — ele vale daqui para a frente.",
  };
}

function legivel(e: unknown): string {
  const m = e instanceof Error ? e.message : String(e);
  const limpo = m.replace(/^.*?:\s*/, "").trim();
  return limpo.length > 3 && limpo.length < 300
    ? limpo.charAt(0).toUpperCase() + limpo.slice(1)
    : "Não consegui. Tente de novo.";
}
