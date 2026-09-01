"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { hoje } from "@/lib/tempo-servidor";
import { inicioDoDiaSP } from "@/lib/tempo";
import { deCentavos } from "@/lib/dinheiro";
import { lerHistorico, type Direcao, type ModoTitulo } from "@/lib/calendario";

export type Resultado =
  | { estado: "inicial" }
  | { estado: "erro"; erros: string[] }
  | { estado: "ok"; mensagem: string };

const DIRECOES: Direcao[] = ["ler", "escrever", "duas_vias"];
const MODOS: ModoTitulo[] = ["discreto", "iniciais", "completo"];

/**
 * Preparar a conexão.
 *
 * Cria a linha do calendário e guarda as preferências. **Não** autoriza nada:
 * a autorização é o passo da Google, que ainda não existe. A tela diz isso, em
 * vez de mostrar um "ligado" que não sincroniza.
 */
export async function prepararCalendario(
  _anterior: Resultado,
  form: FormData,
): Promise<Resultado> {
  const profissional = String(form.get("profissional_id") ?? "").trim();
  if (profissional === "") return { estado: "erro", erros: ["Sem profissional."] };

  const supabase = await supabaseSessao();
  try {
    await db(
      "calendario.preparar",
      supabase.rpc("ligar_calendario", {
        p_profissional: profissional,
        p_email: null,
        p_calendario_externo: "primary",
      }),
    );
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath("/perfil/integracoes");
  return {
    estado: "ok",
    mensagem: "Pronto. Falta só a autorização da Google — as suas escolhas já estão guardadas.",
  };
}

/** Direção e modo de título. Trocar o modo reescreve o que ainda está por vir. */
export async function ajustarCalendario(
  _anterior: Resultado,
  form: FormData,
): Promise<Resultado> {
  const profissional = String(form.get("profissional_id") ?? "").trim();
  const direcao = String(form.get("direcao") ?? "") as Direcao;
  const modo = String(form.get("modo_titulo") ?? "") as ModoTitulo;

  const erros: string[] = [];
  if (profissional === "") erros.push("Sem profissional.");
  if (!DIRECOES.includes(direcao)) erros.push("Escolha o que sincronizar.");
  if (!MODOS.includes(modo)) erros.push("Escolha o que o evento vai dizer.");
  if (erros.length > 0) return { estado: "erro", erros };

  const supabase = await supabaseSessao();
  try {
    await db(
      "calendario.ajustar",
      supabase.rpc("ajustar_calendario", {
        p_profissional: profissional,
        p_direcao: direcao,
        p_modo_titulo: modo,
      }),
    );
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath("/perfil/integracoes");
  return {
    estado: "ok",
    mensagem:
      modo === "discreto"
        ? "Salvo. As sessões daqui para a frente vão como “Sessão”, sem nome — as que já foram ficam como estão na sua agenda."
        : "Salvo. Vale para as sessões daqui para a frente.",
  };
}

export async function pausarCalendario(
  _anterior: Resultado,
  form: FormData,
): Promise<Resultado> {
  const profissional = String(form.get("profissional_id") ?? "").trim();
  const pausar = String(form.get("pausar") ?? "") === "1";

  const supabase = await supabaseSessao();
  try {
    await db(
      "calendario.pausar",
      supabase.rpc("pausar_calendario", { p_profissional: profissional, p_pausar: pausar }),
    );
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath("/perfil/integracoes");
  return {
    estado: "ok",
    mensagem: pausar
      ? "Pausado. As horas que eu já conhecia continuam bloqueadas aqui."
      : "Voltou a sincronizar.",
  };
}

/**
 * Desconectar.
 *
 * Apaga a autorização e as horas que eu tinha lido. **Não** apaga os eventos
 * que já foram para a agenda dela — tirar duzentos eventos do calendário de
 * alguém porque ela clicou em "desconectar" seria destruição por efeito
 * colateral.
 */
export async function desligarCalendario(
  _anterior: Resultado,
  form: FormData,
): Promise<Resultado> {
  const profissional = String(form.get("profissional_id") ?? "").trim();
  if (String(form.get("confirma") ?? "") !== "desconectar") {
    return { estado: "erro", erros: ['Escreva "desconectar" para confirmar.'] };
  }

  const supabase = await supabaseSessao();
  try {
    await db(
      "calendario.desligar",
      supabase.rpc("desligar_calendario", { p_profissional: profissional }),
    );
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  revalidatePath("/perfil/integracoes");
  return {
    estado: "ok",
    mensagem:
      "Desconectado. O que já estava na sua agenda continua lá — apagar é decisão sua, no Google.",
  };
}

// =============================================== o histórico que veio de fora

type PacienteConhecido = { id: string; nome: string };

const chave = (s: string) =>
  s
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();

/**
 * Trazer o histórico.
 *
 * Não cria paciente. Uma planilha de dois anos tem o mesmo nome escrito de
 * cinco jeitos, e criar por semelhança encheria a base de duplicatas que ela
 * descobriria meses depois, com o histórico partido entre duas fichas. Quem
 * não é encontrado volta como erro daquela linha, com o nome, para ela
 * cadastrar ou corrigir.
 */
export async function importarHistorico(
  _anterior: Resultado,
  form: FormData,
): Promise<Resultado> {
  const texto = String(form.get("colagem") ?? "");
  if (texto.trim() === "") return { estado: "erro", erros: ["Cole o histórico primeiro."] };

  const leitura = lerHistorico(texto, hoje());
  const supabase = await supabaseSessao();

  let pacientes: PacienteConhecido[];
  try {
    pacientes =
      ((await db(
        "calendario.pacientes",
        supabase.from("pacientes").select("id, nome").limit(2000),
      )) as unknown as PacienteConhecido[]) ?? [];
  } catch (e) {
    return { estado: "erro", erros: [legivel(e)] };
  }

  const porNome = new Map<string, string>();
  for (const p of pacientes) porNome.set(chave(p.nome), p.id);

  const erros: string[] = leitura.erros.map((e) => `linha ${e.linha}: ${e.motivo} — “${e.texto}”`);
  const linhas: Record<string, unknown>[] = [];

  for (const s of leitura.sessoes) {
    const id = porNome.get(chave(s.paciente));
    if (!id) {
      erros.push(
        `linha ${s.linha}: não encontrei “${s.paciente}” nos seus pacientes — cadastre antes, ou corrija o nome`,
      );
      continue;
    }
    const inicio = new Date(inicioDoDiaSP(s.dia).getTime());
    const [h, m] = s.hora.split(":").map(Number);
    inicio.setUTCMinutes(inicio.getUTCMinutes() + h * 60 + m);

    linhas.push({
      paciente_id: id,
      inicio: inicio.toISOString(),
      estado: s.estado,
      valor: s.valorCentavos === null ? 0 : Number(deCentavos(s.valorCentavos)),
    });
  }

  if (linhas.length === 0) {
    return {
      estado: "erro",
      erros: erros.length > 0 ? erros : ["Não achei nenhuma linha para importar."],
    };
  }

  let saida: { importadas: number; repetidas: number; erros: { linha: number; motivo: string }[] };
  try {
    saida = (await db(
      "calendario.importar",
      supabase.rpc("importar_historico", { p_linhas: linhas }),
    )) as unknown as typeof saida;
  } catch (e) {
    return { estado: "erro", erros: [legivel(e), ...erros] };
  }

  for (const e of saida.erros ?? []) erros.push(`${e.motivo}`);

  const partes = [`${saida.importadas} ${saida.importadas === 1 ? "sessão" : "sessões"} no histórico`];
  if (saida.repetidas > 0) partes.push(`${saida.repetidas} que já estavam lá`);

  if (erros.length > 0) {
    return {
      estado: "erro",
      erros: [`Importei ${partes.join(" e ")}. O que ficou de fora:`, ...erros],
    };
  }

  revalidatePath("/perfil/integracoes");
  revalidatePath("/pacientes");
  return {
    estado: "ok",
    mensagem: `${partes.join(" e ")}. Elas entram na linha do tempo do paciente e não mexem em nenhum número do financeiro.`,
  };
}

function legivel(e: unknown): string {
  const m = e instanceof Error ? e.message : String(e);
  const limpo = m.replace(/^.*?:\s*/, "").trim();
  return limpo.length > 3 && limpo.length < 300
    ? limpo.charAt(0).toUpperCase() + limpo.slice(1)
    : "Não consegui. Tente de novo.";
}
