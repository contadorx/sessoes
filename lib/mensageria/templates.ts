/**
 * As oito famílias de mensagem, e o modo discreto (D3).
 *
 * **⚠️ A oitava entrou em 02/09 consertando um defeito vivo, e ele vale ser
 * lido antes do resto.** O P3 criou `confirmacao_de_sessao` na tabela
 * `templates` do banco — com `check` fechado, `essencial = true` e motivo
 * escrito — e `pedir_confirmacoes()` passou a enfileirar mensagens dessa
 * família. **Este arquivo não sabia dela.** `renderizar()` lança
 * `Template desconhecido` para o que não está em `FAMILIAS`, então **toda
 * confirmação enfileirada estouraria no worker**, e a feature inteira — vinte
 * verificações, uma migração, duas telas — não conseguiria mandar uma
 * mensagem.
 *
 * Ninguém viu porque o defeito é **dormente**: `confirmacao_horas_antes` nasce
 * `null` em todo enquadre (é opção, não comportamento), então `pedir_confirmacoes`
 * nunca teve o que enfileirar. Ele acordaria na primeira psicóloga que ligasse
 * a confirmação.
 *
 * A causa é a de sempre neste projeto: **a mesma lista em dois lugares.** O
 * banco tem a sua, fechada por `check`, justamente para que template novo seja
 * migração e não string solta; e nada conferia a direção contrária — que todo
 * template do banco tem renderizador aqui. É a família do `exportar_conta` sem
 * dezessete tabelas e da lista de rotas públicas do proxy.
 *
 * **O espelho agora é teste dos dois lados**, com a mesma lista escrita duas
 * vezes de propósito: a verificação 2 da suíte 0066 confere `templates` contra
 * a lista canônica, e `templates.test.ts` confere `FAMILIAS` contra a mesma.
 * Uma metade que mude sozinha reprova.
 *
 * Quatro coisas que precisam ficar claras antes de ler o código:
 *
 * **1. Discrição é template diferente, não texto trocado em tempo de execução.**
 * A Meta aprova o corpo do template, não o valor das variáveis. Então "discreto"
 * e "completo" são dois templates aprovados separadamente lá — o que muda entre
 * eles é a frase, e a frase é fixa. Trocar palavra na hora do envio faria o
 * WhatsApp recusar a mensagem.
 *
 * **2. O modo é do paciente, não da conta.** Ele viaja gravado na própria
 * mensagem (`params.modo`, congelado pelo gatilho da 0017). Quem editar o
 * cadastro depois não muda o que já foi enfileirado.
 *
 * **3. Nenhum corpo começa ou termina em variável, e o número de variáveis é
 * fixo por template.** As duas são regras da Meta, e desrespeitá-las é
 * reprovação — que reinicia dias de espera (risco R4).
 *
 * **4. Na dúvida, cai para o mais discreto.** Faltou o nome do profissional
 * numa mensagem em modo completo? Sai a discreta. O erro de revelar de menos se
 * conserta com um telefonema; o de revelar demais, não.
 *
 * A regra do modo discreto está escrita como teste em `templates.test.ts`.
 */

import { FUSO } from "@/lib/tempo";
import { formatar } from "@/lib/dinheiro";
// O nome do mês vem de `lib/meses` — a mesma função que escreve "agosto de
// 2026" na linha do mês das duas telas. Uma segunda formatação de competência
// aqui seria a segunda fonte de verdade em cima da palavra, não do número.
import { nomeDoMes } from "@/lib/meses";

export const FAMILIAS = [
  "oferta_de_vaga",
  "encaixe_confirmado",
  "lembrete_de_sessao",
  "aviso_de_desmarque",
  "aviso_de_cobranca",
  "lembrete_de_pagamento",
  "oferta_de_vaga_fixa",
  // A oitava, do P3. Ver o defeito no cabeçalho deste arquivo.
  "confirmacao_de_sessao",
  // As duas do B36, e elas são as primeiras que falam de **um período**, não de
  // uma sessão. O reajuste avisa a partir de quando o valor muda; a pausa avisa
  // que não haverá horário entre duas datas, e quando volta.
  //
  // Nenhuma das duas pede desculpa e nenhuma explica o porquê — nem inflação,
  // nem custo, nem "infelizmente". O valor é dela e o descanso é dela; o texto
  // informa e devolve a palavra à pessoa, que é o mesmo desenho do
  // `aviso_de_cobranca`.
  "aviso_de_reajuste",
  "aviso_de_pausa",
  /*
    A décima primeira, do B54 (§5.2 da estratégia do canal), e ela é a que
    **resolve** a tensão da classe `documento`.

    O recibo nunca trafega. A mensagem carrega só o aviso; o documento mora na
    página do paciente, atrás do link que ela já tem. Por isso a classe no banco
    é `rotina` e não `documento`: não há nada dentro deste texto que a fronteira
    8 proíba de sair por WhatsApp — nem valor, nem procedimento, nem período de
    atendimento.

    **E ela não carrega URL nenhuma.** O banco não conhece o endereço deste
    produto (o link do paciente é montado no navegador, com
    `window.location.origin`), e um link montado com endereço chutado é um link
    quebrado no celular de uma paciente. O texto diz "na sua página" e a pessoa
    abre o link que já recebeu. Quando existir um endereço declarado, o template
    ganha a variável.
  */
  "documento_disponivel",
] as const;

export type Familia = (typeof FAMILIAS)[number];
export type Modo = "discreto" | "completo";

export type Parametros = {
  /** Nome do paciente, congelado no enfileiramento. */
  nome?: string;
  modo?: string;
  /** Início da sessão ou da vaga, em ISO. */
  inicio?: string;
  /** Até quando a oferta vale, em ISO. */
  expira_em?: string;
  /** Nome do profissional. Sem ele, o modo completo não acontece. */
  profissional?: string;
  /** B36 · a data em que o valor novo passa a valer, em ISO (só a data). */
  vale_de?: string;
  /** B36 · o período da pausa, em ISO (só a data). */
  pausa_de?: string;
  pausa_ate?: string;
  /** Quantos horários o lembrete de pagamento cobre. */
  quantidade?: number;
  /** B54 · a competência do documento, em data pura ("2026-08-01"). */
  competencia?: string;
  /** B54 · `documentos.tipo`, para o modo completo nomear o papel. */
  tipo?: string;
  /**
   * O rótulo do horário recorrente — "terça, 15h" —, já montado pelo banco
   * (`rotulo_horario`, da 0031). Vem pronto de propósito: quem decide como um
   * horário fixo se escreve é uma função só, e ela é a mesma que monta o
   * contrato.
   */
  horario_fixo?: string;
  /**
   * O valor vem em centavos inteiros, e é `lib/dinheiro` que o formata — a
   * mesma função que a tela usa. Mandar a string pronta do banco criaria uma
   * segunda formatação de dinheiro no projeto, e duas formatações divergem.
   */
  valor_centavos?: number;
  [k: string]: unknown;
};

export type Renderizado = {
  familia: Familia;
  /** O modo **efetivo** — pode ser mais discreto do que o pedido. */
  modo: Modo;
  /** O nome aprovado na Meta. Discreto e completo são templates distintos. */
  nomeDoTemplate: string;
  /** As variáveis posicionais, na ordem em que o template as espera. */
  variaveis: string[];
  /** Corpo montado: é o que sai por SMS, por e-mail e no adaptador de registro. */
  texto: string;
  /** Assunto — só o canal e-mail usa. */
  assunto: string;
};

/** Palavras que jamais entram numa mensagem discreta. */
export const PROIBIDAS_NO_DISCRETO = [
  "terapia",
  "psicoterapia",
  "psicólog",
  "psicanáli",
  "consultório",
  "clínica",
  "paciente",
  "sessão",
  "sessões",
  "atendimento",
  "consulta",
] as const;

function ehFamilia(v: string): v is Familia {
  return (FAMILIAS as readonly string[]).includes(v);
}

const DIA_E_HORA = new Intl.DateTimeFormat("pt-BR", {
  timeZone: FUSO,
  weekday: "long",
  day: "numeric",
  month: "long",
  hour: "2-digit",
  minute: "2-digit",
});

const SO_HORA = new Intl.DateTimeFormat("pt-BR", {
  timeZone: FUSO,
  hour: "2-digit",
  minute: "2-digit",
});

/**
 * "terça-feira, 3 de março às 15:00". Fuso de São Paulo sempre — a lei nº 3.
 * Sem data utilizável, devolve uma expressão que não mente.
 */
function quando(iso: string | undefined): string {
  if (!iso) return "no horário combinado";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "no horário combinado";
  return DIA_E_HORA.format(d);
}

/** O prazo já vem como sintagma pronto: "às 16:20" ou "o fim do dia". */
function prazo(iso: string | undefined): string {
  if (!iso) return "o fim do dia";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "o fim do dia";
  return `às ${SO_HORA.format(d)}`;
}

const SO_DIA = new Intl.DateTimeFormat("pt-BR", {
  timeZone: FUSO,
  day: "numeric",
  month: "long",
});

/** "14 de outubro", ou uma expressão que não mente. */
function dia(iso: string | undefined, semData: string): string {
  if (!iso) return semData;
  // Data pura ("2026-10-14") é meia-noite UTC, que em São Paulo ainda é o dia
  // anterior. O meio-dia resolve, e é a lei nº 3 do jeito mais barato.
  const d = new Date(/^\d{4}-\d{2}-\d{2}$/.test(iso) ? `${iso}T12:00:00Z` : iso);
  if (Number.isNaN(d.getTime())) return semData;
  return SO_DIA.format(d);
}

/**
 * "14 e 25 de outubro" — o período da pausa.
 *
 * Sem as duas pontas não se inventa uma: o texto passa a falar do período sem
 * dizer qual, e quem recebe pergunta. Melhor do que uma data errada no celular
 * de alguém que ia sair de casa.
 */
function periodo(de: string | undefined, ate: string | undefined): string {
  const a = dia(de, "");
  const b = dia(ate, "");
  if (!a && !b) return "as datas que combinamos";
  if (!a) return `agora e ${b}`;
  if (!b) return `${a} e a data que combinamos`;
  if (a === b) return a;
  return `${a} e ${b}`;
}

/** O dia seguinte ao fim da pausa — em data pura, sem passar por fuso. */
function diaSeguinte(iso: string | undefined): string | undefined {
  if (!iso || !/^\d{4}-\d{2}-\d{2}$/.test(iso)) return undefined;
  const d = new Date(`${iso}T12:00:00Z`);
  if (Number.isNaN(d.getTime())) return undefined;
  d.setUTCDate(d.getUTCDate() + 1);
  return d.toISOString().slice(0, 10);
}

/** "R$ 100,00", ou uma expressão honesta quando não há número. */
function dinheiro(centavos: unknown): string {
  if (typeof centavos !== "number" || !Number.isFinite(centavos) || centavos <= 0) {
    return "o valor combinado";
  }
  return formatar(Math.round(centavos));
}

/** "um horário", "dois horários"… — número por extenso lê melhor que dígito. */
function horarios(quantidade: unknown): string {
  const n =
    typeof quantidade === "number" && Number.isInteger(quantidade) && quantidade > 0
      ? quantidade
      : 1;

  const extenso = ["", "um", "dois", "três", "quatro", "cinco", "seis", "sete", "oito", "nove"];
  const numero = n < extenso.length ? extenso[n] : String(n);
  return n === 1 ? "um horário" : `${numero} horários`;
}

/**
 * "às terças, 15h" — o horário que se repete.
 *
 * O banco manda "terça, 15h" e aqui vira plural: a diferença entre "terça, 15h"
 * e "às terças, 15h" é a diferença entre uma hora e um compromisso semanal, e é
 * exatamente o que esta família de mensagem precisa deixar claro.
 */
function horarioFixo(rotulo: string | undefined): string {
  const limpo = (rotulo ?? "").trim();
  // Sem rótulo não se inventa um dia. O banco sempre manda o dele; esta saída
  // existe para o texto continuar legível se um dia não mandar.
  if (!limpo) return "no dia e hora combinados";
  const [dia, ...resto] = limpo.split(", ");
  const plural = dia.endsWith("s") ? dia : `${dia}s`;
  return resto.length > 0 ? `às ${plural}, ${resto.join(", ")}` : `às ${plural}`;
}

/** Só o primeiro nome. Mensagem não é cadastro. */
function primeiroNome(nome: string | undefined): string {
  const limpo = (nome ?? "").trim();
  if (!limpo) return "tudo bem";
  return limpo.split(/\s+/)[0];
}

/** Palavras que jamais entram numa cobrança. */
export const PROIBIDAS_NA_COBRANCA = [
  "faltou",
  "falta",
  "ausência",
  "ausente",
  "não compareceu",
  "multa",
  "penalidade",
  "infelizmente",
  "lamento",
  "pendência",
  "devedor",
  "dívida",
  "em aberto",
  "atraso",
] as const;

/**
 * Palavras que jamais entram num lembrete de pagamento.
 *
 * Além das da cobrança: nada de ameaça, nada de prazo final, nada de
 * consequência. Uma régua que endurece a cada passo é cobrador; o que se repete
 * aqui é o fato, nunca a intensidade.
 */
export const PROIBIDAS_NA_REGUA = [
  "urgente",
  "última",
  "ultimo aviso",
  "último aviso",
  "prazo final",
  "regulariz",
  "negativ",
  "spc",
  "serasa",
  "protesto",
  "juros",
  "suspens",
  "cancelaremos",
  "providências",
  "cobrança judicial",
] as const;

/**
 * Os corpos, exatamente como vão para a Meta.
 *
 * `{{1}}` é sempre quem recebe, `{{2}}` sempre o horário. Nenhum começa nem
 * termina em variável, e a ordem de cada um está na tabela `VARIAVEIS`.
 *
 * ⚠️ **`aviso_de_cobranca` tem um portão que não é técnico.** A tese inteira do
 * produto é cobrar sem constrangimento — a psicóloga não cobra porque a conversa
 * é humilhante para as duas. Uma palavra errada aqui não gera um bug: gera o
 * problema que o produto existe para resolver. Por isso o texto não diz
 * "faltou", não diz "multa", não pede desculpa e não explica a regra de novo:
 * remete ao que já foi combinado, informa o valor e devolve a palavra à pessoa.
 *
 * Este texto é **rascunho até uma psicóloga lê-lo** (critério de pronto da B11
 * no doc 12, não item de QA). As proibições acima estão no teste; o julgamento
 * sobre o tom, não — esse é dela.
 */
export const CORPOS: Record<Modo, Record<Familia, string>> = {
  discreto: {
    oferta_de_vaga:
      "Oi, {{1}}. Abriu um horário {{2}}. Quer ficar com ele? " +
      "Responda SIM até {{3}} para confirmar. " +
      "Sem resposta, o horário segue para a próxima pessoa da lista.",
    encaixe_confirmado: "Oi, {{1}}. Seu horário {{2}} está confirmado. Até lá.",
    lembrete_de_sessao:
      "Oi, {{1}}. Passando para lembrar do seu horário {{2}}. Até lá.",
    aviso_de_desmarque:
      "Oi, {{1}}. Precisei desmarcar o horário {{2}}. Entro em contato para remarcar.",
    aviso_de_cobranca:
      "Oi, {{1}}. Sobre o horário {{2}}: pelo combinado, fica {{3}} referente a ele. " +
      "Se quiser conversar sobre isso, é só responder aqui.",
    lembrete_de_pagamento:
      "Oi, {{1}}. Passando para lembrar do combinado de {{2}}, referente a {{3}}. " +
      "Se quiser conversar sobre isso, é só responder aqui.",
    oferta_de_vaga_fixa:
      "Oi, {{1}}. Abriu um horário fixo {{2}}, toda semana. Quer ficar com ele? " +
      "Responda SIM até {{3}} e eu falo com você para combinar o começo. " +
      "Sem resposta, o horário segue para a próxima pessoa da lista.",
    confirmacao_de_sessao:
      "Oi, {{1}}. Você confirma o seu horário {{2}}? " +
      "Responda SIM ou NÃO por aqui, quando puder.",
    aviso_de_reajuste:
      "Oi, {{1}}. A partir de {{2}}, o valor do nosso horário passa a ser {{3}}. " +
      "Se quiser conversar sobre isso, é só responder aqui.",
    aviso_de_pausa:
      "Oi, {{1}}. Vou estar fora entre {{2}}, então nossos horários desse período " +
      "não acontecem. Volto {{3}}, no horário de sempre.",
    documento_disponivel:
      "Oi, {{1}}. Um documento seu de {{2}} já está disponível na sua página. " +
      "É só abrir o link que eu te enviei.",
  },
  completo: {
    oferta_de_vaga:
      "Oi, {{1}}. Abriu um horário {{2}} na agenda de {{4}}. Quer ficar com ele? " +
      "Responda SIM até {{3}} para confirmar. " +
      "Sem resposta, a vaga segue para a próxima pessoa da lista de espera.",
    encaixe_confirmado:
      "Oi, {{1}}. Sua sessão {{2}} com {{3}} está confirmada. Até lá.",
    lembrete_de_sessao:
      "Oi, {{1}}. Passando para lembrar da sua sessão {{2}} com {{3}}. Até lá.",
    aviso_de_desmarque:
      "Oi, {{1}}. A sessão {{2}} com {{3}} precisou ser desmarcada. " +
      "Entro em contato para remarcar.",
    aviso_de_cobranca:
      "Oi, {{1}}. Sobre a sessão {{2}} com {{3}}: pelo combinado, fica {{4}} referente a ela. " +
      "Se quiser conversar sobre isso, é só responder aqui.",
    lembrete_de_pagamento:
      "Oi, {{1}}. Passando para lembrar do combinado de {{2}} com {{3}}, referente a {{4}}. " +
      "Se quiser conversar sobre isso, é só responder aqui.",
    oferta_de_vaga_fixa:
      "Oi, {{1}}. Abriu um horário fixo {{2}}, toda semana, na agenda de {{4}}. " +
      "Quer ficar com ele? Responda SIM até {{3}} e eu falo com você para combinar " +
      "o começo. Sem resposta, o horário segue para a próxima pessoa da lista.",
    confirmacao_de_sessao:
      "Oi, {{1}}. Você confirma a sua sessão {{2}} com {{3}}? " +
      "Responda SIM ou NÃO por aqui, quando puder.",
    aviso_de_reajuste:
      "Oi, {{1}}. A partir de {{2}}, o valor da sessão com {{3}} passa a ser {{4}}. " +
      "Se quiser conversar sobre isso, é só responder aqui.",
    aviso_de_pausa:
      "Oi, {{1}}. {{2}} estará fora entre {{3}}, então as sessões desse período " +
      "não acontecem. Voltam {{4}}, no horário de sempre.",
    documento_disponivel:
      "Oi, {{1}}. O seu {{2}} de {{3}} já está disponível na página que {{4}} " +
      "te enviou. É só abrir o link.",
  },
};

/**
 * As variáveis de cada família, na ordem exata em que o corpo acima as usa.
 *
 * Ficam numa tabela, e não numa cadeia de condicionais, por um motivo prático:
 * variável fora de ordem não quebra nada — só troca o horário pelo valor no
 * celular de alguém. O teste confere que a contagem bate com o corpo; a ordem
 * é responsabilidade desta tabela, que dá para conferir a olho.
 */
const VARIAVEIS: Record<Modo, Record<Familia, (c: Campos) => string[]>> = {
  discreto: {
    oferta_de_vaga: (c) => [c.nome, c.hora, c.limite],
    encaixe_confirmado: (c) => [c.nome, c.hora],
    lembrete_de_sessao: (c) => [c.nome, c.hora],
    aviso_de_desmarque: (c) => [c.nome, c.hora],
    aviso_de_cobranca: (c) => [c.nome, c.hora, c.valor],
    lembrete_de_pagamento: (c) => [c.nome, c.valor, c.quantos],
    oferta_de_vaga_fixa: (c) => [c.nome, c.fixo, c.limite],
    confirmacao_de_sessao: (c) => [c.nome, c.hora],
    aviso_de_reajuste: (c) => [c.nome, c.desde, c.valor],
    aviso_de_pausa: (c) => [c.nome, c.pausa, c.volta],
    documento_disponivel: (c) => [c.nome, c.mes],
  },
  completo: {
    oferta_de_vaga: (c) => [c.nome, c.hora, c.limite, c.prof],
    encaixe_confirmado: (c) => [c.nome, c.hora, c.prof],
    lembrete_de_sessao: (c) => [c.nome, c.hora, c.prof],
    aviso_de_desmarque: (c) => [c.nome, c.hora, c.prof],
    aviso_de_cobranca: (c) => [c.nome, c.hora, c.prof, c.valor],
    lembrete_de_pagamento: (c) => [c.nome, c.valor, c.prof, c.quantos],
    oferta_de_vaga_fixa: (c) => [c.nome, c.fixo, c.limite, c.prof],
    confirmacao_de_sessao: (c) => [c.nome, c.hora, c.prof],
    aviso_de_reajuste: (c) => [c.nome, c.desde, c.prof, c.valor],
    aviso_de_pausa: (c) => [c.nome, c.prof, c.pausa, c.volta],
    documento_disponivel: (c) => [c.nome, c.papel, c.mes, c.prof],
  },
};

type Campos = {
  nome: string;
  hora: string;
  limite: string;
  prof: string;
  valor: string;
  quantos: string;
  fixo: string;
  /** B36 · a partir de quando o valor novo vale. */
  desde: string;
  /** B36 · o período da pausa, e o dia em que os horários voltam. */
  pausa: string;
  volta: string;
  /** B54 · "agosto de 2026" e "recibo" — a competência e o papel. */
  mes: string;
  papel: string;
};

/**
 * Monta a mensagem.
 *
 * O modo discreto nunca cita o profissional nem a natureza do encontro — não
 * porque seja segredo, mas porque a tela do celular é lida por quem passa. É a
 * fronteira D3 do doc 11, e a violação dela é dano que não se desfaz.
 */
export function renderizar(template: string, params: Parametros): Renderizado {
  if (!ehFamilia(template)) {
    throw new Error(`Template desconhecido: ${template}`);
  }

  const nome = primeiroNome(params.nome);
  const hora = quando(params.inicio);
  const limite = prazo(params.expira_em);
  const prof = (params.profissional ?? "").trim();

  // O modo pedido só vale se houver com que preenchê-lo. Sem o nome do
  // profissional, o template completo ficaria com variável vazia — que a Meta
  // recusa — e a saída certa é a mais discreta, nunca a menos.
  const modo: Modo = params.modo === "completo" && prof ? "completo" : "discreto";

  const valor = dinheiro(params.valor_centavos);
  const quantos = horarios(params.quantidade);
  const fixo = horarioFixo(params.horario_fixo);
  const desde = dia(params.vale_de, "a data que combinamos");
  const pausa = periodo(params.pausa_de, params.pausa_ate);
  // O dia em que volta é o seguinte ao fim da pausa, e a conta é feita aqui em
  // vez de vir pronta: quem enfileira já mandou o fim do período, e derivar dele
  // é uma fonte de verdade a menos.
  const volta = dia(diaSeguinte(params.pausa_ate), "assim que eu voltar");
  // Sem competência não se inventa um mês: "de um período" é vago e verdadeiro,
  // e "de agosto" errado manda a pessoa procurar o papel do mês errado.
  const mes = nomeDoMes(
    typeof params.competencia === "string" ? params.competencia : null,
    "um período",
  );
  const papel = papelDoDocumento(params.tipo);
  const variaveis = VARIAVEIS[modo][template]({
    nome, hora, limite, prof, valor, quantos, fixo, desde, pausa, volta, mes, papel,
  });

  return {
    familia: template,
    modo,
    nomeDoTemplate: `sessoes_${template}_${modo}`,
    variaveis,
    texto: preencher(CORPOS[modo][template], variaveis),
    assunto: assunto(template, modo),
  };
}

/**
 * "recibo", "declaração", "informe" — e "documento" para o que não se conhece.
 *
 * O modo discreto **não** usa esta função: lá o papel é sempre "um documento
 * seu". Nomear o papel diz o que a pessoa foi buscar num consultório, e é a
 * mesma régua que tira o nome do profissional da mensagem discreta.
 */
function papelDoDocumento(tipo: string | undefined): string {
  switch ((tipo ?? "").trim()) {
    case "recibo":
      return "recibo";
    case "declaracao_comparecimento":
      return "declaração";
    case "informe_anual":
      return "informe";
    default:
      return "documento";
  }
}

/** Troca `{{n}}` pelo n-ésimo valor. É a mesma substituição que a Meta faz. */
function preencher(corpo: string, variaveis: string[]): string {
  return corpo.replace(/\{\{(\d+)\}\}/g, (inteiro, n: string) => {
    const valor = variaveis[Number(n) - 1];
    return valor ?? inteiro;
  });
}

function assunto(familia: Familia, modo: Modo): string {
  if (modo === "discreto") {
    return {
      oferta_de_vaga: "Abriu um horário",
      encaixe_confirmado: "Horário confirmado",
      lembrete_de_sessao: "Lembrete de horário",
      aviso_de_desmarque: "Mudança no horário",
      aviso_de_cobranca: "Sobre um horário",
      lembrete_de_pagamento: "Sobre o combinado",
      oferta_de_vaga_fixa: "Abriu um horário fixo",
      confirmacao_de_sessao: "Confirma o seu horário?",
      aviso_de_reajuste: "Sobre o nosso combinado",
      aviso_de_pausa: "Sobre os próximos horários",
      documento_disponivel: "Um documento seu",
    }[familia];
  }

  return {
    oferta_de_vaga: "Abriu um horário na agenda",
    encaixe_confirmado: "Sua sessão está confirmada",
    lembrete_de_sessao: "Lembrete da sua sessão",
    aviso_de_desmarque: "Sua sessão precisou ser desmarcada",
    aviso_de_cobranca: "Sobre uma sessão",
    lembrete_de_pagamento: "Sobre o combinado",
    oferta_de_vaga_fixa: "Abriu um horário fixo na agenda",
    confirmacao_de_sessao: "Confirma a sua sessão?",
    aviso_de_reajuste: "Sobre o valor das sessões",
    aviso_de_pausa: "Sessões suspensas por um período",
    documento_disponivel: "O seu documento está disponível",
  }[familia];
}
