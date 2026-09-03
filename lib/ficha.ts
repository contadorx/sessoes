import { cpfValido, normalizarTelefone, CANAIS, type Canal } from "@/lib/paciente";

/**
 * A pré-ficha administrativa (PR4).
 *
 * O que a paciente preenche antes da primeira sessão, no link que ela já tem.
 * **Só o que é administrativo** — e essa frase é a build inteira.
 *
 * ---
 *
 * **A fronteira 6, e por que ela mora aqui em vez de num comentário.**
 *
 * "Pergunta clínica não vai por formulário ao paciente." Cinco dos oito
 * concorrentes atravessaram essa linha, e a armadilha do arquivo da build diz
 * como: *aproveitar o formulário para "já ir adiantando" a anamnese, e ele
 * começa com um campo só*. O campo parece inofensivo — "o que te traz aqui?",
 * "já fez terapia antes?" — e quem o acrescenta tem uma boa razão: ela ia
 * perguntar isso na sessão mesmo.
 *
 * A diferença é o **contexto da resposta**. Na sala há alguém escutando, e o
 * que a pessoa diz pode ser acolhido, contextualizado, corrigido. Num
 * formulário há uma caixa de texto, e o que sai dali é dado clínico escrito por
 * quem não sabe que está escrevendo prontuário, num celular que outra pessoa
 * pode estar olhando, sem ninguém do outro lado.
 *
 * Então a lista de campos é **fechada** (`CAMPOS`), e é ela que a varredura de
 * `testes/nenhuma-pergunta-clinica.test.ts` confere contra o vocabulário
 * clínico. O banco fecha a mesma porta do lado de lá: `salvar_ficha` recusa
 * qualquer chave fora desta lista, então uma tela futura não consegue
 * contrabandear campo nem por engano.
 *
 * Duas travas para a mesma regra é de propósito. Uma tela nova nasce sem
 * passar por aqui; o banco, não.
 */

/** Os campos da pré-ficha. Fechada — acrescentar aqui é decisão, não detalhe. */
export const CAMPOS = [
  "nome",
  "nascimento",
  "cpf",
  "telefone",
  "email",
  "msg_canal",
  "msg_modo",
  "responsaveis",
] as const;

export type Campo = (typeof CAMPOS)[number];

/**
 * O vocabulário que não entra — nem como nome de campo, nem como rótulo.
 *
 * Não é filtro de conteúdo: é a lista contra a qual a varredura roda. Uma
 * pergunta clínica disfarçada de administrativa ("como você tem dormido?")
 * escapa daqui, e por isso a verificação de verdade continua sendo a lista
 * fechada acima — esta pega o caso comum, que é o campo com o nome na cara.
 */
export const VOCABULARIO_CLINICO = [
  "sintoma",
  "queixa",
  "diagnóstic",
  "diagnostic",
  "medicament",
  "remédio",
  "remedio",
  "terapia",
  "tratamento",
  "psiquiatr",
  "humor",
  "ansiedade",
  "depress",
  "sono",
  "álcool",
  "alcool",
  "droga",
  "risco",
  "suicíd",
  "suicid",
  "autolesã",
  "internaç",
  "histórico de saúde",
  "historico de saude",
  "o que te traz",
  "motivo da procura",
  "encaminhad",
  "escala",
  "triagem",
  "anamnese",
  "consentimento",
] as const;

export type EntradaFicha = {
  nome?: string;
  nascimento?: string;
  cpf?: string;
  telefone?: string;
  email?: string;
  msg_canal?: string;
  msg_modo?: string;
  responsavel_nome?: string;
  responsavel_documento?: string;
  responsavel_telefone?: string;
};

export type FichaValidada = {
  nome: string;
  nascimento: string;
  cpf: string | null;
  telefone: string | null;
  email: string | null;
  msg_canal: Canal;
  msg_modo: "discreto" | "completo";
  responsaveis: { nome: string; documento: string | null; telefone: string | null }[];
};

/** Quantos anos alguém nascido em `nascimento` tem em `hoje`. */
export function idadeEm(nascimento: string, hoje: string): number | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(nascimento) || !/^\d{4}-\d{2}-\d{2}$/.test(hoje)) {
    return null;
  }
  const [an, mn, dn] = nascimento.split("-").map(Number);
  const [ah, mh, dh] = hoje.split("-").map(Number);
  let anos = ah - an;
  if (mh < mn || (mh === mn && dh < dn)) anos -= 1;
  return anos;
}

export function ehMenor(nascimento: string, hoje: string): boolean {
  const anos = idadeEm(nascimento, hoje);
  return anos !== null && anos < 18;
}

/**
 * Valida o que a paciente mandou.
 *
 * Mais exigente que `validarPaciente` em dois pontos, e os dois têm razão de
 * ser: **nascimento é obrigatório** (sem ele não dá para saber se há
 * responsável a pedir) e **responsável é obrigatório para menor de 18** — é o
 * critério de pronto da build, e é o que o cadastro de responsáveis da B13
 * espera receber.
 *
 * O CPF continua **opcional**. Ele é o campo que trava a linha na importação do
 * Carnê-Leão, e é tentador exigi-lo aqui — mas quem não tem o número à mão no
 * momento em que abre o link ficaria sem conseguir mandar o resto, e o resto é
 * o que faz a primeira sessão acontecer. O formulário diz para que serve e
 * segue sem ele.
 */
export function validarFicha(
  e: EntradaFicha,
  hoje: string,
):
  | { ok: true; dados: FichaValidada }
  | { ok: false; erros: string[]; porCampo: Record<string, string> } {
  const erros: string[] = [];
  const porCampo: Record<string, string> = {};
  const problema = (campo: string | null, frase: string) => {
    erros.push(frase);
    if (campo && !porCampo[campo]) porCampo[campo] = frase;
  };

  const nome = (e.nome ?? "").trim();
  if (nome.length < 2) problema("nome", "Escreva o seu nome completo.");
  if (nome.length > 120) problema("nome", "O nome está longo demais.");

  const nascimento = (e.nascimento ?? "").trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(nascimento)) {
    problema("nascimento", "Informe a sua data de nascimento.");
  } else {
    const anos = idadeEm(nascimento, hoje);
    if (anos === null || anos < 0) problema("nascimento", "Essa data está no futuro.");
    else if (anos > 120) problema("nascimento", "Confira o ano de nascimento.");
  }

  let telefone: string | null = null;
  try {
    telefone = normalizarTelefone(e.telefone ?? "");
  } catch {
    problema("telefone", "Telefone inválido — confira o DDD e os dígitos.");
  }

  const emailBruto = (e.email ?? "").trim().toLowerCase();
  const email = emailBruto === "" ? null : emailBruto;
  if (email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) problema("email", "E-mail inválido.");

  const cpfBruto = (e.cpf ?? "").replace(/\D/g, "");
  const cpf = cpfBruto === "" ? null : cpfBruto;
  if (cpf && !cpfValido(cpf)) problema("cpf", "Confira o CPF — algum dígito não bate.");

  const canal = (e.msg_canal ?? "whatsapp") as Canal;
  if (!CANAIS.includes(canal)) problema("msg_canal", "Escolha como prefere ser avisada.");
  if ((canal === "whatsapp" || canal === "sms") && !telefone) {
    problema("telefone", "Para ser avisada por aí, informe o telefone.");
  }
  if (canal === "email" && !email) problema("email", "Para ser avisada por e-mail, informe o e-mail.");

  const modo = (e.msg_modo ?? "discreto") as "discreto" | "completo";
  if (modo !== "discreto" && modo !== "completo") problema("msg_modo", "Opção desconhecida.");

  // O responsável, e ele é obrigatório para menor de 18.
  const rNome = (e.responsavel_nome ?? "").trim();
  const rDoc = (e.responsavel_documento ?? "").replace(/\D/g, "");
  let rTel: string | null = null;
  try {
    rTel = normalizarTelefone(e.responsavel_telefone ?? "");
  } catch {
    problema("responsavel_telefone", "Telefone do responsável inválido.");
  }

  const menor = /^\d{4}-\d{2}-\d{2}$/.test(nascimento) && ehMenor(nascimento, hoje);
  if (menor && rNome.length < 2) {
    problema("responsavel_nome", "Para menor de 18 anos, informe quem é o responsável.");
  }
  if (rDoc && !cpfValido(rDoc)) {
    problema("responsavel_documento", "Confira o CPF do responsável.");
  }

  const responsaveis =
    rNome.length >= 2
      ? [{ nome: rNome, documento: rDoc === "" ? null : rDoc, telefone: rTel }]
      : [];

  if (erros.length > 0) return { ok: false, erros, porCampo };

  return {
    ok: true,
    dados: { nome, nascimento, cpf, telefone, email, msg_canal: canal, msg_modo: modo, responsaveis },
  };
}
