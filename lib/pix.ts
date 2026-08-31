import { deCentavos } from "@/lib/dinheiro";

/**
 * O PIX que funciona esta semana, sem provedor nenhum.
 *
 * O doc 13 escolheu o Asaas, e ele vem. Mas a decisão de sequência é esta: antes
 * de qualquer intermediário, o sistema gera o **BR Code** (o "copia e cola") da
 * chave PIX **dela**. O dinheiro vai direto para a conta dela, sem tarifa, sem
 * KYC, sem subconta, sem esperar avaliação regulatória de ninguém.
 *
 * Três razões para isso não ser um paliativo, e sim o caminho principal:
 *
 * **1. É o que a psicóloga já faz.** Ela manda a chave PIX no WhatsApp e torce
 * para a pessoa lembrar do valor. O que falta não é um gateway — é a mensagem
 * sair sozinha com o valor certo, o que a B11 já resolveu.
 *
 * **2. Não custodiar nada é uma posição, não uma limitação.** O doc 10 lista o
 * peso regulatório de intermediar (conta nominal por recebedora, KYC herdado,
 * MED em 4 dias, disputa que sobra para nós). Enquanto o dinheiro não passa por
 * aqui, nada disso existe.
 *
 * **3. É o caminho alternativo que o doc 10 exige que sempre haja** — "ela pode
 * continuar cobrando por fora e só registrar no sistema" — e ele fica bom em vez
 * de apenas possível. Se um dia a conta dela travar no provedor, isto continua
 * de pé.
 *
 * A especificação é o BR Code do Banco Central (EMV® QRCPS-MPM). Formato TLV:
 * cada campo é `ID (2) + tamanho (2) + valor`, e o último campo é o CRC.
 */

export type DadosPix = {
  /** A chave: CPF/CNPJ (só dígitos), telefone (+55…), e-mail ou EVP (uuid). */
  chave: string;
  /** Nome de quem recebe. Até 25 caracteres, sem acento. */
  nome: string;
  /** Cidade de quem recebe. Até 15 caracteres, sem acento. */
  cidade: string;
  /** Valor em centavos. Omitido, o app do banco pergunta quanto. */
  valorCentavos?: number;
  /**
   * Identificador da cobrança, até 25 caracteres alfanuméricos. Aparece no
   * extrato dela — é o que permite casar o PIX recebido com a sessão.
   */
  txid?: string;
};

/** Campo TLV: id + tamanho em dois dígitos + valor. */
function campo(id: string, valor: string): string {
  const tamanho = String(valor.length).padStart(2, "0");
  if (valor.length > 99) {
    throw new Error(`Campo ${id} tem ${valor.length} caracteres; o máximo é 99.`);
  }
  return `${id}${tamanho}${valor}`;
}

/**
 * Tira acento e o que não é ASCII imprimível.
 *
 * Não é preciosismo: o BR Code é lido por dezenas de aplicativos de banco, e
 * vários quebram com caractere fora da tabela. Um "José" que vira código
 * inválido é uma cobrança que não pode ser paga.
 */
export function apenasAscii(texto: string, limite: number): string {
  return texto
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^\x20-\x7E]/g, "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, limite)
    .trim();
}

/** Só letras e números, que é o que o campo de identificador aceita. */
export function limparTxid(bruto: string): string {
  return bruto
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^A-Za-z0-9]/g, "")
    .slice(0, 25);
}

/**
 * CRC-16/CCITT-FALSE — polinômio 0x1021, início 0xFFFF, sem reflexão.
 *
 * É o que o Banco Central especifica, e é diferente do CRC16 "comum" que a
 * maioria das bibliotecas traz. Errar aqui produz um código que **parece**
 * certo e é recusado no aplicativo do banco, sem explicação.
 */
export function crc16(texto: string): string {
  let crc = 0xffff;

  for (let i = 0; i < texto.length; i += 1) {
    crc ^= texto.charCodeAt(i) << 8;
    for (let b = 0; b < 8; b += 1) {
      crc = crc & 0x8000 ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff;
    }
  }

  return crc.toString(16).toUpperCase().padStart(4, "0");
}

/** Reconhece o formato da chave, para validar antes de gerar um código torto. */
export function tipoDaChave(chave: string): "cpf" | "cnpj" | "telefone" | "email" | "aleatoria" | null {
  const limpa = chave.trim();

  if (/^[0-9]{11}$/.test(limpa)) return "cpf";
  if (/^[0-9]{14}$/.test(limpa)) return "cnpj";
  if (/^\+55[0-9]{10,11}$/.test(limpa)) return "telefone";
  if (/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(limpa) && limpa.length <= 77) return "email";
  if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(limpa)) return "aleatoria";

  return null;
}

/**
 * Monta o "copia e cola".
 *
 * Lança quando a chave não tem formato de chave PIX. É deliberado: gerar um
 * código com chave inválida produziria um QR bonito que ninguém consegue pagar,
 * e o erro só apareceria no celular do paciente.
 */
export function montarBrCode(dados: DadosPix): string {
  const chave = dados.chave.trim();

  if (tipoDaChave(chave) === null) {
    throw new Error(
      "Chave PIX em formato desconhecido. Use CPF/CNPJ só com números, " +
        "telefone com +55, e-mail ou a chave aleatória.",
    );
  }

  const nome = apenasAscii(dados.nome, 25) || "RECEBEDOR";
  const cidade = apenasAscii(dados.cidade, 15) || "BRASIL";
  const txid = dados.txid ? limparTxid(dados.txid) : "";

  const contaPix =
    campo("00", "br.gov.bcb.pix") + campo("01", chave);

  const partes = [
    campo("00", "01"),
    campo("26", contaPix),
    campo("52", "0000"),
    campo("53", "986"),
  ];

  if (dados.valorCentavos !== undefined) {
    if (!Number.isInteger(dados.valorCentavos) || dados.valorCentavos <= 0) {
      throw new Error("Valor do PIX precisa ser um número inteiro de centavos, maior que zero.");
    }
    // O padrão pede ponto decimal e nada de separador de milhar.
    partes.push(campo("54", deCentavos(dados.valorCentavos)));
  }

  partes.push(campo("58", "BR"));
  partes.push(campo("59", nome));
  partes.push(campo("60", cidade));

  // "***" é o identificador vazio previsto no padrão, para quando não há txid.
  partes.push(campo("62", campo("05", txid || "***")));

  const semCrc = `${partes.join("")}6304`;
  return `${semCrc}${crc16(semCrc)}`;
}

/**
 * Confere um BR Code já pronto.
 *
 * Existe para o teste, e para o dia em que alguém colar um código de fora e
 * quiser saber se está inteiro.
 */
export function brCodeValido(codigo: string): boolean {
  if (codigo.length < 8) return false;
  const corpo = codigo.slice(0, -4);
  const crc = codigo.slice(-4).toUpperCase();
  return corpo.endsWith("6304") && crc16(corpo) === crc;
}

/**
 * Lê os campos de primeiro nível, **na ordem em que aparecem**.
 *
 * Devolve um `Map`, e não um objeto, por um motivo que custou um teste: as
 * chaves do TLV são numéricas ("26", "52", "53"), e o JavaScript reordena
 * chaves assim num objeto comum — `{"00":…, "26":…}` sai como `26` primeiro.
 * Para um formato em que a **ordem é parte do dado**, isso é o tipo de detalhe
 * que passa despercebido e estraga a reconstrução.
 */
export function lerTlv(codigo: string): Map<string, string> {
  const campos = new Map<string, string>();
  let i = 0;

  while (i + 4 <= codigo.length) {
    const id = codigo.slice(i, i + 2);
    const tamanho = Number(codigo.slice(i + 2, i + 4));
    if (!Number.isInteger(tamanho)) break;

    const valor = codigo.slice(i + 4, i + 4 + tamanho);
    if (valor.length < tamanho) break;

    campos.set(id, valor);
    i += 4 + tamanho;
  }

  return campos;
}
