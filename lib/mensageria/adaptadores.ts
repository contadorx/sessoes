import "server-only";
import type { Renderizado } from "./templates";

/**
 * A costura do provedor.
 *
 * O risco R4 do doc 11 é simples de enunciar: um dia a Meta reprova um template,
 * ou o BSP cai, ou o preço muda e o Gupshup deixa de fazer sentido. A mitigação
 * não é escolher o provedor certo — é fazer com que trocar de provedor seja
 * **editar um arquivo**. Este é o arquivo.
 *
 * Nada acima daqui (regra de negócio, cascata, cobrança) sabe o nome de um
 * provedor. Nada abaixo daqui sabe o que é uma vaga.
 */

export type Canal = "whatsapp" | "sms" | "email";

export type Envio = {
  canal: Canal;
  destino: string;
  conteudo: Renderizado;
};

export type ResultadoEnvio =
  | { ok: true; provedor: string; idExterno?: string }
  /**
   * `definitivo` é a diferença entre "tenta de novo daqui a pouco" e "não
   * adianta insistir". Número inválido é definitivo; timeout não é. Insistir no
   * definitivo queima dinheiro e reputação do número.
   */
  | { ok: false; provedor: string; erro: string; definitivo: boolean };

export interface Adaptador {
  readonly nome: string;
  /**
   * Falso enquanto não há provedor — o mesmo campo que
   * `lib/calendario/adaptadores.ts` declara, e pela mesma razão: quem chama
   * precisa **poder perguntar** antes de agir, em vez de descobrir pelo
   * resultado. O calendário acertou primeiro; a mensageria copiou tarde.
   */
  readonly disponivel: boolean;
  /** Por que não está disponível. Vai para a trilha e daí para a tela. */
  readonly motivo: string | null;
  suporta(canal: Canal): boolean;
  enviar(envio: Envio): Promise<ResultadoEnvio>;
}

/** O motivo, escrito uma vez: ele vai para a trilha, para o log e para a tela. */
export const SEM_PROVEDOR = "sem provedor de mensagem configurado";

/**
 * O adaptador que existe antes do BSP existir — e que **recusa**.
 *
 * Ele já existiu com outro nome e outro comportamento, e foi o pior defeito
 * que este produto teve no ar: chamava-se `registro`, devolvia `ok: true` com
 * um `idExterno` inventado (`registro:1788346982148`), e o worker então
 * carimbava `marcar_enviada`. O comentário de então dizia a verdade sem
 * perceber o tamanho dela — *"a mensagem percorre a fila inteira, é reservada,
 * marcada como enviada e aparece na trilha: só não sai do prédio"*.
 *
 * O que isso significava na mesa dela: a tela afirmava que a paciente tinha
 * sido avisada, e a paciente não tinha recebido nada. É um fato sobre outra
 * pessoa, afirmado por um sistema que não observou fato nenhum, e que ela não
 * tinha como conferir. Valia para as quatro mensagens essenciais — lembrete de
 * véspera, aviso de desmarque, encaixe confirmado e pedido de confirmação —
 * que saem automáticas **inclusive no Gratuito**.
 *
 * Não lança, de propósito: estourar deixaria a fila parada em silêncio, que é
 * pior. Recusa com motivo, e o motivo chega até a tela.
 */
export const semProvedor: Adaptador = {
  nome: "sem-provedor",
  disponivel: false,
  motivo: SEM_PROVEDOR,
  suporta: () => false,
  async enviar({ canal, destino, conteudo }) {
    console.info("[mensageria] recusado: sem provedor configurado", {
      canal,
      // Destino mascarado: log não é lugar de dado de contato completo (LGPD).
      destino: mascarar(destino),
      template: conteudo.nomeDoTemplate,
      modo: conteudo.modo,
    });
    return { ok: false, provedor: "sem-provedor", erro: SEM_PROVEDOR, definitivo: false };
  },
};

/** "5511900001234" → "5511*****1234". Suficiente para depurar, insuficiente para vazar. */
export function mascarar(destino: string): string {
  if (destino.includes("@")) {
    const [antes, dominio] = destino.split("@");
    return `${antes.slice(0, 2)}***@${dominio}`;
  }
  if (destino.length <= 8) return "***";
  return `${destino.slice(0, 4)}${"*".repeat(destino.length - 8)}${destino.slice(-4)}`;
}

/**
 * Escolhe o adaptador do canal.
 *
 * Enquanto nenhum provedor estiver plugado aqui, todo canal recebe o adaptador
 * que recusa — e quem chama tem que olhar `disponivel` **antes** de agir. O que
 * acontece com a mensagem nesse caso não é decisão deste arquivo: é do worker,
 * e a resposta dele é pôr a mensagem na mão dela, não marcá-la como enviada.
 *
 * Quando o BSP entrar (B10), é aqui que ele é plugado, e só aqui.
 */
/**
 * O e-mail, com o caminho próprio na frente e a queda atrás. (B55)
 *
 * DUAS COISAS QUE A DOCUMENTAÇÃO DOS PROVEDORES NÃO DEIXA ÓBVIAS
 *
 * **1 · O HTTP 200 não decide nada.** O Postal responde `{"status":"success"}`
 * com 200 quando a mensagem entra **na fila dele** — e responde 200 também
 * quando devolve erro no corpo. Quem decide é o `status` do JSON, nunca o
 * código HTTP. É por isso que este adaptador lê o corpo antes de comemorar.
 *
 * **2 · `ok: true` aqui significa "o provedor aceitou", e nada além disso.** A
 * pergunta "chegou?" tem outro dono: o webhook e a varredura. O `idExterno` é o
 * que amarra os dois — sem ele guardado, a confirmação chega e não acha a
 * mensagem.
 *
 * A queda cobre o provedor **recusar**. Ela não cobre o provedor aceitar e não
 * entregar, que é o caso que de fato acontece — e para esse existe o disjuntor.
 */
const adaptadorDeEmail: Adaptador = {
  nome: "email",
  disponivel: true,
  motivo: null,
  suporta: (canal) => canal === "email",

  async enviar({ destino, conteudo }): Promise<ResultadoEnvio> {
    const proprio = process.env.POSTAL_URL?.trim();
    const chavePropria = process.env.POSTAL_API_KEY?.trim();

    if (proprio && chavePropria) {
      const r = await pelosProprios(proprio, chavePropria, destino, conteudo);
      if (r.ok || r.definitivo) return r;
      // Não foi definitivo: o caminho próprio recusou, e a queda existe para
      // isto. Um destino inválido não melhora trocando de provedor.
    }

    const daQueda = process.env.BREVO_API_KEY?.trim();
    if (!daQueda) {
      return {
        ok: false,
        provedor: "email",
        erro: "o caminho próprio falhou e não há queda configurada",
        definitivo: false,
      };
    }

    return pelaQueda(daQueda, destino, conteudo);
  },
};

async function pelosProprios(
  url: string,
  chave: string,
  destino: string,
  conteudo: Renderizado,
): Promise<ResultadoEnvio> {
  try {
    const resposta = await fetch(`${url.replace(/\/$/, "")}/api/v1/send/message`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-server-api-key": chave },
      body: JSON.stringify({
        to: [destino],
        from: process.env.POSTAL_FROM ?? "Sessões <nao-responda@sessoes.com.br>",
        subject: conteudo.assunto ?? "Sessões",
        plain_body: conteudo.texto,
      }),
    });

    // O corpo decide, não o código. Ver o cabeçalho deste adaptador.
    const corpo = (await resposta.json().catch(() => null)) as
      | { status?: string; data?: Record<string, unknown> }
      | null;

    if (corpo?.status === "success") {
      const id = idDaResposta(corpo.data);
      return id
        ? { ok: true, provedor: "postal", idExterno: id }
        : {
            // Sem id não há como amarrar a confirmação: aceitar seria voltar a
            // afirmar entrega que ninguém confere.
            ok: false,
            provedor: "postal",
            erro: "o provedor aceitou e não devolveu id da mensagem",
            definitivo: false,
          };
    }

    return {
      ok: false,
      provedor: "postal",
      erro: `o provedor recusou: ${corpo?.status ?? resposta.status}`,
      definitivo: resposta.status === 400 || resposta.status === 422,
    };
  } catch (e) {
    return {
      ok: false,
      provedor: "postal",
      erro: e instanceof Error ? e.message : "falha de rede",
      definitivo: false,
    };
  }
}

async function pelaQueda(
  chave: string,
  destino: string,
  conteudo: Renderizado,
): Promise<ResultadoEnvio> {
  try {
    const resposta = await fetch("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: { "content-type": "application/json", "api-key": chave },
      body: JSON.stringify({
        sender: {
          email: process.env.BREVO_REMETENTE_EMAIL ?? "nao-responda@sessoes.com.br",
          name: process.env.BREVO_REMETENTE_NOME ?? "Sessões",
        },
        to: [{ email: destino }],
        subject: conteudo.assunto ?? "Sessões",
        textContent: conteudo.texto,
      }),
    });

    const corpo = (await resposta.json().catch(() => null)) as { messageId?: string } | null;

    if (resposta.ok && corpo?.messageId) {
      return { ok: true, provedor: "brevo", idExterno: corpo.messageId };
    }

    return {
      ok: false,
      provedor: "brevo",
      erro: `a queda recusou: ${resposta.status}`,
      definitivo: resposta.status === 400,
    };
  } catch (e) {
    return {
      ok: false,
      provedor: "brevo",
      erro: e instanceof Error ? e.message : "falha de rede",
      definitivo: false,
    };
  }
}

/** O id vem em `id` ou `message_id`, conforme a versão do provedor. */
function idDaResposta(dados: Record<string, unknown> | undefined): string | null {
  for (const chave of ["message_id", "messageId", "id"]) {
    const v = dados?.[chave];
    if (typeof v === "string" && v.trim() !== "") return v.trim();
    if (typeof v === "number") return String(v);
  }
  return null;
}

/**
 * O SMS — construído, e **fora da vitrine**. (B52)
 *
 * Decisão de 03/09: ele é **medida de crise**. Não é opção de cadastro, não é
 * escolha da paciente na pré-ficha e não é recurso de plano; entra quando uma
 * mensagem **urgente** não tem mais por onde sair, e só aí. `precos_canal`, no
 * banco desde sempre, diz por quê: em milésimos de centavo, e-mail **200**,
 * WhatsApp **4.500**, SMS **8.000**. Quarenta vezes o e-mail, para chegar ao
 * mesmo lugar em quase todo caso.
 *
 * `testes/o-sms-nao-vira-vitrine.test.ts` reprova quem devolver a opção à tela.
 */
const adaptadorDeSms: Adaptador = {
  nome: "sms",
  disponivel: true,
  motivo: null,
  suporta: (canal) => canal === "sms",

  async enviar({ destino, conteudo }): Promise<ResultadoEnvio> {
    const chave = process.env.SMS_API_KEY?.trim();
    const url = process.env.SMS_URL?.trim();

    if (!chave || !url) {
      return { ok: false, provedor: "sms", erro: "sem provedor de SMS", definitivo: false };
    }

    try {
      const resposta = await fetch(url, {
        method: "POST",
        headers: { "content-type": "application/json", authorization: `Bearer ${chave}` },
        body: JSON.stringify({
          // O SMS não tem assunto e não tem formatação: vai o corpo, e o corpo
          // já nasce discreto — o modo da paciente viaja com a mensagem.
          to: destino,
          message: conteudo.texto,
        }),
      });

      const corpo = (await resposta.json().catch(() => null)) as
        | { id?: string; messageId?: string }
        | null;

      const id = corpo?.id ?? corpo?.messageId;
      if (resposta.ok && id) return { ok: true, provedor: "sms", idExterno: String(id) };

      return {
        ok: false,
        provedor: "sms",
        erro: `o provedor de SMS recusou: ${resposta.status}`,
        definitivo: resposta.status === 400,
      };
    } catch (e) {
      return {
        ok: false,
        provedor: "sms",
        erro: e instanceof Error ? e.message : "falha de rede",
        definitivo: false,
      };
    }
  },
};

/** Igual ao e-mail: a pergunta é sobre variável de ambiente, não sobre saúde do provedor. */
export function smsConfigurado(): boolean {
  return Boolean(process.env.SMS_API_KEY?.trim() && process.env.SMS_URL?.trim());
}

export function adaptadorPara(canal: Canal): Adaptador {
  if (canal === "email" && emailConfigurado()) return adaptadorDeEmail;
  if (canal === "sms" && smsConfigurado()) return adaptadorDeSms;
  return semProvedor;
}

/**
 * O e-mail está de pé? (B55)
 *
 * A pergunta é sobre **variável de ambiente**, e não sobre o provedor estar
 * respondendo: quem responde por "está respondendo?" é o disjuntor, que mede
 * confirmação de entrega. Aqui é só a diferença entre existir uma ponta e não
 * existir ponta nenhuma — e ela é a única coisa que faz as telas pararem de
 * dizer que o envio é manual (B50).
 *
 * Sem `POSTAL_URL` **e** sem `BREVO_API_KEY` não há caminho nenhum, e o
 * adaptador que recusa continua valendo. Com um dos dois, há.
 */
export function emailConfigurado(): boolean {
  return Boolean(process.env.POSTAL_URL?.trim() || process.env.BREVO_API_KEY?.trim());
}
