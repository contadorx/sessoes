/**
 * Cinco destinos, e o que sobra vai para o perfil.
 *
 * POR QUE ISTO EXISTE
 *
 * O menu tinha doze itens de mesmo peso: *Agenda · Calendário · Fila · Vagas ·
 * Pacientes · Em aberto · Financeiro · Receita · Contador · Documentos · Conta
 * · Sair*. Uma auditoria externa listou os três defeitos, e os três são o
 * mesmo defeito:
 *
 *   1. **A navegação representava as tabelas, não o trabalho.** "Agenda", que
 *      ela abre todo dia, tinha o mesmo peso que "Calendário", que se
 *      configura uma vez, e que "Vagas", que se usa a cada vários meses.
 *
 *   2. **"Fila" e "Vagas" descrevem mecanismos.** Os nomes são vizinhos
 *      semanticamente e não dizem a diferença entre preencher uma ausência
 *      pontual e oferecer um horário recorrente — a ponto de a dona do
 *      produto confundir os dois. Errar aqui é errar na feature-âncora.
 *
 *   3. **Uma sessão vivia espalhada por seis telas.** Marcar realizada na
 *      Agenda, cobrar em "Em aberto", conferir o recebimento no "Financeiro",
 *      emitir recibo em "Receita", fechar no "Contador", arquivar em
 *      "Documentos". O modelo de dados é centrado na sessão; a interação era
 *      centrada nos departamentos do software.
 *
 * A resposta é uma só: **o menu passa a nomear o trabalho dela.**
 *
 *     Agenda · Encaixes · Pacientes · Recebimentos · Fechamento
 *
 * E, à direita, o que não é destino: buscar, as pendências com prazo, o botão
 * Novo e o perfil. Configuração e arquivo saem da rotina.
 *
 *
 * O CONTRA-ARGUMENTO, QUE É BOM
 *
 * Agrupar esconde Receita Saúde e a pasta do contador — justamente as duas
 * áreas com prazo legal, onde atrasar custa multa. A auditoria levantou isso
 * contra a própria recomendação, e ela tem razão pela metade.
 *
 * A metade certa é que **prazo não pode depender de a pessoa lembrar de
 * abrir uma aba**. A metade errada é concluir daí que prazo precisa de módulo
 * permanente: um item de menu que fica lá o ano inteiro é exatamente o tipo de
 * alarme que se aprende a não ver.
 *
 * Por isso os prazos viram `pendencias()` — uma faixa no topo da Agenda, que é
 * a tela que ela abre, com o que vence e quando, e que **some quando não há
 * nada vencendo**. Alarme que só toca quando é para tocar.
 *
 *
 * O QUE ESTE MÓDULO NÃO É
 *
 * Não é autorização. `destinos()` esconde o que a pessoa não pode usar para a
 * tela não oferecer o que vai recusar depois; quem barra é a RLS (migração
 * 0049) e, antes dela, o `sessaoAtual()` de cada página. Esconder aba nunca
 * foi tranca — é cortesia.
 */

import { podeClinico, podeFinanceiro, type Acessos } from "./permissao";

export type Destino = {
  href: string;
  /** O nome no desktop. */
  rotulo: string;
  /** O nome no celular, onde cabe menos. "Receber" é mais curto que "Recebimentos". */
  curto: string;
  /** Uma linha, para quem passa o mouse e para quem usa leitor de tela. */
  descricao: string;
};

const AGENDA: Destino = {
  href: "/agenda",
  rotulo: "Agenda",
  curto: "Agenda",
  descricao: "Hoje, a semana e o painel completo de cada sessão",
};

const ENCAIXES: Destino = {
  href: "/encaixes",
  rotulo: "Encaixes",
  curto: "Encaixes",
  descricao: "Quem espera vaga, as ofertas em andamento e os horários fixos",
};

const PACIENTES: Destino = {
  href: "/pacientes",
  rotulo: "Pacientes",
  curto: "Pacientes",
  descricao: "Cadastro, combinado e — com acesso clínico — o prontuário",
};

const RECEBIMENTOS: Destino = {
  href: "/recebimentos",
  rotulo: "Recebimentos",
  curto: "Receber",
  descricao: "A receber, conciliação do Pix, entradas, estornos e despesas",
};

const FECHAMENTO: Destino = {
  href: "/fechamento",
  rotulo: "Fechamento",
  curto: "Fechamento",
  descricao: "O mês, a Receita Saúde, a pasta do contador e os documentos",
};

/**
 * Os cinco, filtrados pelo que a pessoa pode.
 *
 * Agenda, Encaixes e Pacientes ficam para todo mundo: sem eles não se marca
 * uma sessão, e tirar isso da secretária devolve o trabalho para a psicóloga
 * — que é o oposto do produto inteiro.
 *
 * Recebimentos e Fechamento pedem o eixo financeiro. Não é hierarquia: é a
 * mesma pergunta que a RLS faz antes de devolver uma cobrança.
 */
export function destinos(a: Acessos): Destino[] {
  const fim = podeFinanceiro(a) ? [RECEBIMENTOS, FECHAMENTO] : [];
  return [AGENDA, ENCAIXES, PACIENTES, ...fim];
}

/**
 * A barra de baixo do celular. Cinco é o teto — a sexta cadeira vira um item
 * que ninguém acerta com o polegar.
 *
 * Quando os cinco cabem, o quinto é "Mais". Quando a pessoa não tem o eixo
 * financeiro e sobram três destinos, "Mais" ainda existe: é onde moram perfil,
 * ajuda e sair.
 */
export type ItemCelular = Destino | { href: "/perfil"; rotulo: "Mais"; curto: "Mais"; descricao: string };

export function barraDoCelular(a: Acessos): ItemCelular[] {
  const d = destinos(a);
  const mais = {
    href: "/perfil" as const,
    rotulo: "Mais" as const,
    curto: "Mais" as const,
    descricao: "Fechamento, documentos, configurações, ajuda e sair",
  };
  // Quatro destinos + Mais = cinco cadeiras. Com o eixo financeiro são cinco
  // destinos, e o Fechamento desce para o Mais — é mensal, e o polegar dela
  // não deve gastar uma cadeira com o que se abre uma vez por mês.
  const primeiros = d.filter((x) => x.href !== "/fechamento");
  return [...primeiros, mais];
}

// ============================================ as pendências com prazo

/**
 * O que vence, e quando.
 *
 * Uma pendência só existe aqui se **tem prazo e o prazo tem consequência**.
 * "Três pacientes sem anamnese" não entra: é trabalho, não é prazo. Recibo da
 * Receita Saúde e fechamento do contador entram, porque atrasar custa dinheiro
 * e a psicóloga descobre tarde.
 */
export type Pendencia = {
  chave: string;
  /** "2 recibos" — o que é, com o número, sem adjetivo. */
  o_que: string;
  /** "10/09" — quando vence. */
  ate: string;
  href: string;
  /** Vence em três dias ou menos, ou já venceu. */
  urgente: boolean;
};

export type PrazosDoMes = {
  recibosPendentes: number;
  recibosAte: string | null;
  recibosUrgente: boolean;
  contadorAberto: boolean;
  contadorAte: string | null;
  contadorUrgente: boolean;
};

export function pendencias(p: PrazosDoMes, a: Acessos): Pendencia[] {
  // Sem o eixo financeiro não há prazo a mostrar: a pessoa não pode nem abrir
  // a lista que a faixa aponta. Faixa que leva a uma tela vazia é pior que
  // faixa nenhuma.
  if (!podeFinanceiro(a)) return [];

  const fora: Pendencia[] = [];

  if (p.recibosPendentes > 0 && p.recibosAte) {
    fora.push({
      chave: "recibos",
      o_que: p.recibosPendentes === 1 ? "1 recibo" : `${p.recibosPendentes} recibos`,
      ate: p.recibosAte,
      href: "/fechamento/receita-saude",
      urgente: p.recibosUrgente,
    });
  }

  if (p.contadorAberto && p.contadorAte) {
    fora.push({
      chave: "contador",
      o_que: "fechamento do contador",
      ate: p.contadorAte,
      href: "/fechamento/contador",
      urgente: p.contadorUrgente,
    });
  }

  return fora;
}

/**
 * A frase da faixa. Compacta, sem gráfico, sem percentual, sem linguagem de
 * painel — ela está indo atender daqui a dez minutos.
 */
export function fraseDasPendencias(ps: Pendencia[]): string {
  if (ps.length === 0) return "";
  const cabeca = ps.length === 1 ? "1 pendência com prazo neste mês" : `${ps.length} pendências com prazo neste mês`;
  return `${cabeca}: ${ps.map((p) => `${p.o_que} até ${p.ate}`).join(" · ")}.`;
}

// ============================================ o botão Novo

export type AcaoNova = { href: string; rotulo: string };

/**
 * O que o botão Novo oferece, e nada além.
 *
 * Quatro coisas nascem no produto: uma sessão, um paciente, um recebimento e
 * um pedido de encaixe. As duas do meio dependem do que a pessoa pode.
 */
export function acoesNovas(a: Acessos): AcaoNova[] {
  const fora: AcaoNova[] = [
    { href: "/agenda?novo=sessao", rotulo: "Sessão" },
    { href: "/pacientes/novo", rotulo: "Paciente" },
    { href: "/encaixes?novo=pedido", rotulo: "Pedido de encaixe" },
  ];
  if (podeFinanceiro(a)) {
    fora.push({ href: "/recebimentos?novo=entrada", rotulo: "Recebimento" });
  }
  return fora;
}

// ============================================ a busca

export type TipoDeAchado = "paciente" | "sessao" | "documento" | "pagamento";

export const ROTULO_ACHADO: Record<TipoDeAchado, string> = {
  paciente: "paciente",
  sessao: "sessão",
  documento: "documento",
  pagamento: "pagamento",
};

/**
 * Onde a busca procura, para esta pessoa.
 *
 * Buscar num lugar que a RLS vai esvaziar produz "nenhum resultado" — que a
 * pessoa lê como "não existe", e não como "não é para você". As duas
 * respostas são erradas de jeitos diferentes, e a segunda é pior: ela vai
 * procurar de novo.
 */
export function ondeBuscar(a: Acessos): TipoDeAchado[] {
  const fora: TipoDeAchado[] = ["paciente", "sessao"];
  if (podeFinanceiro(a)) fora.push("documento", "pagamento");
  return fora;
}

/**
 * A busca só sai com dois caracteres. Com um, ela devolve a base inteira e
 * demora — e ninguém procura ninguém por uma letra.
 */
export function buscavel(termo: string): boolean {
  return termo.trim().length >= 2;
}

export function fraseDoVazio(termo: string, a: Acessos): string {
  if (!buscavel(termo)) return "Digite pelo menos duas letras.";
  const onde = ondeBuscar(a)
    .map((t) => ROTULO_ACHADO[t])
    .join(", ");
  return `Nada encontrado em ${onde}.`;
}

// ============================================ o painel da sessão

/**
 * Tudo o que se faz com uma sessão, no lugar onde ela está.
 *
 * Era a peregrinação entre seis módulos. Agora a sessão responde por si: o
 * painel dela oferece registrar, cobrar, lembrar, documentar, repor e ver o
 * que falta para o fechamento — e as telas agregadas continuam existindo para
 * quem quer despachar várias pendências de uma vez.
 *
 * A ordem não é decorativa: é a ordem em que as coisas acontecem na vida dela.
 * Primeiro aconteceu, depois foi pago, depois virou papel.
 */
export type AcaoDaSessao =
  | "registrar"
  | "cobranca"
  | "lembrete"
  | "documento"
  | "reposicao"
  | "fechamento";

export const ROTULO_ACAO_SESSAO: Record<AcaoDaSessao, string> = {
  registrar: "O que aconteceu",
  cobranca: "Cobrança e pagamento",
  lembrete: "Lembrete",
  documento: "Documento",
  reposicao: "Reposição",
  fechamento: "O que falta para fechar o mês",
};

export function acoesDaSessao(a: Acessos): AcaoDaSessao[] {
  const fora: AcaoDaSessao[] = ["registrar", "lembrete", "reposicao"];
  if (podeFinanceiro(a)) {
    fora.splice(1, 0, "cobranca");
    fora.push("documento", "fechamento");
  }
  // "registrar" é o único que pede o eixo clínico? Não: marcar realizada ou
  // falta é fato administrativo, e quem marca a agenda marca isso. O que pede
  // o eixo clínico é a evolução, e ela mora dentro do paciente — não aqui.
  return fora;
}

// ============================================ as abas da ficha do paciente

/**
 * O que a ficha de um paciente mostra, para esta pessoa.
 *
 * É aqui que a auditoria pedia *"cadastro, dados administrativos e área
 * clínica conforme permissão"*, e é o único lugar do produto onde os dois
 * eixos aparecem na mesma tela: quem marca a agenda precisa do nome, do
 * telefone e do horário combinado; quem atende precisa do registro; quem cuida
 * do caixa precisa do que está a receber.
 *
 * A ordem é a da vida da ficha: quem é, o que foi combinado, o que aconteceu
 * na clínica, o que aconteceu no dinheiro.
 */
export type AbaDoPaciente = "cadastro" | "combinado" | "clinico" | "financeiro";

export const ROTULO_ABA: Record<AbaDoPaciente, string> = {
  cadastro: "Cadastro",
  combinado: "Combinado",
  clinico: "Registro clínico",
  financeiro: "Pagamentos",
};

export function abasDoPaciente(a: Acessos): AbaDoPaciente[] {
  const fora: AbaDoPaciente[] = ["cadastro", "combinado"];
  if (podeClinico(a)) fora.push("clinico");
  if (podeFinanceiro(a)) fora.push("financeiro");
  return fora;
}

// ============================================ o que os destinos contêm

/**
 * As seções de cada destino, para a sub-navegação e para o mapa do produto.
 *
 * Está aqui, e não espalhado nas páginas, porque foi exatamente assim que doze
 * itens apareceram sem ninguém decidir por doze: cada tela nova acrescentava
 * um link no cabeçalho. Uma lista num arquivo só é uma lista que dá para
 * contar.
 */
export const SECOES: Record<string, { href: string; rotulo: string }[]> = {
  "/encaixes": [
    { href: "/encaixes", rotulo: "Pedidos e ofertas" },
    { href: "/encaixes/fixos", rotulo: "Horários fixos" },
  ],
  "/recebimentos": [
    { href: "/recebimentos", rotulo: "A receber" },
    { href: "/recebimentos/movimentacoes", rotulo: "Movimentações e despesas" },
  ],
  "/fechamento": [
    { href: "/fechamento", rotulo: "O mês" },
    { href: "/fechamento/receita-saude", rotulo: "Receita Saúde" },
    { href: "/fechamento/contador", rotulo: "Pasta do contador" },
    { href: "/fechamento/documentos", rotulo: "Documentos" },
  ],
  "/perfil": [
    { href: "/perfil", rotulo: "Conta e cobrança" },
    { href: "/perfil/integracoes", rotulo: "Integrações" },
    { href: "/perfil/contrato", rotulo: "Contrato" },
  ],
};

/**
 * Qual dos cinco está aberto — para grifar um item, e só um.
 *
 * `/fechamento/receita-saude` grifa "Fechamento". `/encaixes/fixos` grifa
 * "Encaixes". A comparação é por prefixo de segmento, não por `startsWith`
 * cru: `/recebimentos` não pode grifar por causa de um futuro
 * `/recebimentos-antigos`.
 */
export function destinoAtivo(caminho: string, href: string): boolean {
  if (href === "/agenda") return caminho === "/agenda" || caminho.startsWith("/agenda/");
  return caminho === href || caminho.startsWith(href + "/");
}
