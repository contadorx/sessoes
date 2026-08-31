/**
 * A lei nº 4 (doc 05): dinheiro em `numeric`, nunca float — e **sinal é contrato**.
 *
 * O importador do FinanceiroX destruía o sinal com `Math.abs` e levou uma
 * auditoria inteira para ser encontrado. Aqui nenhuma função desta biblioteca
 * chama `Math.abs`, e há teste provando que o sinal atravessa.
 *
 * Convenção interna: **centavos como inteiro**. O banco guarda `numeric(12,2)`;
 * `supabase-js` devolve numeric como *string* (justamente para não passar por
 * float), e é assim que ela entra e sai daqui.
 */

/** Converte o que vem do banco (string de numeric) ou um número para centavos inteiros. */
export function paraCentavos(valor: string | number): number {
  if (typeof valor === "number") {
    if (!Number.isFinite(valor)) {
      throw new Error(`Valor monetário inválido: ${valor}`);
    }
    // Só para valores que já nasceram numéricos no código. O caminho normal é string.
    return Math.round(valor * 100);
  }

  const limpo = valor.trim().replace(/\s|R\$/g, "");
  if (limpo === "") throw new Error("Valor monetário vazio");

  const negativo = limpo.startsWith("-");
  const semSinal = limpo.replace(/^[+-]/, "");

  // Aceita "200", "200.5", "200.50" e "200,50" — não aceita separador de milhar
  // ambíguo, porque o que vem do banco nunca tem.
  if (!/^\d+([.,]\d{1,2})?$/.test(semSinal)) {
    throw new Error(`Valor monetário inválido: ${valor}`);
  }

  const [inteira, decimal = ""] = semSinal.split(/[.,]/);
  const centavos = Number(inteira) * 100 + Number(decimal.padEnd(2, "0"));

  return negativo ? -centavos : centavos;
}

/** Devolve a string que vai para uma coluna `numeric(12,2)`. Preserva o sinal. */
export function deCentavos(centavos: number): string {
  exigeInteiro(centavos);
  const negativo = centavos < 0;
  const abs = negativo ? -centavos : centavos;
  const texto = `${Math.trunc(abs / 100)}.${String(abs % 100).padStart(2, "0")}`;
  return negativo ? `-${texto}` : texto;
}

/** Formata para a tela, em pt-BR. */
export function formatar(centavos: number): string {
  exigeInteiro(centavos);
  return (centavos / 100).toLocaleString("pt-BR", {
    style: "currency",
    currency: "BRL",
  });
}

/**
 * Percentual de um valor — é isto que a política de falta usa (D2).
 * Arredonda meio para longe do zero, para que -50% de -100 seja o espelho de
 * +50% de +100. Meio para cima quebraria essa simetria nos negativos.
 */
export function percentual(centavos: number, pct: number): number {
  exigeInteiro(centavos);
  if (!Number.isFinite(pct)) throw new Error(`Percentual inválido: ${pct}`);

  const bruto = (centavos * pct) / 100;
  const sinal = bruto < 0 ? -1 : 1;
  return sinal * Math.round(sinal * bruto);
}

export function somar(...valores: number[]): number {
  valores.forEach(exigeInteiro);
  return valores.reduce((total, v) => total + v, 0);
}

function exigeInteiro(centavos: number): void {
  if (!Number.isInteger(centavos)) {
    throw new Error(
      `Centavos precisa ser inteiro (recebido: ${centavos}). Não guarde dinheiro em float.`,
    );
  }
}
