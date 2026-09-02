"use server";

import { revalidatePath } from "next/cache";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { problemaNaSemana, type Faixa, type Destino } from "@/lib/capacidade";

/**
 * A declaração da semana.
 *
 * Uma ação só, e ela **substitui a semana inteira** — a mesma forma de
 * `definir_links_do_post`. Um "acrescentar faixa" exigiria um "remover faixa", e
 * nenhum dos dois saberia fechar a vigência da semana antiga na mesma
 * transação em que abre a nova. Como a 0055 não tem política de escrita na
 * tabela, essa é a única porta — e é de propósito.
 */

export type Resultado = { estado: "ok" | "erro"; mensagem: string };

const OK = (m: string): Resultado => ({ estado: "ok", mensagem: m });
const ERRO = (m: string): Resultado => ({ estado: "erro", mensagem: m });

const DESTINOS: Destino[] = ["atendimento", "registro", "descanso"];

export async function salvarSemana(_a: Resultado, form: FormData): Promise<Resultado> {
  const profissional = String(form.get("profissional") ?? "").trim();
  if (profissional === "") return ERRO("Não consegui identificar o profissional.");

  const dias = form.getAll("faixa_dia").map(String);
  const inicios = form.getAll("faixa_inicio").map(String);
  const fins = form.getAll("faixa_fim").map(String);
  const destinos = form.getAll("faixa_destino").map(String);

  const faixas: Faixa[] = [];
  for (let i = 0; i < dias.length; i++) {
    const inicio = (inicios[i] ?? "").trim();
    const fim = (fins[i] ?? "").trim();
    // Linha pela metade é ignorada, não gravada em branco — a mesma regra da
    // lista de links da 0051. O formulário manda a lista toda.
    if (inicio === "" || fim === "") continue;

    const d = Number(dias[i]);
    if (!Number.isInteger(d) || d < 0 || d > 6) continue;

    const destino = destinos[i] as Destino;
    faixas.push({
      dia: d,
      inicio,
      fim,
      destino: DESTINOS.includes(destino) ? destino : "atendimento",
    });
  }

  // A tela recusa antes de enviar, com a frase que explica — e o banco
  // continua sendo quem decide. As duas conferências existem porque a de lá é
  // a que vale e a de cá é a que a pessoa consegue ler.
  const problema = problemaNaSemana(faixas);
  if (problema) return ERRO(problema);

  try {
    const supabase = await supabaseSessao();
    await db("capacidade.semana", supabase.rpc("definir_semana", {
      p_profissional: profissional,
      p_janelas: faixas.map((f) => ({
        dia: f.dia,
        inicio: f.inicio,
        fim: f.fim,
        destino: f.destino,
      })),
    }));
  } catch (e) {
    const m = e instanceof Error ? e.message : "";
    if (!m || /fetch|network|timeout|JWT/i.test(m)) {
      return ERRO("Não consegui guardar agora.");
    }
    // As mensagens da 0055 já foram escritas para serem lidas.
    return ERRO(m.replace(/^.*?:\s*/, ""));
  }

  revalidatePath("/perfil/horarios");
  revalidatePath("/comecar");

  return OK(
    faixas.length === 0
      ? "Semana em branco guardada. A partir de hoje, nenhuma hora declarada."
      : "Guardado, valendo de hoje. O que já passou continua como estava declarado na época.",
  );
}
