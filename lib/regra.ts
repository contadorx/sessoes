/**
 * A regra de prioridade da fila. É **dela** — o produto não escolhe por ela, e
 * a fila nunca vira leilão: nenhuma das opções ordena por dinheiro.
 */

export const REGRAS = ["mais_tempo_sem_sessao", "ordem_de_entrada"] as const;

export type Regra = (typeof REGRAS)[number];

export const ROTULO_REGRA: Record<Regra, string> = {
  mais_tempo_sem_sessao: "quem está há mais tempo sem sessão",
  ordem_de_entrada: "quem entrou primeiro na fila",
};

export const EXPLICACAO_REGRA: Record<Regra, string> = {
  mais_tempo_sem_sessao:
    "Prioriza a continuidade: quem ficou mais tempo sem atendimento vem primeiro. É o padrão, e é a escolha clínica na maioria dos consultórios.",
  ordem_de_entrada:
    "Prioriza a espera declarada: quem pediu para entrar na fila antes recebe a oferta antes, independentemente de quando foi a última sessão.",
};
