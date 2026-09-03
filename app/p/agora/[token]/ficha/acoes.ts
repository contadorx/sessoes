"use server";

import { db } from "@/lib/db";
import { supabaseServer } from "@/lib/supabase/server";
import { hoje } from "@/lib/tempo-servidor";
import { validarFicha, type EntradaFicha } from "@/lib/ficha";

export type ResultadoFicha =
  | { estado: "inicial" }
  | { estado: "erro"; erros: string[]; porCampo?: Record<string, string> }
  | { estado: "ok" };

/**
 * A pré-ficha, do lado de quem preenche.
 *
 * Roda como `anon`: quem abre o link não tem conta aqui e não vai criar uma
 * para escrever o próprio CPF. A proteção inteira está no banco — `salvar_ficha`
 * é a única porta, o token é a chave, e ela recusa qualquer campo que não seja
 * administrativo.
 *
 * **O que sobe para o banco é montado a partir de `validarFicha`, e não do
 * `FormData`.** A diferença importa: repassar o formulário inteiro deixaria a
 * lista de campos ser decidida pelo HTML, e o dia em que alguém acrescentasse um
 * `<input name="...">` a mais ele viajaria junto. Assim, o que não passou pela
 * validação não existe daqui para cima — e o banco ainda recusa, de novo.
 */
export async function salvarFicha(
  _anterior: ResultadoFicha,
  form: FormData,
): Promise<ResultadoFicha> {
  const token = String(form.get("token") ?? "");

  const entrada: EntradaFicha = {
    nome: String(form.get("nome") ?? ""),
    nascimento: String(form.get("nascimento") ?? ""),
    cpf: String(form.get("cpf") ?? ""),
    telefone: String(form.get("telefone") ?? ""),
    email: String(form.get("email") ?? ""),
    msg_canal: String(form.get("msg_canal") ?? "whatsapp"),
    msg_modo: String(form.get("msg_modo") ?? "discreto"),
    responsavel_nome: String(form.get("responsavel_nome") ?? ""),
    responsavel_documento: String(form.get("responsavel_documento") ?? ""),
    responsavel_telefone: String(form.get("responsavel_telefone") ?? ""),
  };

  const v = validarFicha(entrada, hoje());
  if (!v.ok) return { estado: "erro", erros: v.erros, porCampo: v.porCampo };

  const supabase = supabaseServer();

  try {
    await db(
      "ficha.salvar",
      supabase.rpc("salvar_ficha", { p_token: token, p_dados: v.dados }),
    );
  } catch (e) {
    console.error("[ficha] falhou salvar", e);
    return {
      estado: "erro",
      erros: ["Não consegui guardar agora. Tente de novo em instantes."],
    };
  }

  return { estado: "ok" };
}
