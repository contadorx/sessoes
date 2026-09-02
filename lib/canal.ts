/**
 * O canal de saída do plano — do lado do app (OP9).
 *
 * A escada tem três degraus no `claude/25`, e o produto tem **dois**:
 *
 *   · **manual** — a mensagem nasce pronta, com o texto renderizado e um link
 *     `wa.me`, e sai **do número dela** quando ela toca. É o plano Grátis;
 *   · **plataforma** — sai sozinha, pelo número do Sessões. É todo plano pago.
 *
 * O terceiro degrau — automático **e** do número dela, via BSP com Embedded
 * Signup — é o quadrante vazio do mercado que a pesquisa do `claude/24`
 * encontrou, e não existe. Ele não está neste tipo de propósito: um valor que
 * o produto não sabe entregar vira, na primeira semana, uma linha de página de
 * preço.
 *
 * **O que o canal nunca alcança:** template essencial. Lembrete de véspera,
 * aviso de desmarque, confirmação de encaixe e pedido de confirmação saem
 * sozinhos em qualquer plano, inclusive no Grátis. Quem ficaria sem eles é a
 * paciente, e ela não escolheu plano nenhum.
 */

export const CANAIS = ["manual", "plataforma"] as const;
export type Canal = (typeof CANAIS)[number];

/**
 * Uma mensagem esperando o dedo dela. Gêmeo de `mensagens_na_sua_mao`.
 */
export type NaMao = {
  id: string;
  template: string;
  destino: string;
  params: Record<string, unknown>;
  paciente_id: string;
  paciente: string;
  espera_desde: string;
  oferta_id: string | null;
};

/**
 * O link.
 *
 * Mesmo padrão que o `Lastro.tsx` e o `Remarcar.tsx` já usam desde a B19 —
 * dígitos e `encodeURIComponent`, e nada mais. Devolve `null` sem destino, em
 * vez de um link quebrado: um botão que abre o WhatsApp em branco é pior do que
 * um botão que não existe, porque ela descobre depois de sair da tela.
 */
export function linkDoWhatsapp(destino: string | null, texto: string): string | null {
  if (!destino) return null;
  const numero = destino.replace(/\D/g, "");
  if (numero.length < 10) return null;
  return `https://wa.me/${numero}?text=${encodeURIComponent(texto)}`;
}

/**
 * Há quanto tempo está parada, em português.
 *
 * A unidade sobe conforme o tempo passa porque "esperando há 187 minutos" é um
 * número que ninguém converte de cabeça, e a conversão é justamente o momento em
 * que a pessoa desiste de ler.
 */
export function espera(desdeISO: string, agora = new Date()): string {
  const min = Math.floor((agora.getTime() - new Date(desdeISO).getTime()) / 60000);
  if (min < 1) return "agora";
  if (min < 60) return `há ${min} min`;
  const h = Math.floor(min / 60);
  if (h < 24) return h === 1 ? "há 1 hora" : `há ${h} horas`;
  const d = Math.floor(h / 24);
  return d === 1 ? "há 1 dia" : `há ${d} dias`;
}

/**
 * O que cada mensagem é, dito em uma linha.
 *
 * O rótulo vem do template e não do texto: o texto é para a paciente, e ela
 * precisa saber, antes de abrir, se aquilo é uma vaga ou uma cobrança — são
 * duas conversas com temperaturas muito diferentes.
 */
export function rotuloDoQueE(template: string): string {
  switch (template) {
    case "oferta_de_vaga":
      return "oferecer a vaga";
    case "oferta_de_vaga_fixa":
      return "oferecer o horário fixo";
    case "aviso_de_cobranca":
      return "avisar da cobrança";
    case "lembrete_de_pagamento":
      return "lembrar do pagamento";
    default:
      return "mandar";
  }
}

/**
 * A urgência, e ela é do tipo de mensagem — não do relógio.
 *
 * A oferta de vaga é a única que **caduca por natureza**: enquanto ela não sai,
 * a hora continua vazia e ninguém foi convidado. O aviso de cobrança pode
 * esperar a tarde inteira sem que nada se perca.
 *
 * A tela usa isso para ordenar, e não para gritar. Não há contagem regressiva,
 * não há vermelho piscando: o relógio da oferta só começa quando ela manda, e
 * inventar pressa sobre uma decisão dela seria a mesma coisa que a política
 * assistida do P4 recusou fazer.
 */
export function primeiroNaFila(a: NaMao, b: NaMao): number {
  const peso = (m: NaMao) => (m.oferta_id ? 0 : 1);
  const d = peso(a) - peso(b);
  if (d !== 0) return d;
  return new Date(a.espera_desde).getTime() - new Date(b.espera_desde).getTime();
}

// ───────────────────────────────────────────────────────── a medida

export type ResumoManual = {
  manual: boolean;
  na_mao_agora: number;
  mais_antiga_horas: number | null;
  enviadas_no_mes: number;
  mediana_minutos: number | null;
};

export const SEM_RESUMO: ResumoManual = {
  manual: false,
  na_mao_agora: 0,
  mais_antiga_horas: null,
  enviadas_no_mes: 0,
  mediana_minutos: null,
};

/**
 * A frase da medida, e ela é o único argumento de upgrade deste produto.
 *
 * Ela é feita de **números dela**: quantas estão paradas, há quanto tempo a mais
 * antiga está, e quanto tempo ela costuma levar. Não há comparação com uma média
 * do plano automático, e não vai haver enquanto essa média não existir de
 * verdade — o `claude/25` propõe a frase *"no automático a média é 5"*, e a
 * segunda metade dela é uma afirmação sobre dados que ninguém mediu.
 *
 * E não há juízo: "você demorou" seria uma frase sobre ela. "A vaga ficou
 * parada" é uma frase sobre a vaga, que é o que de fato aconteceu.
 */
export function fraseDoManual(r: ResumoManual): string {
  if (!r.manual) return "";
  if (r.na_mao_agora === 0 && r.enviadas_no_mes === 0) {
    return "No plano Grátis, a fila e a cobrança saem do seu WhatsApp, com um toque seu. Nada está esperando agora.";
  }
  const partes: string[] = [];
  if (r.na_mao_agora === 1) partes.push("1 mensagem esperando o seu toque");
  else if (r.na_mao_agora > 1) partes.push(`${r.na_mao_agora} mensagens esperando o seu toque`);

  if (r.na_mao_agora > 0 && r.mais_antiga_horas !== null && r.mais_antiga_horas >= 1) {
    partes.push(`a mais antiga há ${formatarHoras(r.mais_antiga_horas)}`);
  }
  if (r.enviadas_no_mes > 0 && r.mediana_minutos !== null) {
    partes.push(`neste mês você mandou ${r.enviadas_no_mes}, tipicamente ${emMinutos(r.mediana_minutos)} depois`);
  }
  return partes.length > 0 ? partes.join(" · ") + "." : "";
}

function formatarHoras(h: number): string {
  if (h < 24) return h === 1 ? "1 hora" : `${Math.round(h)} horas`;
  const d = Math.round(h / 24);
  return d === 1 ? "1 dia" : `${d} dias`;
}

function emMinutos(m: number): string {
  if (m < 60) return `${Math.round(m)} min`;
  const h = m / 60;
  return h < 24 ? (Math.round(h) === 1 ? "1 hora" : `${Math.round(h)} horas`) : formatarHoras(h);
}

/**
 * O que muda se ela subir de plano — dito sem promessa que não se cumpre.
 *
 * A frase não diz que ela vai preencher mais vagas: diz o que o sistema passa a
 * fazer. Preencher depende da paciente, e prometer resultado de terceiro é o
 * tipo de linha que a auditoria de 01/09 tirou da landing inteira.
 */
export function fraseDoQueMudaNoPago(): string {
  return "Nos planos pagos, essas mensagens saem sozinhas, na hora em que a vaga abre — pelo número do Sessões.";
}
