/**
 * Os planos, do lado do app — e a escada que não pode descer (0064).
 *
 * Este módulo existe por um defeito concreto: até 02/09, a tabela de preços da
 * landing era uma constante escrita à mão dentro de `app/(site)/page.tsx`, e o
 * banco tinha os mesmos números com valores diferentes. Não era desleixo, era
 * a consequência inevitável de o mesmo dado morar em dois lugares — e o lugar
 * que estava errado era o que **cobra** (`planos.preco_centavos` achava que a
 * Clínica custava R$ 249 fossem cinco profissionais ou uma).
 *
 * Aqui os números vivem uma vez, com os **mesmos valores esperados da suíte
 * 0064**. A suíte prova o banco; estes testes provam a página; e os dois usam a
 * mesma aritmética escrita duas vezes de propósito, que é como se pega
 * divergência entre camadas.
 *
 * ---
 *
 * **As três regras que o módulo carrega, e que valem mais que os números:**
 *
 * 1. **`codigo` é a palavra do sistema; `nome` é a palavra dela.** O código
 *    viaja na chave estrangeira de `contas.plano`, na URL `?plano=solo` e nos
 *    metadados do cadastro. O nome muda quando o marketing muda. Os dois nunca
 *    se encontram.
 *
 * 2. **`recursos` é o que existe; `porVir` é o que está no roadmap.** As duas
 *    listas são disjuntas, e no banco isso é uma restrição (`check (not
 *    (recursos && por_vir))`). Aqui é um teste. Uma linha não pode ser vendida
 *    e prometida ao mesmo tempo — foi assim que a página passou meses vendendo
 *    briefing, radar de furo e portal do paciente, três coisas que o doc 30
 *    matou e que nunca existiram.
 *
 * 3. **A faixa não é uma cerca, e nos planos de cima ela nem aparece.** Onde
 *    `fairUse` é verdadeiro, o número é meu e não dela: serve para eu enxergar
 *    a clínica disfarçada de autônoma, e o `lib/faixa.ts` cala. O cartão diz
 *    "sem faixa de sessões", e a tela dela concorda.
 */

export type CodigoDePlano = "gratis" | "solo" | "pro" | "clinica";

export type Plano = {
  /** A palavra do sistema. Chave estrangeira, URL, metadado. Nunca aparece. */
  codigo: CodigoDePlano;
  /** A palavra dela. Muda com um `update`, sem migração de chave. */
  nome: string;
  precoCentavos: number;
  /**
   * Acréscimo por profissional **além da primeira** — `null` em plano de preço
   * fixo. `precoCentavos` já inclui uma.
   */
  precoPorProfissionalCentavos: number | null;
  /**
   * Sessões por mês, **por profissional ativo**. `null` = sem faixa, e o
   * Gratuito é assim desde a 0064: o limite dele é o canal manual, não um
   * número.
   */
  faixa: number | null;
  /** `true` = o número é meu, e o cartão diz "sem faixa". */
  fairUse: boolean;
  /** `manual` = a mensagem espera o dedo dela (OP9). */
  canal: "manual" | "plataforma";
  detalhe: string;
  selo?: string;
  destaque?: boolean;
  cta: string;
  href: string;
  /** O que a conta neste plano FAZ hoje. É o que a página vende. */
  recursos: string[];
  /** O que está no roadmap. A página mostra sob rótulo, sem preço e sem data. */
  porVir: string[];
};

/**
 * Os quatro, na ordem em que aparecem — e os mesmos valores da suíte 0064.
 *
 * Os nomes vêm do `claude/25`, revisão 4: eles descrevem **onde ela atende**,
 * não quanto ela cabe. "Eu tenho um consultório" é uma frase que ela diz; "eu
 * sou Pro" não é.
 */
export const PLANOS: Plano[] = [
  {
    codigo: "gratis",
    nome: "Gratuito",
    precoCentavos: 0,
    precoPorProfissionalCentavos: null,
    faixa: null,
    fairUse: false,
    canal: "manual",
    detalhe: "para sempre",
    cta: "Criar conta grátis",
    href: "/entrar?criar",
    // O Gratuito não tem `porVir`, e é decisão: uma lista de "em breve" no
    // plano de entrada é lida por quem está avaliando como "ainda não serve".
    recursos: [
      "Agenda, prontuário e o registro do que aconteceu com cada horário",
      "Pacientes sem limite",
      "Sessões sem limite",
      "Fila e página da vaga, completas",
      "Lembrete de véspera e aviso de desmarque saem sozinhos",
      "Política de cancelamento congelada no contrato",
      "Cobrança, recibo e informe",
      "A fila e a cobrança saem do seu WhatsApp, com um toque seu",
    ],
    porVir: [],
  },
  {
    codigo: "solo",
    nome: "Consultório",
    precoCentavos: 6900,
    precoPorProfissionalCentavos: null,
    faixa: 60,
    fairUse: false,
    canal: "plataforma",
    detalhe: "por mês",
    destaque: true,
    selo: "para quem atende sozinha",
    // O plano viaja na URL, aparece de volta na tela de criar conta e vai nos
    // metadados do cadastro. O rótulo diz o que o clique faz: cria a conta e
    // **pede** o plano — toda conta nasce no Gratuito, porque não existe
    // assinatura self-service (OP5).
    cta: "Criar conta e pedir o Consultório",
    href: "/entrar?criar&plano=solo",
    recursos: [
      "Tudo do Gratuito",
      "A fila e a cobrança saem sozinhas, na hora em que a vaga abre",
      "60 sessões por mês",
      "Modo Receita Saúde e pasta do contador",
      "Régua de atraso impessoal",
      "Receita por hora disponível e o que aconteceu com cada horário",
    ],
    porVir: ["Número próprio: as mensagens saindo do seu WhatsApp, sozinhas"],
  },
  {
    codigo: "pro",
    nome: "Consultório Completo",
    precoCentavos: 12900,
    precoPorProfissionalCentavos: null,
    faixa: 200,
    fairUse: true,
    canal: "plataforma",
    detalhe: "por mês",
    cta: "Criar conta e pedir o Completo",
    href: "/entrar?criar&plano=pro",
    // **A lista curta é o retrato fiel, e isso é desconfortável de propósito.**
    // Hoje o Completo é o Consultório com permissões por pessoa e sem faixa. O
    // problema comercial disso é real e a resposta dele está no `claude/25` (a
    // taxa menor do gateway, que é configuração e não código). Encher a lista
    // com promessa seria resolver o problema comercial mentindo — que é
    // exatamente como ele apareceu.
    recursos: [
      "Tudo do Consultório",
      "Sem faixa de sessões",
      "Permissões por pessoa: quem vê o quê, com aprovação em etapas",
    ],
    porVir: [
      "NFS-e para quem atende como PJ",
      "Número próprio incluso",
      "Página do paciente: confirmar, pagar e receber documento",
      "Reajuste assistido e modo férias",
    ],
  },
  {
    codigo: "clinica",
    nome: "Clínica",
    precoCentavos: 24900,
    precoPorProfissionalCentavos: 3900,
    faixa: 200,
    fairUse: true,
    canal: "plataforma",
    detalhe: "+ R$ 39 por profissional que atende",
    cta: "Conversar sobre a clínica",
    href: "/#conversa",
    recursos: [
      "Tudo do Consultório Completo",
      "Vários profissionais, com sigilo entre eles por construção",
      "Sem faixa de sessões, por profissional que atende",
    ],
    porVir: [
      "Repasse e demonstrativo por profissional",
      "Agenda de salas",
      "Fiscal consolidado da clínica",
      "Fila cruzada entre profissionais",
      "Número próprio da clínica",
    ],
  },
];

export function plano(codigo: CodigoDePlano): Plano {
  const p = PLANOS.find((x) => x.codigo === codigo);
  if (!p) throw new Error(`plano desconhecido: ${codigo}`);
  return p;
}

/**
 * O nome que ela lê, a partir do código que o sistema guarda.
 *
 * Devolve o **código** quando não conhece o plano, em vez de string vazia ou
 * "—": um plano novo no banco e ainda não aqui precisa aparecer feio, não
 * sumir. É a mesma escolha do `rotuloDaAcao` da trilha, e pelo mesmo motivo —
 * o que some é sempre o que ninguém previu.
 */
export function nomeDoPlano(codigo: string): string {
  return PLANOS.find((p) => p.codigo === codigo)?.nome ?? codigo;
}

/**
 * Quanto custa, com o número de profissionais que atendem.
 *
 * `precoCentavos` já inclui uma profissional — cinco na Clínica são
 * 24900 + 4 × 3900 = 40500, que é o R$ 405 escrito na landing. Secretaria e
 * administração não são profissionais e não entram nesta conta.
 *
 * **Isto é a conta da página, e não a conta da fatura.** A `abrir_assinatura`
 * no banco continua lendo só `preco_centavos`, de propósito: mudar a aritmética
 * de cobrança sem gateway (B16) e sem cliente é construir cedo, e cobrar errado
 * destrói confiança de um jeito que não se recupera. A verificação 22 da suíte
 * 0064 tranca isso e reprova quem mudar sem escrever por quê.
 */
export function precoDoPlano(codigo: CodigoDePlano, profissionais = 1): number {
  const p = plano(codigo);
  const n = Math.max(profissionais, 1);
  if (p.precoPorProfissionalCentavos === null) return p.precoCentavos;
  return p.precoCentavos + (n - 1) * p.precoPorProfissionalCentavos;
}

/**
 * A faixa total do plano — `null` quando não há faixa.
 *
 * Gêmeo de `faixa_da_conta` no banco: limite × profissionais ativos, com o
 * mínimo de um profissional. `null` não é "faixa infinita", é **outra espécie
 * de limite**: no Gratuito o que limita é o canal manual.
 */
export function faixaTotal(codigo: CodigoDePlano, profissionais = 1): number | null {
  const p = plano(codigo);
  if (p.faixa === null) return null;
  return p.faixa * Math.max(profissionais, 1);
}

/**
 * A escada paga desce em algum ponto?
 *
 * Devolve o degrau onde desce, ou `null` se não desce. É a função que existe
 * por causa do defeito: até a 0064, a Clínica dava 60 por profissional contra
 * 200 do Pro, e a inversão só era visível com 1, 2 ou 3 profissionais — com
 * quatro, 240 contra 200, ela parecia certa. **Defeito que depende do caso não
 * é achado por quem olha um caso.**
 *
 * O Gratuito fica de fora porque a comparação não faz sentido: `null` contra 60
 * não é descida, é outra unidade de medida.
 */
export function ondeAEscadaDesce(profissionais: number): CodigoDePlano | null {
  const pagos = PLANOS.filter((p) => p.codigo !== "gratis").sort(
    (a, b) => a.precoCentavos - b.precoCentavos,
  );
  let anterior = -1;
  for (const p of pagos) {
    const total = faixaTotal(p.codigo, profissionais) ?? 0;
    if (total < anterior) return p.codigo;
    anterior = total;
  }
  return null;
}

/**
 * O rótulo do bloco de roadmap, e ele precisa dizer três coisas de uma vez:
 * que aquilo **não existe**, que está sendo construído, e que **não está no
 * preço**. Faltando qualquer uma, a lista vira a promessa que fez a palavra
 * "sem" sair da página de privacidade.
 */
export const ROTULO_POR_VIR = "Ainda não existe, e não está no preço:";

/** Em centavos, para a tela. `formatar()` de `lib/dinheiro` cuida do resto. */
export function precoDaClinicaCom(profissionais: number): number {
  return precoDoPlano("clinica", profissionais);
}

/**
 * O preço de tabela do jeito que o cartão mostra: **sem centavos**.
 *
 * Os quatro preços são reais inteiros, e "R$ 69,00" no cartão de uma landing
 * lê como preço de gôndola. Mas o corte é declarado em vez de assumido: se
 * algum plano ganhar centavos um dia, esta função mostra os centavos em vez de
 * escondê-los — arredondar em silêncio seria a página dizendo um número e a
 * fatura cobrando outro, que é a família de defeito que a 0064 existe para
 * fechar.
 */
export function precoDeTabela(p: Plano): string {
  const reais = Math.floor(p.precoCentavos / 100);
  const centavos = p.precoCentavos % 100;
  if (centavos === 0) return `R$ ${reais.toLocaleString("pt-BR")}`;
  return `R$ ${reais.toLocaleString("pt-BR")},${String(centavos).padStart(2, "0")}`;
}
