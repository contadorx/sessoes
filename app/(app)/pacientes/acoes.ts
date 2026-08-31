"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { db, ErroDeBanco } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { sessaoAtual } from "@/lib/conta";
import { validarPaciente } from "@/lib/paciente";
import { hoje } from "@/lib/tempo-servidor";

export type Resultado =
  | { estado: "inicial" }
  | { estado: "erro"; erros: string[] }
  // Salvar cadastro redireciona, então não precisava de "ok". As ações de
  // privacidade (B13) precisam: a resposta do banco — a data até quando o
  // registro fica guardado — é justamente o que a psicóloga vai repassar.
  | { estado: "ok"; mensagem: string };

const INICIAL: Resultado = { estado: "inicial" };

/** Lê os campos do enquadre do formulário. Devolve null quando ela não preencheu. */
function lerEnquadre(form: FormData): { erros: string[]; dados: Record<string, unknown> | null } {
  const hora = String(form.get("hora") ?? "").trim();
  const valorBruto = String(form.get("valor") ?? "").trim().replace(",", ".");

  if (hora === "" && valorBruto === "") return { erros: [], dados: null };

  const erros: string[] = [];
  if (!/^\d{2}:\d{2}$/.test(hora)) erros.push("Informe o horário da sessão.");

  const valor = Number(valorBruto);
  if (!Number.isFinite(valor) || valor < 0) erros.push("Informe o valor da sessão.");

  const dia = Number(form.get("dia_semana"));
  if (!Number.isInteger(dia) || dia < 0 || dia > 6) erros.push("Escolha o dia da semana.");

  const duracao = Number(form.get("duracao_min") ?? 50);
  if (!Number.isInteger(duracao) || duracao < 15 || duracao > 240) {
    erros.push("A duração precisa ficar entre 15 e 240 minutos.");
  }

  const horas = Number(form.get("politica_horas") ?? 24);
  const pct = Number(form.get("politica_percentual") ?? 50);
  if (!Number.isInteger(horas) || horas < 0 || horas > 168) erros.push("Prazo da política inválido.");
  if (!Number.isInteger(pct) || pct < 0 || pct > 100) erros.push("Percentual da política inválido.");

  if (erros.length > 0) return { erros, dados: null };

  return {
    erros: [],
    dados: {
      dia_semana: dia,
      hora,
      duracao_min: duracao,
      valor: valor.toFixed(2), // numeric vai como string; nunca float no caminho
      social: form.get("social") === "on",
      modelo_cobranca: String(form.get("modelo_cobranca") ?? "avulso"),
      politica_horas: horas,
      politica_percentual: pct,
    },
  };
}

export async function criarPaciente(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const sessao = await sessaoAtual();
  if (!sessao.profissionalId) {
    return { estado: "erro", erros: ["Sua conta está sem profissional cadastrado."] };
  }

  const paciente = validarPaciente({
    nome: String(form.get("nome") ?? ""),
    telefone: String(form.get("telefone") ?? ""),
    email: String(form.get("email") ?? ""),
    cpf: String(form.get("cpf") ?? ""),
    estado: String(form.get("estado") ?? "interessado"),
    msg_canal: String(form.get("msg_canal") ?? "whatsapp"),
    msg_modo: String(form.get("msg_modo") ?? "discreto"),
    observacao: String(form.get("observacao") ?? ""),
  });

  const enquadre = lerEnquadre(form);

  if (!paciente.ok || enquadre.erros.length > 0) {
    return {
      estado: "erro",
      erros: [...(paciente.ok ? [] : paciente.erros), ...enquadre.erros],
    };
  }

  const supabase = await supabaseSessao();
  let id: string;

  try {
    const criado = await db(
      "pacientes.criar",
      supabase
        .from("pacientes")
        .insert({ ...paciente.dados, profissional_id: sessao.profissionalId })
        .select("id")
        .limit(1),
    );

    id = (criado ?? [])[0]?.id as string;
    if (!id) return { estado: "erro", erros: ["Não consegui criar o cadastro."] };

    if (enquadre.dados) {
      await db(
        "enquadres.criar",
        supabase.from("enquadres").insert({ ...enquadre.dados, paciente_id: id }),
      );
    }
  } catch (e) {
    return { estado: "erro", erros: [traduzir(e)] };
  }

  revalidatePath("/pacientes");
  redirect(`/pacientes/${id}`);
}

export async function atualizarPaciente(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const id = String(form.get("id") ?? "");
  if (!id) return { estado: "erro", erros: ["Cadastro não identificado."] };

  const paciente = validarPaciente({
    nome: String(form.get("nome") ?? ""),
    telefone: String(form.get("telefone") ?? ""),
    email: String(form.get("email") ?? ""),
    cpf: String(form.get("cpf") ?? ""),
    estado: String(form.get("estado") ?? "interessado"),
    msg_canal: String(form.get("msg_canal") ?? "whatsapp"),
    msg_modo: String(form.get("msg_modo") ?? "discreto"),
    observacao: String(form.get("observacao") ?? ""),
  });

  if (!paciente.ok) return { estado: "erro", erros: paciente.erros };

  const supabase = await supabaseSessao();

  try {
    await db(
      "pacientes.atualizar",
      supabase.from("pacientes").update(paciente.dados).eq("id", id),
    );
  } catch (e) {
    return { estado: "erro", erros: [traduzir(e)] };
  }

  revalidatePath(`/pacientes/${id}`);
  revalidatePath("/pacientes");
  return INICIAL;
}

/**
 * O mecanismo que a D14 vai usar: **nunca** se edita o valor de um enquadre
 * vigente. Fecha-se o atual com um motivo e abre-se o próximo. O histórico do
 * que foi combinado, e quando, fica de pé — e o índice parcial do banco garante
 * que só existe um aberto por vez.
 */
export async function substituirEnquadre(
  _anterior: Resultado,
  form: FormData,
): Promise<Resultado> {
  const pacienteId = String(form.get("paciente_id") ?? "");
  const abertoId = String(form.get("enquadre_aberto_id") ?? "");
  const motivo = String(form.get("motivo_fim") ?? "reajuste");

  if (!pacienteId) return { estado: "erro", erros: ["Paciente não identificado."] };

  const enquadre = lerEnquadre(form);
  if (enquadre.erros.length > 0) return { estado: "erro", erros: enquadre.erros };
  if (!enquadre.dados) return { estado: "erro", erros: ["Preencha o novo combinado."] };

  const supabase = await supabaseSessao();
  const dia = hoje();

  try {
    if (abertoId) {
      await db(
        "enquadres.fechar",
        supabase
          .from("enquadres")
          .update({ vigencia_fim: dia, motivo_fim: motivo })
          .eq("id", abertoId)
          .is("vigencia_fim", null),
      );
    }

    await db(
      "enquadres.abrir",
      supabase
        .from("enquadres")
        .insert({ ...enquadre.dados, paciente_id: pacienteId, vigencia_inicio: dia }),
    );
  } catch (e) {
    return { estado: "erro", erros: [traduzir(e)] };
  }

  revalidatePath(`/pacientes/${pacienteId}`);
  return INICIAL;
}

function traduzir(e: unknown): string {
  if (e instanceof ErroDeBanco) {
    if (e.codigo === "23505") return "Já existe um combinado aberto para este paciente.";
    if (e.codigo === "23514") return "Algum valor está fora do permitido.";
    if (e.codigo === "42501") return "Sem permissão para esta operação.";
  }
  console.error("[pacientes] erro não traduzido", e);
  return "Não consegui salvar agora. Tente de novo em instantes.";
}

/**
 * O pedido de exclusão, respondido com honestidade.
 *
 * A mensagem que volta é do banco de propósito: é ela que a psicóloga repassa ao
 * paciente, com a data exata em que o registro pode sair. Improvisar uma
 * explicação sobre a LGPD no meio de uma conversa difícil é como se erra aqui.
 */
export async function esquecerContato(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const id = String(form.get("paciente_id") ?? "");
  if (!id) return { estado: "erro", erros: ["Paciente não identificado."] };

  const supabase = await supabaseSessao();

  try {
    const explicacao = await db<string>(
      "paciente.esquecer_contato",
      supabase.rpc("esquecer_contato", { p_paciente: id }),
    );
    revalidatePath(`/pacientes/${id}`);
    revalidatePath("/pacientes");
    return { estado: "ok", mensagem: explicacao };
  } catch (e) {
    console.error("[paciente] falhou esquecer contato", e);
    return { estado: "erro", erros: ["Não consegui agora. Tente de novo em instantes."] };
  }
}

/**
 * Encerrar.
 *
 * O texto do encerramento é exigido pelo banco, não pelo formulário — a Res. CFP
 * 001/2009 pede o registro de como o acompanhamento terminou, e um prontuário
 * que acaba no silêncio é o que o Conselho aponta como falta.
 */
export async function arquivarPaciente(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const id = String(form.get("paciente_id") ?? "");
  const encerramento = String(form.get("encerramento") ?? "").trim();

  if (!id) return { estado: "erro", erros: ["Paciente não identificado."] };
  if (encerramento.length < 10) {
    return {
      estado: "erro",
      erros: ["Escreva como o acompanhamento terminou — alta, encaminhamento, abandono."],
    };
  }

  const supabase = await supabaseSessao();

  try {
    await db(
      "paciente.arquivar",
      supabase.rpc("arquivar_paciente", { p_paciente: id, p_encerramento: encerramento }),
    );
  } catch (e) {
    console.error("[paciente] falhou arquivar", e);
    return { estado: "erro", erros: ["Não consegui agora. Tente de novo em instantes."] };
  }

  revalidatePath(`/pacientes/${id}`);
  revalidatePath("/pacientes");
  return {
    estado: "ok",
    mensagem: "Ficha encerrada e arquivada. Daqui em diante ela é só leitura.",
  };
}
