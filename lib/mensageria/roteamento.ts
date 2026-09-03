/**
 * Por onde a mensagem sai — o lado puro.
 *
 * O EIXO QUE FALTAVA
 *
 * `templates.essencial` responde *"quem se machuca se não for?"* e governa teto
 * de plano. Roteamento precisa de outra pergunta: ***"quanto valor a mensagem
 * perde com atraso?"*** — e é a `classe`.
 *
 *   urgente    perde valor em minutos. Fura a fila e tem cascata automática.
 *   rotina     tolera horas. Pode cair na mão dela sem prejuízo.
 *   documento  recibo, informe, declaração. **Nunca por canal não oficial.**
 *
 * **Cuidado para não ler errado:** `documento` é o *arquivo*, não o *valor*. Uma
 * cobrança que diz "seu pagamento combinado: R$ 200" **pode** ir por WhatsApp —
 * valor não é dado de saúde, e a mensagem discreta não nomeia terapia. O que
 * não vai é o recibo, que nomeia o serviço e existe para reembolso e Receita
 * Saúde. **Valor pode; documento não.**
 *
 * O SMS É MEDIDA DE CRISE, E NÃO SE OFERECE
 *
 * Decisão de 03/09: o canal existe, é construído e testado, e **não aparece em
 * tela nenhuma**. Ele não é opção de cadastro, não é escolha da paciente na
 * pré-ficha e não é recurso de plano.
 *
 * A razão é `precos_canal`, que está no banco desde sempre: em milésimos de
 * centavo, e-mail **200**, WhatsApp **4.500**, SMS **8.000**. O SMS custa
 * **quarenta vezes** o e-mail e chega ao mesmo lugar em quase todo caso.
 *
 * **Em que degrau ele entra é configuração, não código** (B57). A cascata mora
 * em `rota_do_canal`, e a pergunta "vale gastar quarenta vezes mais para não
 * perder esta oferta?" é decisão de risco contra dinheiro — dela, não do
 * arquivo. O que **não** é configurável está logo abaixo, em `ordemDeTentativa`:
 * documento nunca por canal não oficial, e a mão dela sempre por último.
 */

export type Classe = "urgente" | "rotina" | "documento";
export type Canal = "whatsapp" | "sms" | "email";

/** O que sobra quando não há canal: a mensagem espera o dedo dela. */
export const NA_MAO = "na_sua_mao" as const;

export type Tentativa = Canal | typeof NA_MAO;

export type Situacao = {
  /** O canal que a paciente escolheu no cadastro. */
  preferido: Canal;
  classe: Classe;
  /** Quais adaptadores têm provedor configurado agora. */
  disponiveis: readonly Canal[];
  /**
   * A cascata configurada para esta classe, em ordem — `rota_do_canal` no banco.
   *
   * **Ela é configuração, e não código, porque é decisão de produto em aberto.**
   * O SMS na cascata de urgente custa quarenta vezes o e-mail e chega ao mesmo
   * lugar em quase todo caso; tirar ou pôr esse degrau é uma escolha de risco
   * contra dinheiro, e quem a faz não deveria precisar de um commit.
   *
   * Vazia ou ausente, vale a rota mínima: o canal da paciente e mais nada. O
   * padrão sem configuração **não inventa degrau caro**.
   */
  rota?: readonly Canal[];
  /** Canais com o disjuntor aberto — configurados, mas sem confiança agora. */
  interrompidos?: readonly Canal[];
  /** A paciente tem telefone? Sem ele não há WhatsApp nem SMS. */
  temTelefone?: boolean;
  /** E e-mail? Sem ele não há e-mail nem cascata para e-mail. */
  temEmail?: boolean;
};

/**
 * A ordem das tentativas, da primeira ao último degrau.
 *
 * **O painel manual é sempre o fim, e nunca o segundo.** Ele depende de humano
 * acordado: pôr a mão dela no meio da cascata é trocar uma entrega automática
 * que ainda tinha caminho por uma tarefa que ela pode não ver hoje.
 *
 * A lista sai **sem repetição e sem canal impossível** — sem telefone não se
 * tenta WhatsApp nem SMS, sem e-mail não se tenta e-mail. Um canal sem destino
 * não é um degrau: é um erro adiado.
 */
export function ordemDeTentativa(s: Situacao): Tentativa[] {
  const temTelefone = s.temTelefone ?? true;
  const temEmail = s.temEmail ?? true;
  const interrompidos = new Set(s.interrompidos ?? []);

  const possivel = (c: Canal): boolean => {
    if (!s.disponiveis.includes(c)) return false;
    if (interrompidos.has(c)) return false;
    if ((c === "whatsapp" || c === "sms") && !temTelefone) return false;
    if (c === "email" && !temEmail) return false;
    return true;
  };

  // Documento não escolhe: ou sai por e-mail, ou espera a mão dela. Não há
  // cascata para canal não oficial, e não há "quase" — é a fronteira 8 escrita
  // em código, e não num comentário de tela.
  if (s.classe === "documento") {
    return possivel("email") ? ["email", NA_MAO] : [NA_MAO];
  }

  const ordem: Tentativa[] = [];
  const juntar = (c: Canal) => {
    if (possivel(c) && !ordem.includes(c)) ordem.push(c);
  };

  /*
    **O canal da paciente vem primeiro, sempre.** Ele é escolha dela, e a rota
    configurada é o que fazer quando esse caminho não deu — não uma preferência
    nossa que atropela a dela.
  */
  juntar(s.preferido);
  for (const degrau of s.rota ?? []) juntar(degrau);

  ordem.push(NA_MAO);
  return ordem;
}

/**
 * A ordem da fila de saída.
 *
 * Uma oferta expira em quarenta minutos. FIFO com duzentos lembretes na frente
 * mata a métrica-norte do produto sem nenhum erro aparecer em lugar nenhum — a
 * fila estaria "funcionando", e a vaga fecharia vazia.
 */
export function pesoDaClasse(classe: Classe): number {
  return classe === "urgente" ? 0 : classe === "rotina" ? 1 : 2;
}

/**
 * Quanto tempo a mensagem tolera esperar, em minutos.
 *
 * Serve à decisão do passo 3 da regra de saída: uma **urgente** cuja vaga expira
 * antes do fim da janela de silêncio não espera pelas 8h — a janela existe para
 * não acordar paciente de madrugada, e uma vaga que fecha vazia não acorda
 * ninguém, só custa a hora dela.
 */
export function furaJanelaDeSilencio(
  classe: Classe,
  toleraAtrasoMin: number | null,
  minutosAteOFimDoSilencio: number,
): boolean {
  if (classe !== "urgente") return false;
  if (toleraAtrasoMin === null || toleraAtrasoMin <= 0) return false;
  return toleraAtrasoMin < minutosAteOFimDoSilencio;
}

// ============================================ o que a cascata custa, em dinheiro

/**
 * O preço de cada canal, em **milésimos de centavo por mensagem**.
 *
 * A unidade é do banco (`precos_canal.centavos_milesimos`) e não é capricho:
 * um e-mail custa R$ 0,002, que em centavos inteiros seria zero. Arredondar
 * aqui apagaria justamente a diferença que a tabela existe para mostrar.
 */
export type Preco = { canal: Canal; centavosMilesimos: number };

/**
 * Quanto a cascata custa, no pior caso, para uma mensagem desta classe.
 *
 * **Pior caso, e não média**, porque é o número que decide: a cascata só desce
 * o degrau seguinte quando o anterior não deu, então o custo real fica entre o
 * primeiro degrau e este — e o que se compara ao escolher a rota é o teto.
 *
 * Este número não bloqueia nada. Ele existe para a rota ser escolhida com o
 * preço à vista, em vez de escolhida no escuro e descoberta na fatura.
 */
export function custoDaRota(rota: readonly Canal[], precos: readonly Preco[]): number {
  const porCanal = new Map(precos.map((p) => [p.canal, p.centavosMilesimos]));
  return rota.reduce((total, canal) => total + (porCanal.get(canal) ?? 0), 0);
}

/** "R$ 0,045" a partir de milésimos de centavo. Três casas, que é o que a unidade tem. */
export function precoEmReais(centavosMilesimos: number): string {
  return (centavosMilesimos / 100_000).toLocaleString("pt-BR", {
    style: "currency",
    currency: "BRL",
    minimumFractionDigits: 3,
    maximumFractionDigits: 3,
  });
}

/**
 * A frase do custo da cascata, para o painel do operador.
 *
 * Ela nomeia o degrau mais caro, e é de propósito: numa rota de três canais o
 * total esconde que **um** deles responde por quase tudo. Foi o que a leitura
 * de `precos_canal` mostrou — o SMS custa quarenta vezes o e-mail.
 */
export function fraseDoCusto(rota: readonly Canal[], precos: readonly Preco[]): string {
  if (rota.length === 0) return "Sem degrau nenhum configurado.";

  const porCanal = new Map(precos.map((p) => [p.canal, p.centavosMilesimos]));
  const total = custoDaRota(rota, precos);

  const caro = [...rota].sort(
    (a, b) => (porCanal.get(b) ?? 0) - (porCanal.get(a) ?? 0),
  )[0];
  const doCaro = porCanal.get(caro) ?? 0;

  const parte = total > 0 ? Math.round((doCaro / total) * 100) : 0;

  return (
    `${precoEmReais(total)} por mensagem no pior caso — quando todos os degraus falham. ` +
    (doCaro > 0
      ? `O ${caro} responde por ${parte}% disso.`
      : "Nenhum degrau tem preço declarado em precos_canal.")
  );
}
