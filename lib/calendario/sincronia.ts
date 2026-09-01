import "server-only";
import { db } from "@/lib/db";
import { supabaseServico } from "@/lib/supabase/servico";
import {
  adaptadorDoCalendario,
  DIAS_A_LER,
  type AdaptadorCalendario,
  type AcaoEspelho,
} from "./adaptadores";

/**
 * A passada do calendário.
 *
 * Duas metades independentes, e a ordem entre elas importa:
 *
 *   1. **ler** primeiro — trazer as horas ocupadas da agenda dela. É o que
 *      impede a fila de oferecer por cima de um compromisso, e é o passo cujo
 *      atraso custa confiança.
 *   2. **escrever** depois — mandar as sessões para lá. Atraso aqui custa
 *      conveniência: o evento aparece cinco minutos mais tarde no celular dela.
 *
 * Se só desse para fazer uma das duas, seria a primeira. Por isso ela vem antes
 * e por isso uma falha de escrita não interrompe a leitura da conta seguinte.
 *
 * Nada aqui usa `Promise.all`: um lote inteiro em paralelo contra a API de um
 * provedor é a receita para tomar limite de taxa — a mesma lição do worker da
 * mensageria.
 */

type LinhaCalendario = {
  id: string;
  calendario_externo: string;
  sync_token: string | null;
  refresh_token: string;
  lido_ate: string | null;
};

type LinhaEspelho = {
  id: string;
  acao: AcaoEspelho;
  calendario_externo: string;
  evento_externo: string | null;
  titulo: string | null;
  inicio: string | null;
  fim: string | null;
};

export type RelatorioCalendario = {
  provedor: string;
  disponivel: boolean;
  calendarios: number;
  ocupacoes: number;
  espelhosTentados: number;
  espelhosFeitos: number;
  espelhosFalhos: number;
};

export async function sincronizarCalendarios(
  adaptador: AdaptadorCalendario = adaptadorDoCalendario(),
  limite = 20,
): Promise<RelatorioCalendario> {
  const supabase = supabaseServico();

  const r: RelatorioCalendario = {
    provedor: adaptador.nome,
    disponivel: adaptador.disponivel,
    calendarios: 0,
    ocupacoes: 0,
    espelhosTentados: 0,
    espelhosFeitos: 0,
    espelhosFalhos: 0,
  };

  // Sem provedor não há o que tentar, e tentar mesmo assim só encheria o log e
  // gastaria uma tentativa de cada linha da fila. A fila fica onde está.
  if (!adaptador.disponivel) {
    console.info("[calendario] sem provedor configurado — a fila espera", {
      adaptador: adaptador.nome,
    });
    return r;
  }

  // ------------------------------------------------------------------ ler
  const calendarios =
    ((await db("calendario.a_ler", supabase.rpc("calendarios_a_ler", { p_limite: limite }))) as
      | LinhaCalendario[]
      | null) ?? [];

  r.calendarios = calendarios.length;

  const hoje = new Date();
  const de = iso(hoje);
  const ate = iso(new Date(hoje.getTime() + DIAS_A_LER * 86_400_000));

  for (const cal of calendarios) {
    try {
      const leitura = await adaptador.ler({
        calendarioExterno: cal.calendario_externo,
        refreshToken: cal.refresh_token,
        syncToken: cal.sync_token,
        de,
        ate,
      });

      if (!leitura.ok) {
        await db(
          "calendario.falhou",
          supabase.rpc("calendario_falhou", {
            p_calendario: cal.id,
            p_erro: leitura.erro,
            p_expirou: leitura.expirou,
          }),
        );
        continue;
      }

      const gravadas = await db<number>(
        "calendario.registrar",
        supabase.rpc("registrar_ocupacoes", {
          p_calendario: cal.id,
          p_de: de,
          p_ate: ate,
          // Só as quatro chaves saem daqui. A função no banco ignora o resto de
          // qualquer jeito — esta é a segunda tranca, e as duas são de propósito:
          // título de compromisso dela não entra neste banco por nenhum caminho.
          p_eventos: leitura.ocupacoes.map((o) => ({
            id: o.id,
            inicio: o.inicio,
            fim: o.fim,
            dia_inteiro: Boolean(o.dia_inteiro),
          })),
          p_sync_token: leitura.syncToken,
        }),
      );

      r.ocupacoes += gravadas ?? 0;
    } catch (e) {
      // Uma conta que falha não pode levar as outras junto: a agenda da vizinha
      // não tem nada a ver com o token vencido desta.
      console.error("[calendario] leitura falhou", { calendario: cal.id, erro: motivo(e) });
    }
  }

  // --------------------------------------------------------------- escrever
  const espelhos =
    ((await db("calendario.a_enviar", supabase.rpc("espelhos_a_enviar", { p_limite: limite }))) as
      | LinhaEspelho[]
      | null) ?? [];

  for (const e of espelhos) {
    r.espelhosTentados += 1;
    try {
      const saida = await adaptador.escrever(
        {
          acao: e.acao,
          calendarioExterno: e.calendario_externo,
          eventoExterno: e.evento_externo,
          titulo: e.titulo,
          inicio: e.inicio,
          fim: e.fim,
        },
        // O refresh token não vem em `espelhos_a_enviar` de propósito: quem tem
        // o segredo é `calendarios_a_ler`, e quem escreve pega o do calendário
        // que acabou de ser lido nesta mesma passada.
        calendarios.find((c) => c.calendario_externo === e.calendario_externo)?.refresh_token ?? "",
      );

      if (saida.ok) {
        await db(
          "calendario.feito",
          supabase.rpc("marcar_espelho_feito", {
            p_espelho: e.id,
            p_evento: saida.eventoExterno,
          }),
        );
        r.espelhosFeitos += 1;
      } else {
        await db(
          "calendario.falhou_espelho",
          supabase.rpc("marcar_espelho_falhou", { p_espelho: e.id, p_erro: saida.erro }),
        );
        r.espelhosFalhos += 1;
      }
    } catch (err) {
      await db(
        "calendario.falhou_espelho",
        supabase.rpc("marcar_espelho_falhou", { p_espelho: e.id, p_erro: motivo(err) }),
      );
      r.espelhosFalhos += 1;
    }
  }

  return r;
}

function iso(d: Date): string {
  return d.toISOString().slice(0, 10);
}

function motivo(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}
