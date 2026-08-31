import { DIAS, type DiaSemana } from "@/lib/enquadre";
import { normalizarTelefone } from "@/lib/paciente";
import { paraCentavos } from "@/lib/dinheiro";

/**
 * Trazer a agenda de fora.
 *
 * Este arquivo é o que decide se "do zero à primeira vaga" cabe em meia hora ou
 * vira uma tarde de digitação. Quem vai usar tem a agenda numa caderneta, numa
 * planilha ou no Google Agenda, e vai **colar** — não preencher trinta
 * formulários.
 *
 * Três decisões de desenho, e as três são sobre respeitar quem digitou:
 *
 * **1. O separador é descoberto, não exigido.** Ponto e vírgula, vírgula ou
 * tabulação (que é o que sai de uma planilha ao copiar). Pedir um formato exato
 * a quem está com pressa é uma forma educada de recusar o trabalho.
 *
 * **2. Nada é adivinhado.** Linha que não dá para ler vira erro **com o número
 * da linha e o motivo**, e a importação inteira continua sendo mostrada. Uma
 * importação que aceita 28 de 30 e some com as duas é como um cadastro some sem
 * ninguém notar.
 *
 * **3. Nada entra sem ela ver.** O resultado desta função é uma pré-visualização.
 * Quem grava é a ação do servidor, depois de ela olhar.
 */

export type LinhaLida = {
  linha: number;
  nome: string;
  telefone: string | null;
  diaSemana: DiaSemana | null;
  hora: string | null;
  valorCentavos: number | null;
};

export type ErroDeLinha = {
  linha: number;
  texto: string;
  motivo: string;
};

export type Leitura = {
  pacientes: LinhaLida[];
  erros: ErroDeLinha[];
};

/** Aceita ";", tab ou "," — o que aparecer primeiro na linha. */
function partir(linha: string): string[] {
  const separador = linha.includes(";") ? ";" : linha.includes("\t") ? "\t" : ",";
  return linha.split(separador).map((c) => c.trim());
}

/** "terça", "TERÇA-FEIRA", "ter", "3" → 2. */
export function lerDiaDaSemana(bruto: string): DiaSemana | null {
  const limpo = bruto
    .trim()
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/-?feira$/, "")
    .trim();

  if (limpo === "") return null;

  // Número de 0 a 6, na mesma convenção do Postgres (0 = domingo).
  if (/^[0-6]$/.test(limpo)) return Number(limpo) as DiaSemana;

  // Abreviação vale, mas ela tem de ser **prefixo do dia** — não o contrário.
  // Comparar os três primeiros caracteres fazia "qualquer" virar quarta-feira,
  // que é exatamente o tipo de chute que enche a agenda de horário errado.
  const indice = DIAS.findIndex((d) => {
    const nome = d.normalize("NFD").replace(/[̀-ͯ]/g, "");
    return nome === limpo || (limpo.length >= 3 && nome.startsWith(limpo));
  });

  return indice >= 0 ? (indice as DiaSemana) : null;
}

/** "15", "15h", "15:00", "15h30", "9h5" → "15:00" … "09:05". */
export function lerHora(bruto: string): string | null {
  const limpo = bruto.trim().toLowerCase().replace(/\s/g, "");
  if (limpo === "") return null;

  const m = limpo.match(/^(\d{1,2})(?:[h:.](\d{1,2}))?h?$/);
  if (!m) return null;

  const h = Number(m[1]);
  const min = m[2] === undefined ? 0 : Number(m[2]);
  if (h > 23 || min > 59) return null;

  return `${String(h).padStart(2, "0")}:${String(min).padStart(2, "0")}`;
}

/** "200", "200,00", "R$ 200,00", "1.200,50", "1200.50" → centavos. */
export function lerValor(bruto: string): number | null {
  const limpo = bruto.replace(/r\$/i, "").trim();
  if (limpo === "") return null;

  // "1.200,50" é brasileiro; "1200.50" é o que sai de planilha em inglês.
  const brasileiro = /,\d{1,2}$/.test(limpo);
  const normalizado = brasileiro
    ? limpo.replace(/\./g, "").replace(",", ".")
    : limpo.replace(/,/g, "");

  if (!/^\d+(\.\d{1,2})?$/.test(normalizado)) return null;

  const centavos = paraCentavos(normalizado);
  return centavos > 0 ? centavos : null;
}

/**
 * Lê o texto colado.
 *
 * Formato: `nome; telefone; dia; hora; valor` — do segundo campo em diante,
 * tudo é opcional. Só o nome é obrigatório, porque só ele não tem como ser
 * preenchido depois sem adivinhação.
 */
export function lerColagem(texto: string): Leitura {
  const pacientes: LinhaLida[] = [];
  const erros: ErroDeLinha[] = [];
  const vistos = new Set<string>();

  const linhas = texto.split(/\r?\n/);

  linhas.forEach((bruta, i) => {
    const numero = i + 1;
    const linha = bruta.trim();

    if (linha === "") return;

    // Cabeçalho de planilha: reconhecido e ignorado, não tratado como erro.
    if (/^nome\s*[;,\t]/i.test(linha)) return;

    const campos = partir(linha);
    const nome = campos[0]?.trim() ?? "";

    if (nome.length < 2) {
      erros.push({ linha: numero, texto: linha, motivo: "sem nome" });
      return;
    }

    const chave = nome.toLowerCase();
    if (vistos.has(chave)) {
      erros.push({ linha: numero, texto: linha, motivo: "nome repetido na colagem" });
      return;
    }
    vistos.add(chave);

    // `normalizarTelefone` **lança** em número impossível — é a lei nº 1 do
    // projeto aplicada a ele, e está certa lá. Aqui, porém, uma linha ruim não
    // pode derrubar a leitura das outras vinte e nove.
    const telefoneBruto = campos[1] ?? "";
    let telefone: string | null = null;

    if (telefoneBruto.trim() !== "") {
      try {
        telefone = normalizarTelefone(telefoneBruto);
      } catch {
        erros.push({ linha: numero, texto: linha, motivo: `telefone inválido: ${telefoneBruto.trim()}` });
        return;
      }
    }

    const diaBruto = campos[2] ?? "";
    const diaSemana = diaBruto.trim() === "" ? null : lerDiaDaSemana(diaBruto);
    if (diaBruto.trim() !== "" && diaSemana === null) {
      erros.push({ linha: numero, texto: linha, motivo: `não entendi o dia: ${diaBruto}` });
      return;
    }

    const horaBruta = campos[3] ?? "";
    const hora = horaBruta.trim() === "" ? null : lerHora(horaBruta);
    if (horaBruta.trim() !== "" && hora === null) {
      erros.push({ linha: numero, texto: linha, motivo: `não entendi o horário: ${horaBruta}` });
      return;
    }

    const valorBruto = campos[4] ?? "";
    const valorCentavos = valorBruto.trim() === "" ? null : lerValor(valorBruto);
    if (valorBruto.trim() !== "" && valorCentavos === null) {
      erros.push({ linha: numero, texto: linha, motivo: `não entendi o valor: ${valorBruto}` });
      return;
    }

    // Horário pela metade não vira enquadre: uma agenda com o dia certo e a hora
    // errada é pior do que uma agenda vazia, porque parece pronta.
    if ((diaSemana === null) !== (hora === null)) {
      erros.push({
        linha: numero,
        texto: linha,
        motivo: "para criar o horário fixo, preciso do dia E da hora",
      });
      return;
    }

    pacientes.push({ linha: numero, nome, telefone, diaSemana, hora, valorCentavos });
  });

  return { pacientes, erros };
}

/** Quantos viram horário fixo de verdade — é o número que interessa na tela. */
export function comHorario(leitura: Leitura): number {
  return leitura.pacientes.filter((p) => p.diaSemana !== null && p.hora !== null).length;
}
