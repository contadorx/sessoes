/**
 * Quem pode o quê — do lado do app.
 *
 * Gêmeo de `le_clinico()` e `ve_financeiro()` no banco (migração 0049), com os
 * mesmos valores esperados da suíte 0049. E é **só** gêmeo: quem decide de
 * verdade é a RLS. Se este arquivo e o banco discordarem, o banco ganha, e o
 * sintoma é uma tela vazia — não um vazamento.
 *
 * A regra que ele carrega, e que vale mais que a tabela:
 *
 *     **acesso clínico não vem junto com o cargo administrativo.**
 *
 * Quem marca a agenda não precisa ler a sessão. Quem confere o Pix não precisa
 * saber a demanda. Uma auditoria externa olhou o menu de doze itens e escreveu
 * a frase que fechou o assunto — *"a secretária vê as mesmas doze abas,
 * inclusive as que ela não deveria usar"* —, e o buraco não era de menu: era
 * de RLS, onde a única pergunta era "é da mesma conta?".
 *
 * Por que esconder o item de menu não basta, e este módulo existe assim
 * mesmo: esconder resolve o acidente (ela clica sem querer e lê o que não
 * devia), não a intenção. Quem quiser passar por cima digita a URL, ou chama
 * o PostgREST direto. O menu aqui existe para a tela não oferecer o que a
 * pessoa não pode fazer — oferecer e depois recusar é pior do que não
 * oferecer.
 */

/**
 * Os quatro cargos. `operador` não está aqui de propósito: opera a plataforma
 * (eu), não é papel dentro da conta de ninguém, e mora numa coluna à parte.
 */
export type Papel = "dona" | "profissional" | "administradora" | "secretaria";

export const ROTULO_PAPEL: Record<Papel, string> = {
  dona: "responsável pela conta",
  profissional: "psicóloga",
  administradora: "administração",
  secretaria: "secretaria",
};

/**
 * O que cada cargo recebe quando ninguém decidiu nada.
 *
 * O padrão é ponto de partida, não hierarquia: uma concessão explícita na
 * coluna vence em qualquer direção. É a dona que concede — e nem ela em si
 * mesma, porque permissão que o sujeito se dá não é permissão.
 */
export const PADRAO: Record<Papel, { clinico: boolean; financeiro: boolean }> = {
  dona: { clinico: true, financeiro: true },
  // Atende, e o dinheiro é da clínica.
  profissional: { clinico: true, financeiro: false },
  // O espelho: cuida da operação e do caixa, e não entra na sala.
  administradora: { clinico: false, financeiro: true },
  secretaria: { clinico: false, financeiro: false },
};

export type Acessos = {
  papel: Papel;
  /** `null` = não foi decidido; usa o padrão do papel. */
  acessoClinico: boolean | null;
  acessoFinanceiro: boolean | null;
};

export function podeClinico(a: Acessos): boolean {
  return a.acessoClinico ?? PADRAO[a.papel]?.clinico ?? false;
}

export function podeFinanceiro(a: Acessos): boolean {
  return a.acessoFinanceiro ?? PADRAO[a.papel]?.financeiro ?? false;
}

/**
 * Só a dona concede, e nunca a si mesma.
 *
 * A tela pergunta isto antes de mostrar o controle. O banco pergunta de novo
 * num gatilho, que é onde a resposta importa — esta função existe para o
 * botão não aparecer e depois falhar.
 */
export function podeConceder(quem: Acessos, aQuem: { eu: boolean }): boolean {
  return quem.papel === "dona" && !aQuem.eu;
}

/**
 * A frase que explica a concessão sem transformá-la em desconfiança.
 *
 * "A secretária não pode ver prontuário" descreve uma suspeita. "Acesso
 * clínico é uma decisão separada do cargo" descreve uma regra — e é a regra
 * que a psicóloga vai ter que explicar para a pessoa que trabalha com ela.
 */
export function fraseDoAcesso(a: Acessos): string {
  const c = podeClinico(a);
  const f = podeFinanceiro(a);
  if (c && f) return "Vê o prontuário e o financeiro.";
  if (c) return "Vê o prontuário. Não vê cobrança nem recebimento.";
  if (f) return "Vê o financeiro. Não vê prontuário, evolução nem anamnese.";
  return "Vê a agenda, os encaixes e o cadastro. Não vê prontuário nem financeiro.";
}
