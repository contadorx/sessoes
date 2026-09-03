import "server-only";
import { db } from "@/lib/db";
import { supabaseServico } from "@/lib/supabase/servico";
import { renderizar, type Parametros } from "./templates";
import { adaptadorPara, type Canal } from "./adaptadores";
import { varrerEntrega, type RelatorioDaVarredura } from "./varredura";
import { ordemDeTentativa, NA_MAO, type Classe, type Canal as CanalDeSaida } from "./roteamento";

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

/**
 * O degrau seguinte da cascata — ou a mão dela, que é sempre o último. (B52)
 *
 * A ordem vem de `ordemDeTentativa`, que é pura e testada; aqui é só o
 * caminho: descarta os canais já tentados, pega o primeiro que sobrou e pede ao
 * banco que crie a tentativa. O banco recusa o degrau que repetiria a mesma
 * mensagem no mesmo canal — a chave de entrega é (mensagem, canal), e sem ela a
 * paciente recebe a mesma oferta duas vezes.
 */
/** Há algum canal com provedor? Sem nenhum, não existe cascata a calcular. */
function temAlgumCanal(): boolean {
  return (["whatsapp", "email", "sms"] as const).some((c) => adaptadorPara(c).disponivel);
}

async function paraAMaoDela(
  supabase: ReturnType<typeof supabaseServico>,
  linha: LinhaDeMensagem,
  motivo: string,
): Promise<"na_sua_mao"> {
  await db("mensageria.naSuaMao", supabase.rpc("passar_para_a_sua_mao", {
    p_mensagem: linha.id,
    p_motivo: motivo,
  }));
  return "na_sua_mao";
}

async function descerNaCascata(
  supabase: ReturnType<typeof supabaseServico>,
  linha: LinhaDeMensagem,
  classe: Classe,
  motivo: string,
): Promise<"reencaminhada" | "na_sua_mao"> {
  const disponiveis = (["whatsapp", "email", "sms"] as const).filter(
    (c) => adaptadorPara(c).disponivel,
  );

  // A cascata vem do banco (B57): é decisão de risco contra dinheiro, e muda
  // por edição de tabela, não por commit. Sem linha configurada, a rota é
  // vazia e o único degrau é o canal da paciente — o padrão não inventa degrau
  // caro por conta própria.
  const rota = ((await db(
    "mensageria.rota",
    supabase
      .from("rota_do_canal")
      .select("canal")
      .eq("classe", classe)
      .order("posicao"),
  )) ?? []) as { canal: CanalDeSaida }[];

  const ordem = ordemDeTentativa({
    preferido: linha.canal as CanalDeSaida,
    classe,
    disponiveis,
    rota: rota.map((r) => r.canal),
  });

  for (const degrau of ordem) {
    if (degrau === NA_MAO) break;
    if (degrau === linha.canal) continue;

    try {
      const novo = await db<string | null>(
        "mensageria.reencaminhar",
        supabase.rpc("reencaminhar_mensagem", { p_mensagem: linha.id, p_canal: degrau }),
      );
      if (novo) return "reencaminhada";
    } catch (e) {
      // Um degrau que o banco recusou — documento fora do e-mail, paciente sem
      // aquele contato — não derruba a cascata: tenta o próximo.
      console.error("[mensageria] degrau recusado", { canal: degrau, e });
    }
  }

  await db("mensageria.naSuaMao", supabase.rpc("passar_para_a_sua_mao", {
    p_mensagem: linha.id,
    p_motivo: motivo,
  }));
  return "na_sua_mao";
}

export type Relatorio = {
  expiradas: number;
  expiradasFixas: number;
  destravadas: number;
  reservadas: number;
  enviadas: number;
  falhas: number;
  desistidas: number;
  /**
   * Quantas foram para a caixa "Na sua mão" por não haver provedor. Enquanto
   * o BSP não entra, este número é o lote inteiro — e é assim que se vê, do
   * lado de fora, que o produto **não** está afirmando entrega que ninguém fez.
   */
  naSuaMao: number;
  /** Quantas desceram um degrau da cascata em vez de esperar o dedo dela (B52). */
  reencaminhadas: number;
  /**
   * A varredura da entrega (B55). Nula quando não roda — o empurrão imediato
   * não a chama, porque conferir entrega de vinte minutos atrás não tem nada a
   * ver com fazer uma oferta sair agora.
   */
  entrega?: RelatorioDaVarredura;
};

export async function despacharPendentes(
  limite = 20,
  comVarredura = false,
): Promise<Relatorio> {
  const supabase = supabaseServico();

  // **Primeiro expira, depois envia.** Uma oferta que venceu faz a fila andar e
  // enfileira a próxima — se o envio viesse antes, a nova oferta esperaria o
  // tick seguinte, e cinco minutos numa vaga de amanhã é tempo demais.
  //
  // Isto rodava só quando alguém clicava num botão da tela da fila. A promessa
  // da B7 ("a oferta expira em 40 minutos e a fila anda") dependia de haver
  // alguém olhando — e o motor da fila, que está certo, levaria a culpa.
  const expiradas =
    (await db<number>("mensageria.expirar", supabase.rpc("expirar_ofertas"))) ?? 0;

  // A mesma coisa para a fila de vaga fixa (B22). O prazo lá é de 24 horas, não
  // de 40 minutos, mas a razão é idêntica: uma oferta vencida que ninguém
  // expira é uma fila parada — e a vaga mais valiosa da agenda esperando.
  const expiradasFixas =
    (await db<number>("mensageria.expirarFixas", supabase.rpc("expirar_ofertas_fixas"))) ?? 0;

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
    expiradas,
    expiradasFixas,
    destravadas,
    reservadas: lote.length,
    enviadas: 0,
    falhas: 0,
    desistidas: 0,
    naSuaMao: 0,
    reencaminhadas: 0,
  };

  /*
    A classe de cada template decide a cascata — e a consulta é **preguiçosa**,
    de propósito: enquanto não há provedor nenhum configurado, não existe
    cascata para calcular, e o caminho que leva tudo para a mão dela não deve
    pagar uma consulta que não vai usar. `lib/mensageria/worker.test.ts` prova
    justamente esse caminho, e ele continua sem tocar em `templates`.
  */
  let classes: Map<string, Classe> | null = null;
  const classeDe = async (template: string): Promise<Classe> => {
    if (!classes) {
      const linhas = ((await db(
        "mensageria.classes",
        supabase.from("templates").select("codigo, classe"),
      )) ?? []) as { codigo: string; classe: Classe }[];
      classes = new Map(linhas.map((t) => [t.codigo, t.classe]));
    }
    // Sem classe declarada, `rotina` — o padrão seguro: rotina não desce para
    // SMS e não fura a janela de silêncio.
    return classes.get(template) ?? "rotina";
  };

  for (const linha of lote) {
    try {
      const adaptador = adaptadorPara(linha.canal);

      /*
        A pergunta vem **antes** de renderizar e antes de tentar, e é a
        correção do pior defeito que este produto teve no ar: o adaptador sem
        provedor respondia `ok: true` com um id inventado, e a linha abaixo
        carimbava `marcar_enviada`. A tela dizia à psicóloga que a paciente
        tinha sido avisada; a paciente não tinha recebido nada.

        Sem provedor, a mensagem não falha nem é enviada — ela vai para a mão
        dela, com o motivo escrito. `expirar_ofertas` (0061) já segura o
        relógio da oferta enquanto ela estiver lá, então a vaga não queima
        esperando o dedo dela.
      */
      if (!adaptador.disponivel) {
        /*
          A cascata (B52) entra **aqui**, antes da mão dela: sem provedor para o
          canal da paciente, ainda pode haver outro caminho. A mão dela continua
          sendo o último degrau, e nunca o segundo — ela depende de humano
          acordado, e trocar uma entrega que ainda tinha caminho por uma tarefa
          que ela pode não ver hoje é perder a mensagem por comodidade nossa.
        */
        const desfecho = temAlgumCanal()
          ? await descerNaCascata(
              supabase,
              linha,
              await classeDe(linha.template),
              adaptador.motivo ?? "sem provedor configurado",
            )
          : await paraAMaoDela(supabase, linha, adaptador.motivo ?? "sem provedor configurado");

        if (desfecho === "reencaminhada") relatorio.reencaminhadas += 1;
        else relatorio.naSuaMao += 1;
        continue;
      }

      const conteudo = renderizar(linha.template, linha.params ?? {});

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

  /*
    A varredura da entrega vem **depois** do envio, e é de propósito: o que
    acabou de sair ainda está dentro da janela de confirmação, então varrer
    antes mediria a foto de antes deste lote. E ela não derruba o despacho —
    conferir entrega é diagnóstico, mandar mensagem é o trabalho.
  */
  if (comVarredura) {
    try {
      relatorio.entrega = await varrerEntrega("email");
    } catch (e) {
      console.error("[entrega] a varredura falhou; o despacho não depende dela", e);
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
