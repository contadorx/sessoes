"use server";

import { revalidatePath } from "next/cache";
import { db, ErroDeBanco } from "@/lib/db";
import { fraseDaOferta } from "@/lib/canal";
import { caixaMarcada } from "@/lib/formato";
import { supabaseSessao } from "@/lib/supabase/server";
import { sessaoAtual } from "@/lib/conta";
import { montarJanela } from "@/lib/janela";
import { cutucarDespacho } from "@/lib/mensageria/worker";

export type Resultado =
  | { estado: "inicial" }
  | { estado: "ok"; mensagem: string }
  | { estado: "erro"; erros: string[] };

function lerJanela(form: FormData) {
  const dias = form
    .getAll("dias")
    .map((d) => Number(d))
    .filter((d) => Number.isInteger(d) && d >= 0 && d <= 6);

  return montarJanela({
    dias,
    de: String(form.get("de") ?? ""),
    ate: String(form.get("ate") ?? ""),
  });
}

export async function entrarNaFila(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const pacienteId = String(form.get("paciente_id") ?? "");
  if (!pacienteId) return { estado: "erro", erros: ["Escolha o paciente."] };

  const de = String(form.get("de") ?? "");
  const ate = String(form.get("ate") ?? "");
  if (de && ate && ate <= de) {
    return { estado: "erro", erros: ["O fim da janela é antes do começo."] };
  }

  const supabase = await supabaseSessao();

  try {
    await db(
      "fila.entrar",
      supabase.from("fila_encaixe").insert({
        paciente_id: pacienteId,
        janelas: lerJanela(form),
        topa_antecipar: caixaMarcada(form, "topa_antecipar"),
      }),
    );
  } catch (e) {
    return { estado: "erro", erros: [traduzir(e)] };
  }

  revalidatePath("/encaixes");
  return { estado: "ok", mensagem: "Entrou na fila." };
}

export async function atualizarNaFila(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const id = String(form.get("id") ?? "");
  if (!id) return { estado: "erro", erros: ["Registro não identificado."] };

  const de = String(form.get("de") ?? "");
  const ate = String(form.get("ate") ?? "");
  if (de && ate && ate <= de) {
    return { estado: "erro", erros: ["O fim da janela é antes do começo."] };
  }

  const prioridade = Number(form.get("prioridade") ?? 0);
  const supabase = await supabaseSessao();

  try {
    await db(
      "fila.atualizar",
      supabase
        .from("fila_encaixe")
        .update({
          janelas: lerJanela(form),
          topa_antecipar: caixaMarcada(form, "topa_antecipar"),
          prioridade: Number.isInteger(prioridade) ? prioridade : 0,
          ativo: caixaMarcada(form, "ativo"),
        })
        .eq("id", id),
    );
  } catch (e) {
    return { estado: "erro", erros: [traduzir(e)] };
  }

  revalidatePath("/encaixes");
  return { estado: "ok", mensagem: "Salvo." };
}

export async function sairDaFila(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const id = String(form.get("id") ?? "");
  if (!id) return { estado: "erro", erros: ["Registro não identificado."] };

  const supabase = await supabaseSessao();

  try {
    await db("fila.sair", supabase.from("fila_encaixe").delete().eq("id", id));
  } catch (e) {
    return { estado: "erro", erros: [traduzir(e)] };
  }

  revalidatePath("/encaixes");
  return { estado: "ok", mensagem: "Saiu da fila." };
}

/**
 * Abre a vaga e dispara a cascata. Quem escolhe para quem vai a oferta é o
 * motor, pela regra de prioridade dela — não esta tela.
 *
 * A frase do fim **lê o estado real da mensagem** antes de falar no passado.
 * Ver `fraseDaOferta`: dizer "enviada" sobre uma oferta que a janela de
 * silêncio só vai soltar às 8h é uma afirmação sobre uma pessoa que não
 * recebeu nada, e é a partir dela que ela decide não avisar ninguém.
 */
export async function oferecerEmCascata(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const sessaoId = String(form.get("sessao_id") ?? "");
  if (!sessaoId) return { estado: "erro", erros: ["Vaga não identificada."] };

  const supabase = await supabaseSessao();

  try {
    const oferta = await db<string | null>(
      "vaga.abrir",
      supabase.rpc("abrir_vaga", { p_sessao: sessaoId }),
    );

    // A oferta já está no banco e a mensagem já está enfileirada. Isto só
    // tenta fazê-la sair agora em vez de esperar o cron; falhar aqui não
    // desfaz nada.
    await cutucarDespacho();

    revalidatePath(`/encaixes/${sessaoId}`);
    revalidatePath("/encaixes");

    if (!oferta) return { estado: "ok", mensagem: "Ninguém da fila cabe nesta vaga agora." };

    // Depois do `cutucarDespacho`, de propósito: se a mensagem saiu no empurrão,
    // é isso que a leitura encontra, e a frase pode falar no passado com razão.
    return { estado: "ok", mensagem: await fraseDoQueAconteceu(supabase, oferta) };
  } catch (e) {
    return { estado: "erro", erros: [traduzir(e)] };
  }
}

/** Lê a mensagem da oferta e o relógio dela; degrada para o presente, nunca para o passado. */
async function fraseDoQueAconteceu(
  supabase: Awaited<ReturnType<typeof supabaseSessao>>,
  ofertaId: string,
): Promise<string> {
  try {
    const [msgs, ofertas] = await Promise.all([
      db(
        "oferta.mensagem",
        supabase.from("mensagens").select("estado").eq("chave_idem", `oferta:${ofertaId}`).limit(1),
      ),
      db(
        "oferta.relogio",
        supabase.from("ofertas").select("enviar_em").eq("id", ofertaId).limit(1),
      ),
    ]);

    return fraseDaOferta({
      mensagem: ((msgs ?? []) as { estado: string }[])[0]?.estado ?? null,
      enviarEm: ((ofertas ?? []) as { enviar_em: string | null }[])[0]?.enviar_em ?? null,
    });
  } catch (e) {
    // A leitura da confirmação falhou; a oferta existe. Afirmar envio aqui
    // seria exatamente o defeito que esta build fecha.
    console.error("[fila] não consegui conferir se a mensagem saiu", e);
    return "Oferta preparada. Não consegui conferir se a mensagem já saiu.";
  }
}

/**
 * Registra a resposta que chegou por fora (por telefone, no corredor). Quando o
 * WhatsApp entrar, o webhook chama exatamente esta mesma função do banco.
 */
export async function responderPorEla(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const ofertaId = String(form.get("oferta_id") ?? "");
  const resposta = String(form.get("resposta") ?? "");
  const sessaoId = String(form.get("sessao_id") ?? "");

  if (!ofertaId || !["aceita", "recusada"].includes(resposta)) {
    return { estado: "erro", erros: ["Resposta inválida."] };
  }

  const supabase = await supabaseSessao();

  try {
    await db(
      "oferta.responder",
      supabase.rpc("responder_oferta", { p_oferta: ofertaId, p_resposta: resposta }),
    );

    // Uma recusa faz a fila andar, e a próxima oferta já nasceu na fila de
    // envio. Sair agora é a diferença entre a cascata parecer viva ou lenta.
    await cutucarDespacho();
  } catch (e) {
    return { estado: "erro", erros: [traduzir(e)] };
  }

  revalidatePath(`/encaixes/${sessaoId}`);
  revalidatePath("/agenda");

  return {
    estado: "ok",
    mensagem: resposta === "aceita" ? "Vaga preenchida." : "Registrado. A fila andou.",
  };
}

/** O cron chama isto; a tela também, para não esperar o relógio numa demo. */
export async function expirarOfertas(_anterior: Resultado): Promise<Resultado> {
  const supabase = await supabaseSessao();

  try {
    const n = await db("ofertas.expirar", supabase.rpc("expirar_ofertas"));
    revalidatePath("/encaixes");
    return { estado: "ok", mensagem: `${n ?? 0} oferta(s) venceram e a fila andou.` };
  } catch (e) {
    return { estado: "erro", erros: [traduzir(e)] };
  }
}

export async function salvarRegras(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const sessao = await sessaoAtual();
  if (sessao.papel !== "dona") {
    return { estado: "erro", erros: ["Só a dona da conta muda a regra da fila."] };
  }

  const regra = String(form.get("regra_prioridade") ?? "");
  const timeout = Number(form.get("oferta_timeout_min") ?? 40);
  const inicio = String(form.get("silencio_inicio") ?? "21:00");
  const fim = String(form.get("silencio_fim") ?? "08:00");

  const erros: string[] = [];
  if (!["mais_tempo_sem_sessao", "ordem_de_entrada"].includes(regra)) erros.push("Regra desconhecida.");
  if (!Number.isInteger(timeout) || timeout < 5 || timeout > 720) {
    erros.push("O prazo da oferta precisa ficar entre 5 e 720 minutos.");
  }
  if (!/^\d{2}:\d{2}$/.test(inicio) || !/^\d{2}:\d{2}$/.test(fim)) erros.push("Horário inválido.");
  if (erros.length > 0) return { estado: "erro", erros };

  const supabase = await supabaseSessao();

  try {
    await db(
      "conta.salvarRegras",
      supabase
        .from("contas")
        .update({
          regra_prioridade: regra,
          oferta_timeout_min: timeout,
          silencio_inicio: inicio,
          silencio_fim: fim,
        })
        .eq("id", sessao.contaId),
    );
  } catch (e) {
    return { estado: "erro", erros: [traduzir(e)] };
  }

  revalidatePath("/encaixes");
  return { estado: "ok", mensagem: "Regra salva." };
}

function traduzir(e: unknown): string {
  if (e instanceof ErroDeBanco) {
    const m = e.message;
    if (e.codigo === "23505") return "Esse paciente já está na fila.";
    if (/outra conta/i.test(m)) return "Paciente de outra conta.";
    if (/cancelado/i.test(m)) return "Só horário cancelado vira vaga.";
    if (/já passou|ja passou/i.test(m)) return "Essa hora já passou.";
    if (/respondida/i.test(m)) return "Essa oferta já foi respondida.";
    if (/não está mais aberta|nao esta mais aberta/i.test(m)) return "A vaga não está mais aberta.";
    if (/deixou de estar livre/i.test(m)) return "O horário deixou de estar livre.";
  }
  console.error("[fila] erro não traduzido", e);
  return "Não consegui completar agora. Tente de novo em instantes.";
}
