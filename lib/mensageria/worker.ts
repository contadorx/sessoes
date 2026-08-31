import "server-only";
import { db } from "@/lib/db";
import { supabaseServico } from "@/lib/supabase/servico";
import { renderizar, type Parametros } from "./templates";
import { adaptadorPara, type Canal } from "./adaptadores";

/**
 * O despachante.
 *
 * A ordem importa e é sempre esta:
 *
 *   1. **destravar** o que ficou preso em `enviando` (processo morto no meio);
 *   2. **reservar** um lote — a reserva é atômica no banco, então dois workers
 *      rodando ao mesmo tempo nunca pegam a mesma mensagem;
 *   3. falar com o provedor **uma mensagem por vez**, e registrar o desfecho de
 *      cada uma antes de passar para a próxima.
 *
 * O passo 3 não usa `Promise.all` de propósito. Um lote inteiro em paralelo
 * contra a API do provedor é a receita para tomar limite de taxa e transformar
 * uma fila saudável em cinco tentativas queimadas. Devagar é mais rápido aqui.
 *
 * O que este código nunca faz: decidir sozinho que uma mensagem não vale a pena.
 * Quem desiste é o banco, depois de cinco tentativas, e a linha fica lá contando
 * o que aconteceu.
 */

type LinhaDeMensagem = {
  id: string;
  canal: Canal;
  template: string;
  params: Parametros | null;
  destino: string;
  tentativas: number;
};

export type Relatorio = {
  destravadas: number;
  reservadas: number;
  enviadas: number;
  falhas: number;
  desistidas: number;
};

export async function despacharPendentes(limite = 20): Promise<Relatorio> {
  const supabase = supabaseServico();

  const destravadas =
    (await db<number>("mensageria.destravar", supabase.rpc("destravar_mensagens", {
      p_minutos: 10,
    }))) ?? 0;

  const lote =
    (await db<LinhaDeMensagem[]>(
      "mensageria.reservar",
      supabase.rpc("reservar_mensagens", { p_limite: limite }),
    )) ?? [];

  const relatorio: Relatorio = {
    destravadas,
    reservadas: lote.length,
    enviadas: 0,
    falhas: 0,
    desistidas: 0,
  };

  for (const linha of lote) {
    try {
      const conteudo = renderizar(linha.template, linha.params ?? {});
      const adaptador = adaptadorPara(linha.canal);

      const r = await adaptador.enviar({
        canal: linha.canal,
        destino: linha.destino,
        conteudo,
      });

      if (r.ok) {
        await db("mensageria.enviada", supabase.rpc("marcar_enviada", {
          p_mensagem: linha.id,
          p_provedor: r.provedor,
          p_provedor_msg_id: r.idExterno ?? null,
        }));
        relatorio.enviadas += 1;
        continue;
      }

      // Erro definitivo (número que não existe, e-mail malformado): insistir não
      // muda o desfecho. Encerra de uma vez, com o motivo escrito na trilha.
      if (r.definitivo) {
        await db("mensageria.desistir", supabase.rpc("desistir_mensagem", {
          p_mensagem: linha.id,
          p_erro: r.erro,
        }));
        relatorio.desistidas += 1;
        continue;
      }

      const desfecho = await db<string>("mensageria.falha", supabase.rpc("marcar_falha", {
        p_mensagem: linha.id,
        p_erro: r.erro,
      }));

      if (desfecho === "falhou") relatorio.desistidas += 1;
      else relatorio.falhas += 1;
    } catch (e) {
      // Erro nosso, não do provedor: template desconhecido, params corrompidos.
      // A mensagem volta para a fila com o motivo escrito — silêncio aqui seria
      // uma mensagem sumindo sem rastro.
      const motivo = e instanceof Error ? e.message : String(e);
      console.error("[mensageria] falhou ao despachar", { id: linha.id, motivo });

      const desfecho = await db<string>("mensageria.falha", supabase.rpc("marcar_falha", {
        p_mensagem: linha.id,
        p_erro: motivo,
      }));

      if (desfecho === "falhou") relatorio.desistidas += 1;
      else relatorio.falhas += 1;
    }
  }

  return relatorio;
}

/**
 * O empurrão imediato.
 *
 * O cron varre de cinco em cinco minutos, e uma oferta que expira em quarenta
 * não pode esperar cinco para sair. Então quem enfileira também cutuca: abriu a
 * vaga, a mensagem tenta sair na mesma requisição.
 *
 * Duas decisões deliberadas:
 *
 *  - **Nunca lança.** A cascata já aconteceu no banco quando isto roda. Se o
 *    envio falhar, a fila não pode desandar por causa disso — a mensagem fica
 *    pendente e o cron pega no próximo minuto.
 *  - **Some quando não há chave de serviço.** Antes do BSP e da variável de
 *    ambiente, o sistema inteiro funciona sem envio real; a alternativa seria a
 *    tela de vagas quebrar por falta de uma configuração que ainda nem é usada.
 */
export async function cutucarDespacho(limite = 5): Promise<void> {
  if (!process.env.SUPABASE_SERVICE_ROLE_KEY) return;

  try {
    await despacharPendentes(limite);
  } catch (e) {
    console.error("[mensageria] o empurrão imediato falhou; o cron pega depois", {
      motivo: e instanceof Error ? e.message : String(e),
    });
  }
}
