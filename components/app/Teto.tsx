import {
  fraseDosPacientes,
  fraseDaSaida_pacientes,
  type Pacientes,
} from "@/lib/teto";

/**
 * **Este arquivo encolheu na OP8.** Ele tinha quatro componentes; ficou com um.
 *
 * `AvisoDoTeto`, `FilaPausadaNoTeto` e `TetoNaConta` descreviam o teto mensal de
 * mensagens do plano — a fila pausando, o aviso de cobrança não saindo, o número
 * na tela da conta. A migração 0060 tirou esse teto do produto, e os três
 * deixaram de ter o que dizer. O que entrou no lugar é o
 * `components/app/Faixa.tsx`, que fala de sessão em vez de mensagem.
 *
 * O que sobrou aqui é o limite de pacientes, que a 0048 desligou e ninguém
 * religou — e que continua construído, testado e pronto para o dia em que
 * alguém tiver um motivo.
 */

/**
 * O limite de pacientes.
 *
 * Aparece o tempo todo, e não só quando lota: um plano cujo limite só aparece
 * quando estoura não é plano, é armadilha. E a frase da saída vem junto, porque
 * limite sem saída é parede — arquivar quem encerrou devolve a vaga, e a ficha
 * continua guardada com o histórico inteiro (obrigação de guarda não é consumo
 * de plano).
 */
export function LimiteDePacientes({ p }: { p: Pacientes }) {
  if (!p.tem_limite) return null;

  const pct = Math.min(100, Math.round((100 * p.ativos) / Math.max(p.limite ?? 1, 1)));

  return (
    <div
      className={
        p.lotou
          ? "mb-5 rounded-cartao border border-vaga-linha bg-vaga-bg px-5 py-4"
          : "mb-5 rounded-cartao border border-linha bg-folha px-5 py-3"
      }
    >
      <div className="flex items-baseline justify-between gap-3">
        <span className={`text-[13px] ${p.lotou ? "font-medium text-vaga" : "text-tinta2"}`}>
          {fraseDosPacientes(p)}
        </span>
        <span className="font-mono text-[11.5px] tabular-nums text-tinta3">{pct}%</span>
      </div>
      <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-folha2">
        <div
          className={`h-full ${p.lotou ? "bg-vaga" : "bg-cheia"}`}
          style={{ width: `${pct}%` }}
        />
      </div>
      {p.lotou && (
        <p className="mt-2 max-w-2xl text-[12.5px] leading-relaxed text-tinta2">
          {fraseDaSaida_pacientes(p)}
        </p>
      )}
    </div>
  );
}
