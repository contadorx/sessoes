import { paraCentavos } from "@/lib/dinheiro";

/**
 * A camada de entrada: o que ela **digitou**, virando o que o sistema guarda.
 *
 * A fronteira que este arquivo existe para marcar:
 *
 * - `lib/dinheiro.ts` (`paraCentavos`) é a camada de **fronteira**. Ela recebe
 *   o que vem do banco — `numeric` como string — que nunca tem separador de
 *   milhar. Recusar `1.200` ali é decisão, não descuido: se `paraCentavos`
 *   aceitasse milhar, `"1.200"` vindo do banco seria ambíguo entre R$ 1,20 e
 *   R$ 1.200,00, e a ambiguidade viraria silêncio.
 * - `lib/formato.ts` (`lerValor`) é a camada de **entrada**. Aqui o milhar é
 *   esperado, porque é assim que gente escreve preço.
 *
 * Antes desta separação existir por escrito, o produto tinha **duas**
 * normalizações locais e incompatíveis espalhadas por sete arquivos, e as duas
 * erravam caladas em direções opostas: `Number("1.200")` gravava R$ 1,20, e
 * `"1200.00".replace(/\./g,"")` gravava R$ 120.000,00. Nenhuma das duas
 * mostrava erro. Por isso `lerValor` é o **único** parser de dinheiro digitado
 * do produto, e há suíte que reprova quem escrever o oitavo.
 */

/**
 * Uma caixa de seleção, lida do jeito que o HTML manda.
 *
 * **Caixa desmarcada não envia nada.** É a regra que o produto esqueceu em três
 * lugares: `form.get("ativo") !== "nao"` devolve `true` para a caixa
 * desmarcada, porque `null !== "nao"`, e nenhum formulário do produto tinha um
 * campo escondido mandando `"nao"`. As duas caixas da fila eram, na prática,
 * escreve-sempre-verdadeiro — e uma delas é a que tira alguém de receber
 * oferta.
 *
 * A ausência é a única coisa que decide. O valor enviado varia de tela para
 * tela (`"sim"`, `"1"`, ou o `"on"` que o navegador manda quando o `value` não
 * foi escrito), e por isso não é ele que responde a pergunta: presente é
 * marcado, ausente é desmarcado.
 */
export function caixaMarcada(form: FormData, nome: string): boolean {
  return form.get(nome) !== null;
}

/** Só os dígitos — o que se guarda de CPF, CNPJ e telefone. */
export function digitos(bruto: string | null | undefined): string {
  return (bruto ?? "").replace(/\D/g, "");
}

/**
 * "200", "200,00", "R$ 200,00", "1.200,50", "1200.50" → centavos. **Zero
 * inclusive.**
 *
 * É o parser propriamente dito. Quem chama decide se zero serve: o combinado
 * de um atendimento gratuito é R$ 0,00 e sempre foi aceito no cadastro, mas
 * uma linha de despesa de R$ 0,00 não é despesa. Separar as duas coisas é o
 * que impede a política de um campo de virar regra de todos por acidente.
 *
 * Devolve `null` só quando não dá para ler — inclusive para negativo: nenhum
 * campo digitado do produto recebe sinal, e `paraCentavos` engoliria o "-".
 */
export function lerCentavos(bruto: string): number | null {
  const limpo = bruto.replace(/r\$/i, "").replace(/\s/g, "");
  if (limpo === "") return null;

  // Tem vírgula: ela é a decimal, e todo ponto é milhar. É o caso brasileiro,
  // e é o único em que a leitura não precisa de desempate.
  if (limpo.includes(",")) {
    if (!/^\d{1,3}(\.\d{3})*,\d{1,2}$/.test(limpo) && !/^\d+,\d{1,2}$/.test(limpo)) {
      return null;
    }
    return paraCentavos(limpo.replace(/\./g, "").replace(",", "."));
  }

  // Sem vírgula, o ponto é ambíguo — e é exatamente aqui que morava o S1.
  // O desempate é a **quantidade de casas depois do ponto**, não o palpite:
  //
  //   "1.200"     três casas → milhar. Dinheiro não tem três decimais, e em
  //               português isto é mil e duzentos. Era o que virava R$ 1,20.
  //   "1200.50"   uma ou duas casas → decimal em inglês, que é o que sai de
  //               planilha. Era o que virava R$ 120.000,00.
  //
  // O que não cai em nenhum dos dois ("12.3456", "1.20.30") é recusado. Campo
  // de dinheiro que adivinha é como o produto chegou aqui.
  if (/^\d+$/.test(limpo)) return paraCentavos(limpo);
  if (/^\d{1,3}(\.\d{3})+$/.test(limpo)) return paraCentavos(limpo.replace(/\./g, ""));
  if (/^\d+\.\d{1,2}$/.test(limpo)) return paraCentavos(limpo);

  return null;
}

/**
 * O mesmo parser, com a política mais comum embutida: **só valor positivo**.
 *
 * É o que a colagem do importador usa — lá `0` não é "de graça", é linha que
 * ela não preencheu — e o que serve a todo campo onde zero não faz sentido.
 */
export function lerValor(bruto: string): number | null {
  const centavos = lerCentavos(bruto);
  return centavos !== null && centavos > 0 ? centavos : null;
}

/**
 * Máscara de CPF aplicada **enquanto ela digita**: 000.000.000-00.
 *
 * Trunca em 11 dígitos em vez de recusar a tecla — recusar tecla em campo de
 * documento é o jeito mais rápido de fazer alguém achar que o campo travou.
 */
export function mascaraCpf(bruto: string): string {
  const d = digitos(bruto).slice(0, 11);
  if (d.length <= 3) return d;
  if (d.length <= 6) return `${d.slice(0, 3)}.${d.slice(3)}`;
  if (d.length <= 9) return `${d.slice(0, 3)}.${d.slice(3, 6)}.${d.slice(6)}`;
  return `${d.slice(0, 3)}.${d.slice(3, 6)}.${d.slice(6, 9)}-${d.slice(9)}`;
}

/** Máscara de CNPJ: 00.000.000/0000-00. */
export function mascaraCnpj(bruto: string): string {
  const d = digitos(bruto).slice(0, 14);
  if (d.length <= 2) return d;
  if (d.length <= 5) return `${d.slice(0, 2)}.${d.slice(2)}`;
  if (d.length <= 8) return `${d.slice(0, 2)}.${d.slice(2, 5)}.${d.slice(5)}`;
  if (d.length <= 12) return `${d.slice(0, 2)}.${d.slice(2, 5)}.${d.slice(5, 8)}/${d.slice(8)}`;
  return `${d.slice(0, 2)}.${d.slice(2, 5)}.${d.slice(5, 8)}/${d.slice(8, 12)}-${d.slice(12)}`;
}

/**
 * O documento dela é CPF **ou** CNPJ no mesmo campo, e ela não escolhe qual
 * numa aba antes de digitar. Até o 11º dígito a máscara é de CPF; do 12º em
 * diante o número só pode ser CNPJ, e a máscara troca sozinha.
 */
export function mascaraDocumento(bruto: string): string {
  const d = digitos(bruto);
  return d.length <= 11 ? mascaraCpf(d) : mascaraCnpj(d);
}

/**
 * Máscara de telefone: (11) 98765-4321.
 *
 * Aceita o DDI colado (13 dígitos começando em 55) porque é a forma como o
 * número sai daqui — `normalizarTelefone` guarda com DDI, e um valor guardado
 * reaberto no formulário não pode virar lixo.
 */
export function mascaraTelefone(bruto: string): string {
  let d = digitos(bruto);
  if (d.length > 11 && d.startsWith("55")) d = d.slice(2);
  d = d.slice(0, 11);

  if (d.length <= 2) return d;
  if (d.length <= 6) return `(${d.slice(0, 2)}) ${d.slice(2)}`;
  if (d.length <= 10) return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`;
  return `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`;
}

/**
 * O CPF como a Receita pede: 000.000.000-00 — e um travessão quando não há.
 *
 * Estava duplicado em `components/app/ReceitaSaude.tsx` e na página de
 * documento do fechamento, com regras de borda diferentes entre as duas.
 */
export function cpfBr(cpf: string | null): string {
  const d = digitos(cpf);
  return d.length === 11 ? mascaraCpf(d) : "—";
}

/**
 * "123.456.789-01" / "12.345.678/0001-99" — como as pessoas leem.
 *
 * Devolve o bruto quando não tem 11 nem 14 dígitos: num documento impresso é
 * melhor mostrar o que está gravado do que esconder atrás de um travessão.
 */
export function documentoBr(bruto: string | null): string | null {
  if (!bruto) return null;
  const d = digitos(bruto);
  if (d.length === 11) return mascaraCpf(d);
  if (d.length === 14) return mascaraCnpj(d);
  return bruto;
}
