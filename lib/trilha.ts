/**
 * A trilha de acesso, e a cópia legível do registro — do lado do app (B33).
 *
 * Duas metades de uma coisa só: **registro que ninguém lê é registro que só
 * serve depois do problema.**
 *
 * A `trilha_acesso` é gravada, carimbada pelo servidor e append-only desde a
 * B13, e a página `/seguranca` promete essas três propriedades em voz alta. O
 * que faltava era a psicóloga poder ler a própria — e isso deixou de ser
 * argumento de documento em 02/09, quando a migração 0060 apagou sem querer o
 * `insert` que grava `exportou_conta` e **a exportação da conta ficou três horas
 * sem deixar rastro**. Ninguém teria notado se uma suíte não olhasse.
 *
 * A segunda metade é o direito de acesso do paciente: a exportação da ficha
 * saía em JSON, e o direito da Res. CFP 001/2009 não se exerce com um arquivo
 * que a pessoa não sabe abrir.
 */

// ────────────────────────────────────────────────────────────── a trilha

export type LinhaDaTrilha = {
  em: string;
  acao: string;
  quem: string;
  saiu: boolean;
  paciente: string | null;
  detalhe: Record<string, unknown>;
};

/**
 * As doze ações, em português, na voz de quem fez.
 *
 * Cada rótulo é uma frase no passado com sujeito implícito — "abriu a ficha", e
 * não "leitura de ficha". A trilha é lida no dia em que alguém pergunta *quem
 * fez o quê*, e substantivo abstrato é o jeito mais rápido de uma linha de
 * auditoria não responder essa pergunta.
 */
export const ACOES: Record<string, string> = {
  leu_ficha: "abriu a ficha",
  editou_ficha: "editou o cadastro",
  exportou_paciente: "exportou o registro",
  exportou_conta: "exportou a conta inteira",
  esqueceu_contato: "apagou o contato",
  arquivou: "arquivou o paciente",
  contrato_enviado: "enviou o contrato",
  contrato_aceito: "registrou o aceite do contrato",
  contrato_revogado: "revogou o contrato",
  anotou_ausencia: "anotou uma ausência",
  editou_registro: "escreveu no registro",
  escreveu_evolucao: "escreveu uma evolução",
};

/**
 * Uma ação que a tela não conhece **aparece assim mesmo**.
 *
 * O modo de falha ruim aqui seria a linha sumir: uma trilha que esconde o que a
 * tela não sabe nomear é pior do que uma trilha feia, porque o que some é
 * exatamente o evento novo — o que ninguém previu, que é o que se procura
 * quando se procura alguma coisa.
 */
export function rotuloDaAcao(acao: string): string {
  return ACOES[acao] ?? acao.replace(/_/g, " ");
}

/**
 * As ações que tocam conteúdo clínico.
 *
 * Serve para a tela dar peso visual, e não para filtrar: `minha_trilha` não tem
 * filtro por ação de propósito — tela de auditoria com filtro por tipo de evento
 * é tela onde o evento inconveniente é o que ninguém marca.
 */
export const ACOES_CLINICAS = [
  "leu_ficha",
  "exportou_paciente",
  "editou_registro",
  "escreveu_evolucao",
] as const;

export function ehClinica(acao: string): boolean {
  return (ACOES_CLINICAS as readonly string[]).includes(acao);
}

/** A linha inteira, em uma frase. */
export function fraseDaLinha(l: LinhaDaTrilha): string {
  const alvo = l.paciente ? ` — ${l.paciente}` : "";
  return `${l.quem} ${rotuloDaAcao(l.acao)}${alvo}`;
}

export type TamanhoDaTrilha = { linhas: number; primeira: string | null };

/**
 * O tamanho, dito antes de alguém perguntar.
 *
 * Uma tela que mostra as últimas cinquenta linhas sem dizer que há dezoito mil
 * parece uma tela que esconde — e a trilha é justamente a peça do produto que
 * não pode parecer isso.
 */
export function fraseDoTamanho(t: TamanhoDaTrilha): string {
  if (t.linhas === 0) {
    return "A trilha está vazia. Ela grava sozinha a partir do primeiro acesso a uma ficha.";
  }
  const desde = t.primeira
    ? new Date(t.primeira).toLocaleDateString("pt-BR", { timeZone: "America/Sao_Paulo" })
    : null;
  const n = t.linhas === 1 ? "1 registro" : `${t.linhas.toLocaleString("pt-BR")} registros`;
  return desde ? `${n} desde ${desde}.` : `${n}.`;
}

/**
 * O que a tela diz sobre a própria trilha, e é a frase que a torna defesa.
 *
 * Ela precisa estar na tela e não só na política, porque é lá que a psicóloga
 * vai estar no dia em que precisar dela.
 */
export function fraseDaImutabilidade(): string {
  return "Esta lista não pode ser editada nem apagada — nem por você. É isso que a torna uma defesa: se alguém alegar acesso indevido, o registro que responde não é editável por quem está sendo acusado.";
}

// ──────────────────────────────────────────── a cópia legível do registro

/**
 * As seções da cópia do paciente, na ordem em que ele lê.
 *
 * A ordem é do leitor e não do banco: quem recebe a cópia quer saber **quem
 * ele é aqui, o que foi combinado, o que aconteceu, e o que foi escrito** — e é
 * nessa ordem que a pergunta chega.
 *
 * `chave` casa com a saída de `exportar_paciente`. Uma seção que a função
 * deixar de devolver simplesmente não aparece; uma que ela passar a devolver e
 * não estiver aqui **aparece no fim, sem rótulo bonito** — porque sumir seria
 * pior. É a mesma escolha de `rotuloDaAcao`.
 */
export const SECOES: { chave: string; titulo: string; nota?: string }[] = [
  { chave: "paciente", titulo: "Quem você é neste registro" },
  { chave: "enquadres", titulo: "O combinado", nota: "Valor, duração e frequência acertados, e desde quando." },
  { chave: "sessoes", titulo: "Os encontros" },
  { chave: "cobrancas", titulo: "Os valores" },
  { chave: "registro", titulo: "O registro clínico" },
  { chave: "anamnese", titulo: "A anamnese" },
  { chave: "anamnese_adendos", titulo: "Acréscimos à anamnese" },
  { chave: "evolucoes", titulo: "As evoluções" },
];

/** As chaves da saída que não são seção — cabeçalho e rodapé do documento. */
export const FORA_DAS_SECOES = [
  "gerado_em",
  "aviso",
  "nota_sobre_o_que_nao_esta_aqui",
] as const;

/**
 * A marca do documento.
 *
 * Vem da própria função no banco (`exportar_paciente` devolve em `aviso`), e a
 * tela não a inventa: a mesma frase precisa estar no JSON e no papel, senão são
 * dois documentos diferentes com o mesmo nome.
 */
export const MARCA_PADRAO = "Cópia de documento sigiloso. Res. CFP 001/2009.";

/**
 * O que **não** está na cópia, dito na cópia.
 *
 * O Registro Documental (art. 1º da Res. CFP 001/2009) — testes, protocolos,
 * material de acesso exclusivo da psicóloga — não integra o que o paciente
 * recebe. Dizer isso no próprio documento é o que impede a cópia de parecer
 * completa quando não é, e é a diferença entre uma omissão e uma fronteira.
 *
 * A frase vem do banco quando existe; esta é a rede.
 */
export const AUSENCIA_PADRAO =
  "O Registro Documental (art. 1º, Res. CFP 001/2009) — testes, protocolos e material de acesso exclusivo da psicóloga — não integra esta cópia.";

/**
 * Rótulos de campo. Sem entrada, o nome cru vira legível em vez de sumir.
 */
const CAMPOS: Record<string, string> = {
  nome: "Nome",
  telefone: "Telefone",
  email: "E-mail",
  nascimento: "Nascimento",
  documento: "Documento",
  cpf: "CPF",
  estado: "Situação",
  criado_em: "Cadastrado em",
  inicio: "Início",
  fim: "Fim",
  valor: "Valor",
  valor_reconhecido: "Valor reconhecido",
  duracao_min: "Duração (min)",
  frequencia: "Frequência",
  vigencia_de: "Vigente desde",
  vigencia_ate: "Vigente até",
  pago_em: "Pago em",
  vencimento: "Vencimento",
  texto: "Texto",
  conteudo: "Conteúdo",
  camada: "Camada",
  observacao: "Observação",
};

export function rotuloDoCampo(chave: string): string {
  if (CAMPOS[chave]) return CAMPOS[chave];
  const limpo = chave.replace(/_/g, " ");
  return limpo.charAt(0).toUpperCase() + limpo.slice(1);
}

/**
 * Campos que nunca vão para o papel.
 *
 * Ids não dizem nada a quem lê e enchem a página; `conta_id` e
 * `profissional_id` já saem no banco. **`token` está aqui pela lição da 0059c**:
 * um link mágico num arquivo que a pessoa guarda no computador é a mesma família
 * de erro três vezes seguida.
 */
export const CAMPOS_OCULTOS = ["id", "conta_id", "profissional_id", "paciente_id", "token", "chave_idem"];

export function ehOculto(chave: string): boolean {
  return CAMPOS_OCULTOS.includes(chave) || chave.endsWith("_id");
}
