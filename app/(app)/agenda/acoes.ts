"use server";

import { revalidatePath } from "next/cache";
import { db, ErroDeBanco } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { sessaoAtual } from "@/lib/conta";
import { inicioDoDiaSP } from "@/lib/tempo";
import { deCentavos, paraCentavos } from "@/lib/dinheiro";
import { lerCentavos } from "@/lib/formato";
import { adaptadorPara } from "@/lib/pagamentos/adaptadores";
import { problemaNoAjuste, fraseDoAviso, type DestinoDoAviso } from "@/lib/politica";

/** O instante exato de um "dia + hora" no fuso de São Paulo. */
function inicioDaSessao(dia: string, hora: string): Date {
  const [h, m] = hora.split(":").map(Number);
  return new Date(inicioDoDiaSP(dia).getTime() + (h * 60 + m) * 60_000);
}

export type Resultado =
  | { estado: "inicial" }
  | { estado: "ok"; mensagem: string }
  | { estado: "erro"; erros: string[] };

const TIPOS = ["ferias", "feriado", "bloqueio"] as const;

/**
 * Criar uma ausência **não mexe no enquadre** — o gatilho no banco apaga só as
 * previsões daquele período. Remover devolve a recorrência, porque a
 * materialização é idempotente e roda de novo.
 */
export async function criarAusencia(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const sessao = await sessaoAtual();
  if (!sessao.profissionalId) {
    return { estado: "erro", erros: ["Sua conta está sem profissional cadastrado."] };
  }

  const tipo = String(form.get("tipo") ?? "ferias");
  const inicio = String(form.get("inicio") ?? "");
  const fim = String(form.get("fim") ?? "") || inicio;
  const motivo = String(form.get("motivo") ?? "").trim() || null;

  const erros: string[] = [];
  if (!(TIPOS as readonly string[]).includes(tipo)) erros.push("Tipo desconhecido.");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(inicio)) erros.push("Informe a data inicial.");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(fim)) erros.push("Data final inválida.");
  if (inicio && fim && fim < inicio) erros.push("A data final é anterior à inicial.");
  if (erros.length > 0) return { estado: "erro", erros };

  const supabase = await supabaseSessao();

  try {
    await db(
      "excecoes.criar",
      supabase.from("excecoes_agenda").insert({
        profissional_id: sessao.profissionalId,
        tipo,
        inicio,
        fim,
        motivo,
      }),
    );
  } catch (e) {
    console.error("[ausencias] falhou", e);
    return {
      estado: "erro",
      erros: [e instanceof ErroDeBanco ? "Não consegui registrar." : "Erro inesperado."],
    };
  }

  revalidatePath("/agenda");
  return { estado: "ok", mensagem: "Registrado. As sessões do período saíram da agenda." };
}

/**
 * Põe uma mensalidade aberta no valor que a conta do mês dá hoje.
 *
 * Uma por vez, e sempre pedida. A alternativa — o gatilho da exceção sair
 * corrigindo cobrança sozinho — é o antipadrão "o default que decide por ela",
 * e sobre dinheiro ele é pior: ela descobriria pela diferença no extrato.
 */
export async function reverMensalidade(
  _anterior: Resultado,
  form: FormData,
): Promise<Resultado> {
  const id = String(form.get("cobranca") ?? "");
  if (!id) return { estado: "erro", erros: ["Cobrança não identificada."] };

  const supabase = await supabaseSessao();

  try {
    await db("mensalidades.rever", supabase.rpc("rever_mensalidade", { p_cobranca: id }));
  } catch (e) {
    console.error("[mensalidades] falhou rever", e);
    return { estado: "erro", erros: ["Não consegui atualizar esta cobrança agora."] };
  }

  revalidatePath("/agenda");
  revalidatePath("/recebimentos");
  return { estado: "ok", mensagem: "Atualizada." };
}

export async function removerAusencia(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const id = String(form.get("id") ?? "");
  if (!id) return { estado: "erro", erros: ["Não identifiquei o registro."] };

  const supabase = await supabaseSessao();

  try {
    await db("excecoes.remover", supabase.from("excecoes_agenda").delete().eq("id", id));
  } catch (e) {
    console.error("[ausencias] falhou remover", e);
    return { estado: "erro", erros: ["Não consegui remover."] };
  }

  revalidatePath("/agenda");
  return { estado: "ok", mensagem: "Removido. A recorrência voltou." };
}

/**
 * Cancela — e **não diz se foi cedo ou tarde**. Quem classifica é o banco,
 * comparando o relógio do servidor com a política gravada na própria sessão.
 * Se a classificação viesse daqui, a multa de falta seria negociável por quem
 * soubesse abrir o inspetor do navegador.
 */
export async function cancelarSessao(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const id = String(form.get("id") ?? "");
  const por = String(form.get("por") ?? "paciente");
  if (!id) return { estado: "erro", erros: ["Sessão não identificada."] };

  const supabase = await supabaseSessao();

  try {
    const resultado = await db(
      "sessoes.cancelar",
      supabase.rpc("cancelar_sessao", { p_sessao: id, p_por: por }),
    );

    revalidatePath("/agenda");

    return {
      estado: "ok",
      mensagem:
        resultado === "cancelada_tarde"
          // **P4 (0058):** a política não se aplica mais sozinha. Ela chega
          // como pergunta, e a frase tem de dizer isso — senão a tela promete
          // uma cobrança que ninguém vai encontrar.
          ? "Cancelamento tardio. A cobrança está esperando sua decisão, em \u201cA decidir\u201d."
          : "Cancelado dentro do prazo, sem cobrança.",
    };
  } catch (e) {
    console.error("[sessoes] falhou cancelar", e);
    return { estado: "erro", erros: [traduzir(e)] };
  }
}

const MARCAVEIS = ["prevista", "confirmada", "realizada", "falta"] as const;

/** Confirmar, marcar realizada, marcar falta — e desfazer, voltando a prevista. */
export async function marcarSessao(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const id = String(form.get("id") ?? "");
  const estado = String(form.get("estado") ?? "");

  if (!id) return { estado: "erro", erros: ["Sessão não identificada."] };
  if (!(MARCAVEIS as readonly string[]).includes(estado)) {
    return { estado: "erro", erros: ["Estado desconhecido."] };
  }

  const supabase = await supabaseSessao();

  try {
    await db("sessoes.marcar", supabase.from("sessoes").update({ estado }).eq("id", id));
  } catch (e) {
    console.error("[sessoes] falhou marcar", e);
    return { estado: "erro", erros: [traduzir(e)] };
  }

  revalidatePath("/agenda");
  return { estado: "ok", mensagem: "Pronto." };
}

/** Encaixe manual num horário livre. A fila (B7) vai fazer isso sozinha. */
/**
 * Marcar uma sessão que não vem da recorrência — e a origem dela.
 *
 * **`origem` aqui é `avulsa`, e não `encaixe`.** Isto era um defeito de número,
 * não de nome. A `financeiro_do_mes` (0037:465-472) soma "o que voltou" por
 * `origem = 'encaixe'` **sem casar com vaga nenhuma**, e `fraseDoRecuperado`
 * escreve na tela dela *"N horas que a fila preencheu"*. Como esta função
 * cravava `'encaixe'` em toda sessão marcada à mão — e a lista de quem aparece
 * no formulário é `pacientesParaEncaixe()`, que é todo paciente ativo, sem vaga
 * envolvida —, cada sessão marcada de propósito num horário livre virava
 * dinheiro recuperado de um buraco que nunca existiu, com a fila levando o
 * crédito.
 *
 * Quem preenche vaga é a fila, e é o banco que registra isso: `responder_oferta`
 * insere a sessão com `'encaixe'` quando alguém aceita a oferta (lido do
 * `pg_get_functiondef`, não da migração). Marcar à mão é `'avulsa'` — a RLS da
 * 0035:640 aceita as duas, e é a única escrita de origem que a tela faz.
 */
export async function criarSessao(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const sessao = await sessaoAtual();
  if (!sessao.profissionalId) {
    return { estado: "erro", erros: ["Sua conta está sem profissional cadastrado."] };
  }

  const pacienteId = String(form.get("paciente_id") ?? "");
  const dia = String(form.get("dia") ?? "");
  const hora = String(form.get("hora") ?? "");
  const duracao = Number(form.get("duracao_min") ?? 50);
  const valorBruto = String(form.get("valor") ?? "").trim();

  const erros: string[] = [];
  if (!pacienteId) erros.push("Escolha o paciente.");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dia)) erros.push("Informe o dia.");
  if (!/^\d{2}:\d{2}$/.test(hora)) erros.push("Informe o horário.");
  if (!Number.isInteger(duracao) || duracao < 15 || duracao > 240) erros.push("Duração inválida.");

  const valorCentavos = lerCentavos(valorBruto);
  if (valorCentavos === null) erros.push("Informe o valor.");
  if (erros.length > 0) return { estado: "erro", erros };

  const inicio = inicioDaSessao(dia, hora);
  const fim = new Date(inicio.getTime() + duracao * 60_000);

  const supabase = await supabaseSessao();

  try {
    await db(
      "sessoes.marcar",
      supabase.from("sessoes").insert({
        conta_id: sessao.contaId,
        profissional_id: sessao.profissionalId,
        paciente_id: pacienteId,
        inicio: inicio.toISOString(),
        fim: fim.toISOString(),
        origem: "avulsa",
        estado: "prevista",
        valor: deCentavos(valorCentavos ?? 0),
      }),
    );
  } catch (e) {
    console.error("[sessoes] falhou marcar sessão", e);
    return { estado: "erro", erros: [traduzir(e)] };
  }

  revalidatePath("/agenda");
  return { estado: "ok", mensagem: "Sessão marcada." };
}

function traduzir(e: unknown): string {
  if (e instanceof ErroDeBanco) {
    const m = e.message;
    if (/sobreposicao|exclusion/i.test(m) || e.codigo === "23P01") {
      return "Já existe sessão nesse horário.";
    }
    if (/ainda n[aã]o come/i.test(m)) return "A sessão ainda não começou.";
    if (/j[aá] aconteceu/i.test(m)) return "Esta sessão já aconteceu.";
    if (/n[aã]o vira presen/i.test(m)) return "Cancelamento não vira presença — reabra como prevista.";
  }
  return "Não consegui completar agora. Tente de novo em instantes.";
}


/**
 * Perdoar.
 *
 * O freio da régua automática, e ele tem de ser mais fácil de puxar do que o
 * acelerador. Quem decide se cobra é ela — a política só faz a parte que ela
 * não conseguiria fazer sozinha, que é levantar o assunto.
 *
 * Cancelar o aviso que ainda não saiu é do banco (0022 + 0023). Aqui é só o
 * caminho da tela.
 */
export async function perdoarCobranca(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const id = String(form.get("cobranca_id") ?? "");
  if (!id) return { estado: "erro", erros: ["Cobrança não identificada."] };

  const supabase = await supabaseSessao();

  try {
    await db("cobranca.perdoar", supabase.rpc("perdoar_cobranca", { p_cobranca: id }));
  } catch (e) {
    console.error("[cobranca] falhou perdoar", e);
    return { estado: "erro", erros: [traduzirCobranca(e)] };
  }

  revalidatePath("/agenda");
  return { estado: "ok", mensagem: "Perdoada. O aviso não vai sair." };
}

/** Recebeu. O meio de pagamento é da fase 2; isto é o registro dela. */
export async function marcarCobrancaPaga(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const id = String(form.get("cobranca_id") ?? "");
  if (!id) return { estado: "erro", erros: ["Cobrança não identificada."] };

  const supabase = await supabaseSessao();

  try {
    await db("cobranca.pagar", supabase.rpc("marcar_cobranca_paga", { p_cobranca: id }));
  } catch (e) {
    console.error("[cobranca] falhou marcar paga", e);
    return { estado: "erro", erros: [traduzirCobranca(e)] };
  }

  revalidatePath("/agenda");
  return { estado: "ok", mensagem: "Registrado como recebido." };
}

function traduzirCobranca(e: unknown): string {
  if (e instanceof ErroDeBanco) {
    if (/n[aã]o encontrada/i.test(e.message)) return "Esta cobrança não existe mais.";
    if (/aberta/i.test(e.message)) return "Esta cobrança já foi resolvida.";
  }
  return "Não consegui completar agora. Tente de novo em instantes.";
}

/**
 * Gera o PIX da cobrança.
 *
 * O código sai da chave **dela** e é guardado na cobrança — não regerado a cada
 * abertura de tela. O motivo é o mesmo do retrato da sessão: o que foi mandado
 * para o paciente tem de continuar existindo igual, mesmo que ela troque a chave
 * PIX amanhã. Um copia-e-cola que muda debaixo de quem já recebeu é uma
 * cobrança que não pode ser paga.
 */
export async function gerarPix(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const id = String(form.get("cobranca_id") ?? "");
  if (!id) return { estado: "erro", erros: ["Cobrança não identificada."] };

  const supabase = await supabaseSessao();
  const sessao = await sessaoAtual();

  try {
    const contas = (await db(
      "cobranca.pix.conta",
      supabase
        .from("contas")
        .select("pix_chave, pix_nome, pix_cidade, provedor_pagamento, provedor_estado")
        .eq("id", sessao.contaId)
        .limit(1),
    )) as unknown as {
      pix_chave: string | null;
      pix_nome: string | null;
      pix_cidade: string | null;
      provedor_pagamento: string | null;
      provedor_estado: string | null;
    }[];

    const conta = contas[0];

    const cobrancas = (await db(
      "cobranca.pix.ler",
      supabase.from("cobrancas").select("id, valor, estado").eq("id", id).limit(1),
    )) as unknown as { id: string; valor: string; estado: string }[];

    const cobranca = cobrancas[0];
    if (!cobranca) return { estado: "erro", erros: ["Esta cobrança não existe mais."] };
    if (cobranca.estado !== "aberta") {
      return { estado: "erro", erros: ["Esta cobrança já foi resolvida."] };
    }

    const txid = await db<string>(
      "cobranca.txid",
      supabase.rpc("txid_da_cobranca", { p_cobranca: id }),
    );

    const adaptador = adaptadorPara(conta?.provedor_pagamento ?? null, conta?.provedor_estado ?? null);

    const criada = await adaptador.criar(
      { cobrancaId: id, valorCentavos: paraCentavos(cobranca.valor), txid },
      {
        pixChave: conta?.pix_chave ?? null,
        pixNome: conta?.pix_nome ?? null,
        pixCidade: conta?.pix_cidade ?? null,
      },
    );

    await db(
      "cobranca.pix.salvar",
      supabase
        .from("cobrancas")
        .update({
          txid,
          provedor: criada.provedor,
          pix_copia_cola: criada.pixCopiaCola,
          link_pagamento: criada.link,
          provedor_cobranca_id: criada.provedorCobrancaId,
        })
        .eq("id", id)
        .select("id"),
    );
  } catch (e) {
    console.error("[cobranca] falhou gerar pix", e);
    return {
      estado: "erro",
      erros: [e instanceof Error ? e.message : "Não consegui gerar o PIX agora."],
    };
  }

  revalidatePath("/agenda");
  return { estado: "ok", mensagem: "PIX gerado." };
}

/**
 * A decisão sobre a multa (P4).
 *
 * **É a única porta pela qual uma cobrança de falta nasce.** O gatilho parou de
 * criar cobrança na 0058; ele cria a pergunta, e esta ação é a resposta.
 *
 * Três coisas de desenho, e as três são sobre postura:
 *
 *  · **"Não cobrar" tem o mesmo peso visual que "Cobrar"** na tela que chama
 *    esta ação. Quem construiu a régua tem a obrigação de deixar o desvio tão
 *    fácil quanto o caminho — e agora o desvio é o padrão, porque sem decisão
 *    nada acontece;
 *  · **o valor ajustado é validado aqui e no banco**, com o mesmo teto. O banco
 *    é quem garante; isto é para a mensagem de erro ser em português;
 *  · **a resposta diz o que vai acontecer com o aviso**, inclusive quando ele
 *    não vai sair. Descobrir depois que o paciente nunca soube da cobrança é o
 *    pior lugar para descobrir.
 */
export async function decidirCobranca(_anterior: Resultado, form: FormData): Promise<Resultado> {
  const id = String(form.get("proposta_id") ?? "");
  const decisao = String(form.get("decisao") ?? "");
  const motivo = String(form.get("motivo") ?? "").trim() || null;
  const bruto = String(form.get("valor") ?? "").trim();
  const teto = String(form.get("valor_da_sessao") ?? "").trim();

  if (!id) return { estado: "erro", erros: ["Decisão não identificada."] };
  if (decisao !== "cobrar" && decisao !== "perdoar") {
    return { estado: "erro", erros: ["Escolha cobrar ou não cobrar."] };
  }

  let valor: string | null = null;
  if (decisao === "cobrar" && bruto) {
    // Os dois passam pelo parser de entrada: `bruto` porque ela digita, e
    // `teto` porque, mesmo vindo do banco por campo escondido, ele chega por
    // formulário — e `paraCentavos` **lança**, o que ali dentro seria um 500
    // em vez de uma recusa.
    const centavos = lerCentavos(bruto);
    if (centavos === null) return { estado: "erro", erros: ["O valor não parece um número."] };
    const problema = problemaNoAjuste(centavos, teto ? lerCentavos(teto) : null);
    if (problema) return { estado: "erro", erros: [problema] };
    valor = deCentavos(centavos);
  }

  const supabase = await supabaseSessao();

  let resposta: { decisao: string; valor: string; aviso: DestinoDoAviso; aviso_em: string | null };
  try {
    resposta = (await db(
      "cobranca.decidir",
      supabase.rpc("decidir_cobranca", {
        p_proposta: id,
        p_decisao: decisao,
        p_valor: valor,
        p_motivo: motivo,
      }),
    )) as unknown as typeof resposta;
  } catch (e) {
    console.error("[cobranca] falhou decidir", e);
    return { estado: "erro", erros: [traduzirDecisao(e)] };
  }

  revalidatePath("/agenda");

  if (decisao === "perdoar") {
    return {
      estado: "ok",
      mensagem: "Registrado que você não vai cobrar. Ninguém recebe mensagem nenhuma.",
    };
  }

  return {
    estado: "ok",
    mensagem: `Cobrança criada. ${fraseDoAviso(resposta?.aviso ?? null, resposta?.aviso_em ?? null)}`.trim(),
  };
}

function traduzirDecisao(e: unknown): string {
  if (e instanceof ErroDeBanco) {
    if (/j[aá] foi decidida/i.test(e.message)) return "Esta decisão já foi tomada.";
    if (/n[aã]o encontrada/i.test(e.message)) return "Esta pergunta não existe mais — a falta pode ter sido desfeita.";
    if (/n[aã]o passa do valor/i.test(e.message)) return "O ajuste não pode passar do valor da sessão.";
    if (/perd[aã]o n[aã]o tem valor/i.test(e.message)) {
      return "Para cobrar menos, escolha cobrar e ajuste o valor.";
    }
    if (/zero/i.test(e.message)) return "Cobrança de zero não é cobrança — escolha não cobrar.";
  }
  return "Não consegui completar agora. Tente de novo em instantes.";
}

/**
 * Registra que a ação de uma causa foi usada (P5).
 *
 * **Ela não faz nada com a navegação** — o link leva para onde tem de levar de
 * qualquer jeito, e esta ação só conta. Se falhar, falha em silêncio: uma
 * medição de produto nunca pode impedir a pessoa de chegar onde ia.
 *
 * O que se mede é o **alerta**, não a pessoa: uma linha por conta e por causa,
 * sem paciente, sem sessão e sem rastro de navegação. É o instrumento do
 * critério de pronto do P5 — alerta que ninguém usa por três meses é candidato
 * a sumir da tela.
 */
export async function usarAlerta(causa: string): Promise<void> {
  const supabase = await supabaseSessao();
  try {
    await db("risco.usar_alerta", supabase.rpc("registrar_uso_do_alerta", { p_causa: causa }));
  } catch (e) {
    console.error("[risco] falhou registrar uso do alerta", e);
  }
}

/**
 * Ela mandou pelo WhatsApp dela (OP9).
 *
 * O clique no link e o registro são dois atos separados, e é de propósito: o
 * `wa.me` abre o aplicativo dela, e daquele ponto em diante o produto **não tem
 * como saber** se a mensagem saiu. Só ela sabe, e por isso é ela quem diz.
 *
 * Um botão que registrasse o envio no próprio clique do link afirmaria uma
 * entrega que ninguém observou — a mesma classe de mentira que a policy do
 * banco recusa ao não deixar escrever `entregue`.
 */
export async function mandeiPeloWhatsapp(id: string): Promise<Resultado> {
  try {
    const supabase = await supabaseSessao();
    const registrou = await db<boolean>(
      "canal.mandei",
      supabase.rpc("marcar_enviada_a_mao", { p_mensagem: id }),
    );

    // O RPC devolve `false` quando a mensagem já saiu daquele estado — dois
    // toques seguidos, ou outra aba. Dizer "Anotado" aí seria a mesma classe de
    // mentira que esta build existe para consertar.
    if (registrou === false) {
      return { estado: "erro", erros: ["Esta já tinha saído da lista. Recarregue para ver como está."] };
    }

    // Só `/agenda`: é a única tela que mostra a caixa. Revalidar `/encaixes`
    // junto refazia as consultas de uma página que nem estava aberta, e cada
    // toque aqui custava duas recargas — oito envios num dia, dezesseis.
    revalidatePath("/agenda");
    return { estado: "ok", mensagem: "Anotado. O prazo da resposta começa agora." };
  } catch (e) {
    console.error("[canal] falhou registrar o envio a mão", e);
    return {
      estado: "erro",
      erros: ["Não consegui anotar que você mandou. A vaga continua esperando — tente de novo."],
    };
  }
}

/**
 * Ela decidiu não mandar.
 *
 * Existe porque a alternativa é pior: a expiração da oferta passou a esperar
 * pela mensagem que está na mão dela, então uma que ficasse parada para sempre
 * seguraria a fila junto. Desistir devolve a vaga ao relógio.
 */
export async function naoVouMandar(id: string): Promise<Resultado> {
  try {
    const supabase = await supabaseSessao();
    const tirou = await db<boolean>(
      "canal.nao_vou",
      supabase.rpc("nao_vou_mandar", { p_mensagem: id }),
    );

    if (tirou === false) {
      return { estado: "erro", erros: ["Esta já tinha saído da lista. Recarregue para ver como está."] };
    }

    revalidatePath("/agenda");
    return { estado: "ok", mensagem: "Tirado da lista. A vaga volta a andar sozinha." };
  } catch (e) {
    console.error("[canal] falhou tirar da lista", e);
    return {
      estado: "erro",
      erros: ["Não consegui tirar da lista. Ela continua aqui — tente de novo."],
    };
  }
}
