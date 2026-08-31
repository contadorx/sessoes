/**
 * Regras puras do cadastro de paciente. Minimização de dados é postura
 * (doc 07): só o necessário para agendar, avisar e emitir recibo.
 */

export const ESTADOS = [
  "interessado",
  "triagem",
  "em_atendimento",
  "pausa",
  "alta",
  "encerrado",
  "arquivado",
] as const;

export type Estado = (typeof ESTADOS)[number];

export const ROTULO_ESTADO: Record<Estado, string> = {
  interessado: "interessado",
  triagem: "em triagem",
  em_atendimento: "em atendimento",
  pausa: "em pausa",
  alta: "alta",
  encerrado: "encerrado",
  arquivado: "arquivado",
};

export const CANAIS = ["whatsapp", "sms", "email", "nao_avisar"] as const;
export type Canal = (typeof CANAIS)[number];

export const ROTULO_CANAL: Record<Canal, string> = {
  whatsapp: "WhatsApp",
  sms: "SMS",
  email: "só e-mail",
  nao_avisar: "não avisar",
};

/**
 * Guarda só dígitos, com DDI. Quem digita "(11) 98765-4321" quer dizer
 * +55 11 98765-4321 — normalizar aqui evita duplicata e mensagem não entregue.
 */
export function normalizarTelefone(bruto: string): string | null {
  const digitos = bruto.replace(/\D/g, "");
  if (digitos === "") return null;

  // 10 ou 11 dígitos = número nacional sem DDI.
  if (digitos.length === 10 || digitos.length === 11) return `55${digitos}`;
  if (digitos.length === 12 || digitos.length === 13) return digitos;

  throw new Error("Telefone com quantidade de dígitos fora do esperado.");
}

/** "+55 11 98765-4321" para a tela. */
export function formatarTelefone(guardado: string | null): string {
  if (!guardado) return "—";
  const m = /^55(\d{2})(\d{4,5})(\d{4})$/.exec(guardado);
  return m ? `(${m[1]}) ${m[2]}-${m[3]}` : guardado;
}

/**
 * CPF com dígito verificador — vai ser exigido no recibo do Receita Saúde
 * (F2a), então é melhor recusar errado no cadastro do que na hora do recibo.
 */
export function cpfValido(bruto: string): boolean {
  const d = bruto.replace(/\D/g, "");
  if (d.length !== 11 || /^(\d)\1{10}$/.test(d)) return false;

  const digito = (ate: number) => {
    let soma = 0;
    for (let i = 0; i < ate; i++) soma += Number(d[i]) * (ate + 1 - i);
    const resto = (soma * 10) % 11;
    return resto === 10 ? 0 : resto;
  };

  return digito(9) === Number(d[9]) && digito(10) === Number(d[10]);
}

export type EntradaPaciente = {
  nome: string;
  telefone: string;
  email: string;
  cpf: string;
  estado: string;
  msg_canal: string;
  msg_modo: string;
  observacao: string;
};

export type Validado = {
  nome: string;
  telefone: string | null;
  email: string | null;
  cpf: string | null;
  estado: Estado;
  msg_canal: Canal;
  msg_modo: "discreto" | "completo";
  observacao: string | null;
};

/** Devolve os dados prontos para o banco, ou a lista de problemas. */
export function validarPaciente(
  e: Partial<EntradaPaciente>,
): { ok: true; dados: Validado } | { ok: false; erros: string[] } {
  const erros: string[] = [];

  const nome = (e.nome ?? "").trim();
  if (nome.length < 2) erros.push("O nome precisa de ao menos duas letras.");
  if (nome.length > 120) erros.push("O nome está longo demais.");

  let telefone: string | null = null;
  try {
    telefone = normalizarTelefone(e.telefone ?? "");
  } catch {
    erros.push("Telefone inválido — confira o DDD e os dígitos.");
  }

  const emailBruto = (e.email ?? "").trim().toLowerCase();
  const email = emailBruto === "" ? null : emailBruto;
  if (email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    erros.push("E-mail inválido.");
  }

  const cpfBruto = (e.cpf ?? "").replace(/\D/g, "");
  const cpf = cpfBruto === "" ? null : cpfBruto;
  if (cpf && !cpfValido(cpf)) erros.push("CPF inválido.");

  const estado = (e.estado ?? "interessado") as Estado;
  if (!ESTADOS.includes(estado)) erros.push("Estado desconhecido.");

  const canal = (e.msg_canal ?? "whatsapp") as Canal;
  if (!CANAIS.includes(canal)) erros.push("Canal de mensagem desconhecido.");

  const modo = (e.msg_modo ?? "discreto") as "discreto" | "completo";
  if (modo !== "discreto" && modo !== "completo") erros.push("Modo de mensagem desconhecido.");

  // Quem vai receber mensagem precisa ter por onde receber.
  if (canal === "whatsapp" && !telefone) erros.push("Para avisar por WhatsApp, informe o telefone.");
  if (canal === "sms" && !telefone) erros.push("Para avisar por SMS, informe o telefone.");
  if (canal === "email" && !email) erros.push("Para avisar por e-mail, informe o e-mail.");

  const observacao = (e.observacao ?? "").trim() || null;
  if (observacao && observacao.length > 2000) erros.push("A anotação está longa demais.");

  if (erros.length > 0) return { ok: false, erros };

  return {
    ok: true,
    dados: { nome, telefone, email, cpf, estado, msg_canal: canal, msg_modo: modo, observacao },
  };
}
