import "server-only";
import { adaptadorPara } from "@/lib/mensageria/adaptadores";

/**
 * O que a tela pública pode afirmar sobre o envio automático.
 *
 * "A promessa que o software não cumpre" é um antipadrão nomeado deste projeto
 * e **já aconteceu quatro vezes**: a `/privacidade` descreveu duas exclusões
 * inexistentes, a `/termos` prometeu 60 mensagens depois de o limite ter
 * mudado, a página de planos descreveu oito recursos inexistentes, e a landing
 * trouxe o nono de volta pelo lado que a restrição do banco não alcança.
 *
 * O conserto que importa nunca foi a frase — foi a varredura. Aqui isso vira
 * estrutura: **seis lugares afirmavam que a mensagem sai sozinha**, cada um com
 * a sua redação, e nenhum tinha como saber se isso é verdade hoje. Agora existe
 * uma pergunta só, e ela é feita a quem sabe responder: o adaptador de
 * mensageria (`lib/mensageria/adaptadores.ts`). No dia em que o BSP entrar, as
 * seis telas ficam verdadeiras juntas, sem ninguém reescrever nada.
 *
 * É o oposto de guardar um `ENVIO_AUTOMATICO = true` aqui: isso seria uma
 * segunda fonte de verdade sobre o mesmo fato, e a primeira coisa que
 * divergiria.
 */
export function envioAutomaticoLigado(): boolean {
  return adaptadorPara("whatsapp").disponivel;
}

/**
 * A frase de estado, ou nada.
 *
 * Vazia quando o canal está ligado — aí a página já diz a verdade sozinha e uma
 * observação a mais seria ruído. Quando não está, a frase é curta e factual: o
 * que muda para ela, sem pedir desculpa e sem explicar a decisão de projeto na
 * tela de quem só quer saber o que o produto faz.
 */
export function fraseDoEnvioAutomatico(): string {
  if (envioAutomaticoLigado()) return "";
  return (
    "O envio automático ainda não está ligado: até ele entrar, as mensagens " +
    "de todos os planos nascem escritas e saem do seu WhatsApp, com um toque seu."
  );
}
