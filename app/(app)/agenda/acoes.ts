"use server";

import { revalidatePath } from "next/cache";
import { db, ErroDeBanco } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { sessaoAtual } from "@/lib/conta";
import { inicioDoDiaSP } from "@/lib/tempo";

/** O instante exato de um "dia + hora" no fuso de São Paulo. */
function inicioDaSessao(dia: string, hora: string): Date {
  const [h, m] = hora.split(":").map(Number);
  return new Date(inicioDoDiaSP(dia).getTime() + (h * 60 + m) * 60_000);
}

export type Resultado =
  | { estado: "inicial" }
  | { estado: "ok"; mensagem: string }
  | { estado: "erro"; erros: string[] };

const TIPOS = ["ferias", "feriado", "bloqueio"] as const;

/**
 * Criar uma ausência **não mexe no enquadre** — o gatilho no banco apaga só as
 * previsões daquele período. Remover devolve a recorrência, porque a
 * materialização é idempotente e roda de novo.
 */
export async function criarAusencia(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const sessao = await sessaoAtual();
  if (!sessao.profissionalId) {
    return { estado: "erro", erros: ["Sua conta está sem profissional cadastrado."] };
  }

  const tipo = String(form.get("tipo") ?? "ferias");
  const inicio = String(form.get("inicio") ?? "");
  const fim = String(form.get("fim") ?? "") || inicio;
  const motivo = String(form.get("motivo") ?? "").trim() || null;

  const erros: string[] = [];
  if (!(TIPOS as readonly string[]).includes(tipo)) erros.push("Tipo desconhecido.");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(inicio)) erros.push("Informe a data inicial.");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(fim)) erros.push("Data final inválida.");
  if (inicio && fim && fim < inicio) erros.push("A data final é anterior à inicial.");
  if (erros.length > 0) return { estado: "erro", erros };

  const supabase = await supabaseSessao();

  try {
    await db(
      "excecoes.criar",
      supabase.from("excecoes_agenda").insert({
        profissional_id: sessao.profissionalId,
        tipo,
        inicio,
        fim,
        motivo,
      }),
    );
  } catch (e) {
    console.error("[ausencias] falhou", e);
    return {
      estado: "erro",
      erros: [e instanceof ErroDeBanco ? "Não consegui registrar." : "Erro inesperado."],
    };
  }

  revalidatePath("/agenda");
  return { estado: "ok", mensagem: "Registrado. As sessões do período saíram da agenda." };
}

export async function removerAusencia(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const id = String(form.get("id") ?? "");
  if (!id) return { estado: "erro", erros: ["Não identifiquei o registro."] };

  const supabase = await supabaseSessao();

  try {
    await db("excecoes.remover", supabase.from("excecoes_agenda").delete().eq("id", id));
  } catch (e) {
    console.error("[ausencias] falhou remover", e);
    return { estado: "erro", erros: ["Não consegui remover."] };
  }

  revalidatePath("/agenda");
  return { estado: "ok", mensagem: "Removido. A recorrência voltou." };
}

/**
 * Cancela — e **não diz se foi cedo ou tarde**. Quem classifica é o banco,
 * comparando o relógio do servidor com a política gravada na própria sessão.
 * Se a classificação viesse daqui, a multa de falta seria negociável por quem
 * soubesse abrir o inspetor do navegador.
 */
export async function cancelarSessao(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const id = String(form.get("id") ?? "");
  const por = String(form.get("por") ?? "paciente");
  if (!id) return { estado: "erro", erros: ["Sessão não identificada."] };

  const supabase = await supabaseSessao();

  try {
    const resultado = await db(
      "sessoes.cancelar",
      supabase.rpc("cancelar_sessao", { p_sessao: id, p_por: por }),
    );

    revalidatePath("/agenda");

    return {
      estado: "ok",
      mensagem:
        resultado === "cancelada_tarde"
          ? "Cancelamento tardio — a política se aplica."
          : "Cancelado dentro do prazo, sem cobrança.",
    };
  } catch (e) {
    console.error("[sessoes] falhou cancelar", e);
    return { estado: "erro", erros: [traduzir(e)] };
  }
}

const MARCAVEIS = ["prevista", "confirmada", "realizada", "falta"] as const;

/** Confirmar, marcar realizada, marcar falta — e desfazer, voltando a prevista. */
export async function marcarSessao(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const id = String(form.get("id") ?? "");
  const estado = String(form.get("estado") ?? "");

  if (!id) return { estado: "erro", erros: ["Sessão não identificada."] };
  if (!(MARCAVEIS as readonly string[]).includes(estado)) {
    return { estado: "erro", erros: ["Estado desconhecido."] };
  }

  const supabase = await supabaseSessao();

  try {
    await db("sessoes.marcar", supabase.from("sessoes").update({ estado }).eq("id", id));
  } catch (e) {
    console.error("[sessoes] falhou marcar", e);
    return { estado: "erro", erros: [traduzir(e)] };
  }

  revalidatePath("/agenda");
  return { estado: "ok", mensagem: "Pronto." };
}

/** Encaixe manual num horário livre. A fila (B7) vai fazer isso sozinha. */
export async function criarEncaixe(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const sessao = await sessaoAtual();
  if (!sessao.profissionalId) {
    return { estado: "erro", erros: ["Sua conta está sem profissional cadastrado."] };
  }

  const pacienteId = String(form.get("paciente_id") ?? "");
  const dia = String(form.get("dia") ?? "");
  const hora = String(form.get("hora") ?? "");
  const duracao = Number(form.get("duracao_min") ?? 50);
  const valorBruto = String(form.get("valor") ?? "").trim().replace(",", ".");

  const erros: string[] = [];
  if (!pacienteId) erros.push("Escolha o paciente.");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dia)) erros.push("Informe o dia.");
  if (!/^\d{2}:\d{2}$/.test(hora)) erros.push("Informe o horário.");
  if (!Number.isInteger(duracao) || duracao < 15 || duracao > 240) erros.push("Duração inválida.");

  const valor = Number(valorBruto);
  if (!Number.isFinite(valor) || valor < 0) erros.push("Informe o valor.");
  if (erros.length > 0) return { estado: "erro", erros };

  const inicio = inicioDaSessao(dia, hora);
  const fim = new Date(inicio.getTime() + duracao * 60_000);

  const supabase = await supabaseSessao();

  try {
    await db(
      "sessoes.encaixe",
      supabase.from("sessoes").insert({
        conta_id: sessao.contaId,
        profissional_id: sessao.profissionalId,
        paciente_id: pacienteId,
        inicio: inicio.toISOString(),
        fim: fim.toISOString(),
        origem: "encaixe",
        estado: "prevista",
        valor: valor.toFixed(2),
      }),
    );
  } catch (e) {
    console.error("[sessoes] falhou encaixe", e);
    return { estado: "erro", erros: [traduzir(e)] };
  }

  revalidatePath("/agenda");
  return { estado: "ok", mensagem: "Encaixe marcado." };
}

function traduzir(e: unknown): string {
  if (e instanceof ErroDeBanco) {
    const m = e.message;
    if (/sobreposicao|exclusion/i.test(m) || e.codigo === "23P01") {
      return "Já existe sessão nesse horário.";
    }
    if (/ainda n[aã]o come/i.test(m)) return "A sessão ainda não começou.";
    if (/j[aá] aconteceu/i.test(m)) return "Esta sessão já aconteceu.";
    if (/n[aã]o vira presen/i.test(m)) return "Cancelamento não vira presença — reabra como prevista.";
  }
  return "Não consegui completar agora. Tente de novo em instantes.";
}

/** Estende a janela rolante. É o que o cron vai chamar todo dia. */
export async function estenderJanela(): Promise<Resultado> {
  const supabase = await supabaseSessao();

  try {
    // Sem parâmetro de propósito: a função resolve a conta pelo `conta_atual()`
    // do banco. Tenant nunca vem do cliente.
    await db("agenda.materializar", supabase.rpc("materializar_conta"));
  } catch (e) {
    console.error("[agenda] falhou materializar", e);
    return { estado: "erro", erros: ["Não consegui estender a agenda."] };
  }

  revalidatePath("/agenda");
  return { estado: "ok", mensagem: "Agenda estendida." };
}
