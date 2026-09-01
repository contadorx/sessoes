"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { sessaoAtual } from "@/lib/conta";
import { tipoDaChave, apenasAscii } from "@/lib/pix";

export type Resultado =
  | { estado: "inicial" }
  | { estado: "erro"; erros: string[] }
  | { estado: "ok"; mensagem: string };

/**
 * Guarda a chave PIX dela.
 *
 * A validação é do formato, não da existência: não há como saber daqui se a
 * chave existe no arranjo do Banco Central. O que dá para impedir é o erro mais
 * comum — colar o CPF com ponto e traço, ou o telefone sem o +55 — que produz um
 * código que só falha no celular do paciente.
 */
export async function salvarPix(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const chave = String(form.get("pix_chave") ?? "").trim();
  const nome = String(form.get("pix_nome") ?? "").trim();
  const cidade = String(form.get("pix_cidade") ?? "").trim();

  const sessao = await sessaoAtual();
  if (sessao.papel !== "dona") {
    return { estado: "erro", erros: ["Só a dona da conta muda os dados de recebimento."] };
  }

  const supabase = await supabaseSessao();

  // Apagar a chave é uma escolha legítima: volta a cobrar por fora.
  if (chave === "") {
    await db(
      "conta.pix.limpar",
      supabase.from("contas").update({ pix_chave: null }).eq("id", sessao.contaId).select("id"),
    );
    revalidatePath("/perfil");
    revalidatePath("/agenda");
    return { estado: "ok", mensagem: "Chave removida. As cobranças voltam a ser sem PIX." };
  }

  const erros: string[] = [];

  if (tipoDaChave(chave) === null) {
    erros.push(
      "Não reconheci essa chave. CPF e CNPJ só com números, telefone com +55 na frente " +
        "(+5511900000001), e-mail inteiro, ou a chave aleatória como o banco mostra.",
    );
  }

  if (nome.length < 2) erros.push("Escreva o nome de quem recebe, como está na conta.");
  if (cidade.length < 2) erros.push("A cidade é obrigatória no padrão do Banco Central.");

  if (erros.length > 0) return { estado: "erro", erros };

  await db(
    "conta.pix.salvar",
    supabase
      .from("contas")
      .update({
        pix_chave: chave,
        // Cortados aqui e não só na geração: melhor ela ver na tela o que vai
        // aparecer para o paciente do que descobrir depois que o nome saiu pela
        // metade.
        pix_nome: apenasAscii(nome, 25),
        pix_cidade: apenasAscii(cidade, 15),
      })
      .eq("id", sessao.contaId)
      .select("id"),
  );

  revalidatePath("/perfil");
  revalidatePath("/agenda");
  return { estado: "ok", mensagem: "Pronto. As cobranças passam a sair com o PIX." };
}

/** Os três relógios da conta: silêncio, atraso da cobrança e lembrete. */
export async function salvarRitmo(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const sessao = await sessaoAtual();
  if (sessao.papel !== "dona") {
    return { estado: "erro", erros: ["Só a dona da conta muda estes ajustes."] };
  }

  const atraso = Number(form.get("cobranca_atraso_min") ?? 60);
  const lembrete = Number(form.get("lembrete_horas") ?? 24);
  const dia = Number(form.get("mensalidade_dia") ?? 1);
  const cobraSessao = String(form.get("cobra_sessao") ?? "") === "1";

  if (!Number.isInteger(atraso) || atraso < 0 || atraso > 1440) {
    return { estado: "erro", erros: ["A espera antes do aviso de cobrança vai de 0 a 1440 minutos."] };
  }
  if (!Number.isInteger(lembrete) || lembrete < 0 || lembrete > 72) {
    return { estado: "erro", erros: ["O lembrete vai de 0 (desligado) a 72 horas."] };
  }
  // Até 28 porque fevereiro existe: um "dia 30" nunca chegaria em fevereiro, e a
  // mensalidade daquele mês simplesmente não sairia — em silêncio.
  if (!Number.isInteger(dia) || dia < 1 || dia > 28) {
    return { estado: "erro", erros: ["O dia da mensalidade vai de 1 a 28."] };
  }

  const supabase = await supabaseSessao();

  await db(
    "conta.ritmo",
    supabase
      .from("contas")
      .update({
        cobranca_atraso_min: atraso,
        lembrete_horas: lembrete,
        mensalidade_dia: dia,
        cobra_sessao: cobraSessao,
      })
      .eq("id", sessao.contaId)
      .select("id"),
  );

  revalidatePath("/perfil");
  return { estado: "ok", mensagem: "Ajustado." };
}

/**
 * Como ela assina.
 *
 * O CRP e o CPF não são enfeite de perfil: sem eles o recibo não serve para
 * reembolso nem para imposto de renda, e a pessoa descobre isso no balcão do
 * convênio. Por isso a validação é do formato, e a tela diz para que serve cada
 * campo em vez de só nomeá-lo.
 */
export async function salvarAssinatura(
  _anterior: Resultado,
  form: FormData,
): Promise<Resultado> {
  const assinaComo = String(form.get("assina_como") ?? "").trim();
  const crp = String(form.get("crp") ?? "").trim();
  const documento = String(form.get("documento") ?? "").replace(/\D/g, "");
  const cidade = String(form.get("cidade") ?? "").trim();

  const sessao = await sessaoAtual();
  if (!sessao.profissionalId) {
    return { estado: "erro", erros: ["Sua conta ainda não tem profissional."] };
  }

  if (documento !== "" && documento.length !== 11 && documento.length !== 14) {
    return {
      estado: "erro",
      erros: ["CPF tem 11 dígitos e CNPJ tem 14. Pode digitar com pontos — eu tiro."],
    };
  }

  const supabase = await supabaseSessao();

  await db(
    "conta.assinatura",
    supabase
      .from("profissionais")
      .update({
        assina_como: assinaComo || null,
        crp: crp || null,
        documento: documento || null,
      })
      .eq("id", sessao.profissionalId)
      .select("id"),
  );

  if (sessao.papel === "dona") {
    await db(
      "conta.cidade",
      supabase
        .from("contas")
        .update({ cidade: cidade || null })
        .eq("id", sessao.contaId)
        .select("id"),
    );
  }

  revalidatePath("/perfil");
  revalidatePath("/fechamento/documentos");
  return { estado: "ok", mensagem: "Salvo. Os próximos documentos já saem assim." };
}

/**
 * O ritmo da régua.
 *
 * Os degraus são poucos e o teto é do banco (no máximo três). Isto não é
 * limitação de interface: uma régua com sete degraus não é lembrete, é
 * perseguição — e o produto existe para tirar o constrangimento da relação, não
 * para transferi-lo do lado dela para o lado do paciente.
 */
export async function salvarRegua(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const sessao = await sessaoAtual();
  if (sessao.papel !== "dona") {
    return { estado: "erro", erros: ["Só a dona da conta muda estes ajustes."] };
  }

  const ativa = String(form.get("regua_ativa") ?? "") === "1";
  const escolha = String(form.get("regua_dias") ?? "7,21");

  const dias = escolha
    .split(",")
    .map((d) => Number(d.trim()))
    .filter((d) => Number.isInteger(d) && d >= 1 && d <= 180);

  if (dias.length === 0 || dias.length > 3) {
    return { estado: "erro", erros: ["Escolha de um a três lembretes."] };
  }

  const supabase = await supabaseSessao();

  await db(
    "conta.regua",
    supabase
      .from("contas")
      .update({ regua_ativa: ativa, regua_dias: dias })
      .eq("id", sessao.contaId)
      .select("id"),
  );

  revalidatePath("/perfil");
  revalidatePath("/recebimentos");
  return { estado: "ok", mensagem: "Ajustado." };
}
