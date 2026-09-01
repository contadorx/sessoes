import "server-only";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { hoje } from "@/lib/tempo-servidor";
import { prazoDoAno, diasEntre, faseDoPrazo } from "@/lib/receitasaude";

export type Alarme = { pendentes: number; urgente: boolean };

/**
 * O alarme de fevereiro, no menu.
 *
 * Ele olha o **ano anterior**, não o corrente: o que está prestes a vencer é
 * sempre o retroativo do ano que passou. Entre janeiro e o último dia de
 * fevereiro esse número é o que separa "resolvo depois" de R$ 100 por recibo —
 * e uma tela que ela pode passar meses sem abrir não serve de aviso.
 *
 * Falhar aqui não pode derrubar o app inteiro: se a consulta não responder, o
 * menu aparece sem o número. O alarme é importante; o acesso à agenda é mais.
 */
export async function alarmeFiscal(): Promise<Alarme> {
  const vazio: Alarme = { pendentes: 0, urgente: false };

  try {
    const dia = hoje();
    const ano = Number(dia.slice(0, 4)) - 1;

    const supabase = await supabaseSessao();
    const bruto = (await db(
      "rfb.alarme",
      supabase.rpc("receita_saude_do_ano", { p_ano: ano }),
    )) as unknown as {
      ligado: boolean;
      pendentes: { n: number };
      vencidos: { n: number };
    } | null;

    if (!bruto?.ligado) return vazio;

    const pendentes = bruto.pendentes.n;
    if (pendentes === 0) return vazio;

    const dias = diasEntre(dia, prazoDoAno(ano));
    return { pendentes, urgente: faseDoPrazo(dias, pendentes) !== "tranquilo" };
  } catch (e) {
    console.error("[receita-saude] não consegui ler o alarme", e);
    return vazio;
  }
}
