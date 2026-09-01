import {
  nivelDoAviso,
  fraseDoTeto,
  fraseDoQueParou,
  fraseDaSaida,
  fraseDoRestante,
  filaPausada,
  fraseDaFilaPausada,
  type Teto,
} from "@/lib/teto";

/**
 * O aviso do teto.
 *
 * Duas regras, e as duas vêm de o teto ser meu e o custo dele ser dela:
 *
 * 1. **Diz o que continua saindo, não só o que parou.** "Você atingiu o
 *    limite" sozinho deixa ela imaginando o pior — e o pior aqui é exatamente
 *    o que não acontece: o paciente ficar sem lembrete. A frase mais
 *    importante desta caixa é a segunda.
 *
 * 2. **Não vira anúncio.** O limite é meu, não um defeito dela. Uma tela de
 *    limite que vira vitrine é a que faz a pessoa desconfiar de todo o resto,
 *    e há teste que reprova preço, "assine agora" e "aproveite" em qualquer
 *    das frases.
 *
 * Aparece a partir de 70% e não antes: um aviso que fica o mês inteiro na tela
 * é um aviso que se aprende a não ler.
 */
export function AvisoDoTeto({ teto }: { teto: Teto }) {
  const nivel = nivelDoAviso(teto);
  if (nivel === "nenhum") return null;

  const estourou = nivel === "estourou";

  return (
    <div
      className={
        estourou
          ? "mb-5 rounded-cartao border border-vaga-linha bg-vaga-bg px-5 py-4"
          : "mb-5 rounded-cartao border border-aviso-linha bg-aviso-bg px-5 py-3"
      }
    >
      <p
        className={`text-[13px] font-medium ${estourou ? "text-vaga" : "text-aviso"}`}
      >
        {fraseDoTeto(teto)}
      </p>

      {estourou ? (
        <>
          <p className="mt-1.5 max-w-2xl text-[12.5px] leading-relaxed text-tinta2">
            {fraseDoQueParou(teto)}
          </p>
          <p className="mt-1.5 max-w-2xl text-[12.5px] leading-relaxed text-tinta2">
            {fraseDaSaida(teto)}
          </p>
        </>
      ) : (
        <p className="mt-1 text-[12px] leading-relaxed text-tinta2">
          {fraseDoRestante(teto)} Lembrete de véspera e aviso de desmarque não entram nessa
          conta e não param nunca.
        </p>
      )}
    </div>
  );
}

/**
 * A linha na vaga aberta.
 *
 * Existe para evitar o pior sintoma possível: ela cancelar uma sessão, ver a
 * fila não fazer nada, e concluir que o produto quebrou. A fila parada sem
 * motivo escrito é indistinguível de fila com defeito.
 */
export function FilaPausadaNoTeto({ teto }: { teto: Teto }) {
  if (!filaPausada(teto)) return null;
  return (
    <p className="mt-2 rounded-cartao border border-vaga-linha bg-vaga-bg px-4 py-2 text-[12.5px] leading-relaxed text-vaga">
      {fraseDaFilaPausada(teto)}
    </p>
  );
}

/** A linha discreta na tela da conta, sempre visível quando há teto. */
export function TetoNaConta({ teto }: { teto: Teto }) {
  if (!teto.tem_teto) {
    return (
      <p className="text-[12.5px] text-tinta2">
        Seu plano não tem limite de mensagens.
      </p>
    );
  }

  return (
    <div>
      <div className="flex items-baseline justify-between gap-3">
        <span className="text-[12.5px] text-tinta2">{fraseDoTeto(teto)}</span>
        <span className="font-mono text-[11.5px] tabular-nums text-tinta3">{teto.pct}%</span>
      </div>
      <div className="mt-1.5 h-1.5 overflow-hidden rounded-full bg-folha2">
        <div
          className={`h-full ${teto.estourou ? "bg-vaga" : "bg-cheia"}`}
          style={{ width: `${Math.min(100, teto.pct)}%` }}
        />
      </div>
      <p className="mt-1.5 text-[11.5px] leading-relaxed text-tinta3">
        {fraseDoRestante(teto)} Conta só oferta de vaga e aviso de cobrança —{" "}
        <b className="font-medium text-tinta2">
          lembrete de véspera, aviso de desmarque e confirmação de encaixe saem sempre
        </b>
        , em qualquer plano.
      </p>
    </div>
  );
}
