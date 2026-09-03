/**
 * A linha do mês — o vocabulário único (B54, §5.4 da estratégia do canal).
 *
 * **A decisão que este arquivo carrega:** o que amarra cobrança, pagamento e
 * recibo não é a cobrança, é a **competência**. Amarrar por `cobranca_id`
 * quebraria na primeira psicóloga que cobra por sessão e emite recibo por mês —
 * quatro cobranças, um documento.
 *
 * E a segunda, que é a que importa mais:
 *
 *     **A mesma linha, com as mesmas marcas, na mesma ordem e com as
 *     mesmas palavras, aparece na tela dela e na página do paciente.**
 *
 * Por isso `marcasDoMes` devolve a lista pronta, e nenhuma das duas telas
 * escreve rótulo próprio. Uma tela que montasse a frase por conta seria a
 * segunda fonte de verdade sobre dinheiro — S1 automático neste projeto —, e
 * foi exatamente o defeito que a 0090 acabou de consertar entre `retorno` e
 * `financeiro_do_mes`. A varredura `a-linha-do-mes-tem-uma-lingua-so.test.ts`
 * reprova quem escrever esses rótulos à mão.
 *
 * **Fato no banco, palavra aqui.** `linhas_do_mes` (0095) devolve números e
 * datas; nenhum "pago", "em aberto" ou "disponível" existe em SQL.
 *
 * ---
 *
 * **A quarta marca não está aqui, e a ausência é escrita.** O §5.4 pede
 * Combinado · Comprovante · Pago · Recibo. **Comprovante** depende da tabela
 * `comprovantes` (§4.8), que é da B53 — e a B53 não abre por decisão: o OCR do
 * §4.9 acrescenta um operador ao inventário da política de privacidade, e a
 * cláusula precisa existir no doc 18 antes do código.
 *
 * Então a marca não aparece de jeito nenhum. Não aparece como "não enviado",
 * não aparece cinza, não aparece desabilitada. Um lugar em branco esperando
 * feature é "a promessa que o software não cumpre" — o antipadrão que já custou
 * seis correções a este produto.
 */

import { FUSO } from "@/lib/tempo";
import { formatar } from "@/lib/dinheiro";

/** O que `linhas_do_mes(paciente, 12)` devolve, linha a linha. */
export type LinhaDoMes = {
  /** Primeiro dia da competência, em data pura: "2026-08-01". */
  competencia: string;
  /** Reais, como o `numeric` do banco entrega — o PostgREST manda string. */
  combinado: number | string;
  quantos: number;
  aberto: number | string;
  pago: number | string;
  perdoado: number | string;
  pago_em: string | null;
  recibo: string | null;
  recibo_numero: number | null;
  recibo_em: string | null;
  /** Se o recibo ainda cabe na janela de 90 dias que `documento_do_link` exige. */
  recibo_na_janela: boolean;
};

const MES_E_ANO = new Intl.DateTimeFormat("pt-BR", {
  timeZone: FUSO,
  month: "long",
  year: "numeric",
});

const DIA_CURTO = new Intl.DateTimeFormat("pt-BR", {
  timeZone: FUSO,
  day: "2-digit",
  month: "2-digit",
});

/**
 * "agosto de 2026".
 *
 * O meio-dia UTC é a lei nº 3 do jeito mais barato: "2026-08-01" é meia-noite
 * UTC, que em São Paulo ainda é 31 de julho — e a competência de agosto viraria
 * julho na tela.
 */
export function nomeDoMes(
  competencia: string | null | undefined,
  semData = "o mês",
): string {
  if (!competencia) return semData;
  const d = new Date(
    /^\d{4}-\d{2}-\d{2}$/.test(competencia) ? `${competencia}T12:00:00Z` : competencia,
  );
  if (Number.isNaN(d.getTime())) return semData;
  return MES_E_ANO.format(d);
}

/** "12/08", ou travessão — nunca uma data inventada. */
export function diaCurto(iso: string | null | undefined): string {
  if (!iso) return "—";
  const d = new Date(/^\d{4}-\d{2}-\d{2}$/.test(iso) ? `${iso}T12:00:00Z` : iso);
  if (Number.isNaN(d.getTime())) return "—";
  return DIA_CURTO.format(d);
}

function reais(v: number | string | null | undefined): number {
  const n = typeof v === "string" ? Number(v) : v;
  return typeof n === "number" && Number.isFinite(n) ? n : 0;
}

/** "R$ 1.300,00" — pela mesma função que a tela dela usa, em centavos inteiros. */
export function emReais(v: number | string | null | undefined): string {
  return formatar(Math.round(reais(v) * 100));
}

/** "5 horários", "um horário" — número por extenso até nove, como na mensageria. */
export function horarios(quantos: number): string {
  const n = Number.isInteger(quantos) && quantos > 0 ? quantos : 0;
  if (n === 0) return "nenhum horário";
  const extenso = ["", "um", "dois", "três", "quatro", "cinco", "seis", "sete", "oito", "nove"];
  return n === 1 ? "um horário" : `${n < extenso.length ? extenso[n] : n} horários`;
}

/**
 * O estado do dinheiro do mês.
 *
 * **"em aberto" ganha de "pago" sempre que sobra valor.** Um mês com R$ 1.040
 * pagos e R$ 260 em aberto não é um mês pago: dizer "pago em 02/09" ali seria
 * o campo que não faz o que ela digitou, com dinheiro dentro.
 */
export type MarcaDoPago = "em_aberto" | "pago" | "perdoado" | "nada";

export function marcaDoPago(l: LinhaDoMes): MarcaDoPago {
  if (reais(l.aberto) > 0) return "em_aberto";
  if (reais(l.pago) > 0) return "pago";
  if (reais(l.perdoado) > 0) return "perdoado";
  return "nada";
}

/**
 * O estado do recibo.
 *
 * `comJanela` é `true` na página do paciente e `false` na tela dela, e a
 * diferença não é de permissão: `documento_do_link` só serve documento dos
 * últimos 90 dias (0066), então oferecer "abrir" para o recibo de março na
 * página dele seria oferecer uma porta que responde 404. Ela não tem essa
 * restrição — abre pela ficha, com a RLS da conta dela.
 */
export type MarcaDoRecibo = "nao_emitido" | "disponivel" | "guardado";

export function marcaDoRecibo(l: LinhaDoMes, comJanela: boolean): MarcaDoRecibo {
  // **A existência é `recibo_em`, não o id.** Desde a 0096 o id sai nulo na
  // página do paciente quando o documento está fora da janela — a lista mostra
  // que o recibo existe sem entregar o endereço dele. Ler o id como sinal de
  // existência faria a página dizer "ainda não emitido" sobre um recibo que
  // está emitido, que é mentira e manda a pessoa cobrar dela um papel que ela
  // já fez.
  if (!l.recibo_em) return "nao_emitido";
  if (!comJanela || l.recibo_na_janela) return "disponivel";
  return "guardado";
}

/** As três marcas, nesta ordem, nos dois lugares. */
export const MARCAS = ["combinado", "pago", "recibo"] as const;
export type Marca = (typeof MARCAS)[number];

export type MarcaMontada = {
  chave: Marca;
  rotulo: string;
  texto: string;
};

/**
 * A linha do mês, montada.
 *
 * As duas telas chamam esta função e desenham o que vier — nenhuma escreve
 * "Combinado", "em aberto" ou "disponível" por conta própria.
 */
export function marcasDoMes(l: LinhaDoMes, comJanela: boolean): MarcaMontada[] {
  const pago = marcaDoPago(l);
  const recibo = marcaDoRecibo(l, comJanela);

  const textoDoPago =
    pago === "em_aberto"
      ? `${emReais(l.aberto)} em aberto`
      : pago === "pago"
        ? `pago em ${diaCurto(l.pago_em)}`
        : pago === "perdoado"
          ? "perdoado"
          : "—";

  const textoDoRecibo =
    recibo === "disponivel"
      ? "disponível"
      : recibo === "guardado"
        ? `emitido em ${diaCurto(l.recibo_em)}`
        : "ainda não emitido";

  // Mês sem cobrança nenhuma existe: é o mês que só tem documento em cima dele
  // — um recibo trimestral cobre três competências e as cobranças podem estar
  // lançadas em uma só. Escrever "R$ 0,00 · nenhum horário" ao lado de um
  // recibo de R$ 800 é a tela se contradizendo sobre o mesmo mês. O travessão
  // diz o que é verdade: aqui não há combinado lançado.
  const textoDoCombinado =
    l.quantos > 0 ? `${emReais(l.combinado)} · ${horarios(l.quantos)}` : "—";

  return [
    { chave: "combinado", rotulo: "Combinado", texto: textoDoCombinado },
    { chave: "pago", rotulo: "Pago", texto: textoDoPago },
    { chave: "recibo", rotulo: "Recibo", texto: textoDoRecibo },
  ];
}

/**
 * A frase do recibo guardado, na página do paciente.
 *
 * Sem ela a pessoa conclui que o recibo sumiu — e depois que o consultório
 * perdeu os documentos dele. É a mesma escolha de `fraseDaJanela`: dizer o
 * recorte transforma uma ausência numa regra, e regra a pessoa entende.
 */
export function fraseDoReciboGuardado(): string {
  return (
    "Recibo emitido há mais de três meses fica guardado, e o link deixa de " +
    "abrir. Se precisar dele de novo, é só pedir a quem te enviou este link."
  );
}

/** O recorte, dito em voz alta na página do paciente. */
export function fraseDosMeses(): string {
  return "Os últimos doze meses. O que for mais antigo fica com quem te atende.";
}
