"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { sessaoAtual } from "@/lib/conta";
import { lerColagem } from "@/lib/importacao";
import { deCentavos } from "@/lib/dinheiro";
import { hoje } from "@/lib/tempo-servidor";

export type ResultadoImport =
  | { estado: "inicial" }
  | { estado: "erro"; erros: string[] }
  | { estado: "ok"; criados: number; comHorario: number; ignorados: string[] };

/** Teto por colagem. Acima disso é migração de sistema, não primeiro dia. */
const LIMITE = 200;

/**
 * Grava a colagem.
 *
 * O parsing acontece **de novo aqui**, e não se confia no que a tela mandou. A
 * pré-visualização é conveniência de quem está olhando; o servidor lê o texto
 * cru pelo mesmo caminho, porque quem manda o formulário pode ser qualquer um.
 *
 * Cada paciente é inserido sozinho, e o erro de um não derruba os outros. Uma
 * importação transacional que aborta na linha 27 devolve a pessoa ao início com
 * a sensação de ter perdido meia hora — e ela não volta.
 */
export async function importarPacientes(
  _anterior: ResultadoImport,
  form: FormData,
): Promise<ResultadoImport> {
  const texto = String(form.get("colagem") ?? "");
  const politicaHoras = Number(form.get("politica_horas") ?? 24);
  const politicaPercentual = Number(form.get("politica_percentual") ?? 50);

  if (texto.trim() === "") {
    return { estado: "erro", erros: ["Cole a lista antes de importar."] };
  }

  const { pacientes, erros } = lerColagem(texto);

  if (pacientes.length === 0) {
    return {
      estado: "erro",
      erros:
        erros.length > 0
          ? erros.slice(0, 5).map((e) => `linha ${e.linha}: ${e.motivo}`)
          : ["Não encontrei ninguém nessa lista."],
    };
  }

  if (pacientes.length > LIMITE) {
    return {
      estado: "erro",
      erros: [`São ${pacientes.length} pessoas de uma vez. Faça em partes de até ${LIMITE}.`],
    };
  }

  const sessao = await sessaoAtual();
  if (!sessao.profissionalId) {
    return { estado: "erro", erros: ["Sua conta ainda não tem profissional."] };
  }

  const supabase = await supabaseSessao();
  const ignorados: string[] = erros.map((e) => `linha ${e.linha}: ${e.motivo}`);
  let criados = 0;
  let comHorarioCriado = 0;

  for (const p of pacientes) {
    try {
      const [novo] = (await db(
        "importacao.paciente",
        supabase
          .from("pacientes")
          .insert({
            profissional_id: sessao.profissionalId,
            nome: p.nome,
            telefone: p.telefone,
            estado: "em_atendimento",
            // Discreto é o padrão em toda porta de entrada, inclusive nesta.
            msg_canal: p.telefone ? "whatsapp" : "nao_avisar",
            msg_modo: "discreto",
          })
          .select("id"),
      )) as unknown as { id: string }[];

      criados += 1;

      if (novo && p.diaSemana !== null && p.hora !== null && p.valorCentavos !== null) {
        await db(
          "importacao.enquadre",
          supabase.from("enquadres").insert({
            paciente_id: novo.id,
            dia_semana: p.diaSemana,
            hora: p.hora,
            valor: deCentavos(p.valorCentavos),
            politica_horas: politicaHoras,
            politica_percentual: politicaPercentual,
            vigencia_inicio: hoje(),
          }),
        );
        comHorarioCriado += 1;
      } else if (novo && p.diaSemana !== null) {
        ignorados.push(`${p.nome}: horário anotado, mas sem valor — defina na ficha`);
      }
    } catch (e) {
      console.error("[importacao] falhou uma linha", { nome: p.nome, e });
      ignorados.push(`${p.nome}: não consegui cadastrar (nome repetido?)`);
    }
  }

  revalidatePath("/pacientes");
  revalidatePath("/agenda");
  revalidatePath("/comecar");

  return { estado: "ok", criados, comHorario: comHorarioCriado, ignorados };
}
