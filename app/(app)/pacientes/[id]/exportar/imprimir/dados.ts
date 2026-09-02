import "server-only";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";

/**
 * A mesma chamada da rota irmã — e é de propósito que seja a mesma.
 *
 * `../route.ts` devolve o jsonb como arquivo; esta função devolve o mesmo jsonb
 * para virar papel. Se um dia as duas divergirem, existirão dois documentos com
 * o mesmo nome — e o paciente que comparar o arquivo com a folha vai encontrar
 * diferenças que ninguém decidiu criar.
 *
 * A restrição judicial continua sendo do banco. `?ciente=1` só aparece na tela
 * depois de ela ler o aviso; se esta tela fosse a guardiã, bastaria digitar a
 * URL.
 */
export type Copia =
  | { estado: "ok"; dados: Record<string, unknown> }
  | { estado: "erro"; restrito: boolean; motivo: string };

export async function copiaDoPaciente(id: string, ciente: boolean): Promise<Copia> {
  const supabase = await supabaseSessao();

  try {
    const dados = await db<Record<string, unknown>>(
      "paciente.exportar.imprimir",
      supabase.rpc("exportar_paciente", {
        p_paciente: id,
        p_ciente_da_restricao: ciente,
      }),
    );

    return { estado: "ok", dados: dados ?? {} };
  } catch (e) {
    const bruto = e instanceof Error ? e.message : String(e);
    const restrito = /restrição judicial/i.test(bruto);

    console.error("[exportar] imprimir", { id, motivo: bruto });

    return {
      estado: "erro",
      restrito,
      motivo: restrito
        ? "Há restrição judicial nesta ficha. Confirme que você conhece a decisão antes de gerar a cópia."
        : "Não consegui montar a cópia agora.",
    };
  }
}
