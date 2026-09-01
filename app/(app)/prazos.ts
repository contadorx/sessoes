import "server-only";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { hoje } from "@/lib/tempo-servidor";
import { prazoDoAno, diasEntre, faseDoPrazo, diaBr } from "@/lib/receitasaude";
import { mesAFechar } from "@/lib/contador";
import type { PrazosDoMes } from "@/lib/navegacao";

/**
 * O que vence, para a faixa no topo da Agenda.
 *
 * Antes disto, Receita Saúde e Contador eram dois itens de menu permanentes —
 * e era assim que os prazos ficavam invisíveis: um item que fica lá o ano
 * inteiro não avisa nada. A auditoria escreveu a versão curta: *"a usuária
 * trabalha normalmente e só descobre a obrigação quando decide abrir Receita
 * ou Contador"*.
 *
 * A troca é essa: os dois saem do menu e viram uma faixa que **só existe
 * quando existe prazo correndo**, na tela que ela abre todo dia.
 *
 * Falhar aqui não derruba nada. Sem os prazos, a agenda aparece sem a faixa —
 * o alarme importa, o acesso à agenda importa mais. É a mesma regra que o
 * `alarmeFiscal` já seguia.
 */
export async function prazosDoMes(): Promise<PrazosDoMes> {
  const vazio: PrazosDoMes = {
    recibosPendentes: 0,
    recibosAte: null,
    recibosUrgente: false,
    contadorAberto: false,
    contadorAte: null,
    contadorUrgente: false,
  };

  try {
    const dia = hoje();
    const supabase = await supabaseSessao();

    // ---------------------------------------------------------- Receita Saúde
    //
    // O que está prestes a vencer é sempre o retroativo do **ano anterior** —
    // entre janeiro e o último dia de fevereiro esse número é o que separa
    // "resolvo depois" de R$ 100 por recibo.
    const ano = Number(dia.slice(0, 4)) - 1;
    let recibosPendentes = 0;
    let recibosAte: string | null = null;
    let recibosUrgente = false;

    const rfb = (await db("prazos.rfb", supabase.rpc("receita_saude_do_ano", { p_ano: ano }))) as unknown as {
      ligado: boolean;
      pendentes: { n: number };
    } | null;

    if (rfb?.ligado && rfb.pendentes.n > 0) {
      const prazo = prazoDoAno(ano);
      recibosPendentes = rfb.pendentes.n;
      recibosAte = diaBr(prazo);
      recibosUrgente = faseDoPrazo(diasEntre(dia, prazo), recibosPendentes) !== "tranquilo";
    }

    // -------------------------------------------------------------- o contador
    //
    // A pasta é do mês passado, e vence no dia que ela combinou com ele
    // (`pasta_dia`, padrão 5). Se a pasta daquele mês já foi gerada, não há
    // pendência — mesmo que ele ainda não tenha respondido, porque a partir
    // daí a bola é dele.
    let contadorAberto = false;
    let contadorAte: string | null = null;
    let contadorUrgente = false;

    const contas = (await db(
      "prazos.conta",
      supabase.from("contas").select("pasta_dia, pasta_ativa").limit(1),
    )) as unknown as { pasta_dia: number; pasta_ativa: boolean }[] | null;

    const conta = contas?.[0];
    if (conta?.pasta_ativa) {
      const competencia = mesAFechar(dia);

      const pastas = (await db(
        "prazos.pasta",
        supabase.from("pastas_contador").select("id").eq("competencia", `${competencia}-01`).limit(1),
      )) as unknown as { id: string }[] | null;

      if (!pastas || pastas.length === 0) {
        const diaDoPrazo = String(conta.pasta_dia).padStart(2, "0");
        // O prazo é no mês corrente: a pasta de agosto vence no dia 5 de
        // setembro. `mesAFechar` já garantiu que a competência é a anterior.
        const prazo = `${dia.slice(0, 7)}-${diaDoPrazo}`;
        contadorAberto = true;
        contadorAte = diaBr(prazo);
        contadorUrgente = diasEntre(dia, prazo) <= 3;
      }
    }

    return { recibosPendentes, recibosAte, recibosUrgente, contadorAberto, contadorAte, contadorUrgente };
  } catch (e) {
    console.error("[prazos] não consegui ler os prazos do mês", e);
    return vazio;
  }
}
