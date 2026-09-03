import {
  nivelDaFaixa,
  fraseDaFaixa,
  fraseDoQueNaoMuda,
  fraseDoConvite,
  fraseDoRestante,
  fraseDoQueConta,
  type Faixa,
} from "@/lib/faixa";

/**
 * O aviso da faixa.
 *
 * Substituiu o `AvisoDoTeto` na OP8, e a diferença entre os dois é a diferença
 * entre um limite e um preço:
 *
 * 1. **Ele não avisa que algo parou, porque nada parou.** A primeira frase
 *    depois do número é a do que continua funcionando — agenda, fila, mensagens
 *    da paciente —, e ela existe porque "você passou do limite" sozinho deixa
 *    a pessoa imaginando o pior, e o pior aqui é exatamente o que não acontece.
 *
 * 2. **Não vira anúncio.** O convite fala do próximo ciclo e não de agora, não
 *    mostra preço e não tem botão de comprar. Há teste reprovando "R$",
 *    "assine agora" e "aproveite" em qualquer das frases.
 *
 * Aparece a partir de 70% e não antes — um aviso que fica o mês inteiro na tela
 * é um aviso que se aprende a não ler. E **nunca** aparece no fair-use do Pro:
 * a página de preços diz que ele não tem faixa, e avisar sobre um limite que a
 * página diz não existir seria a página mentindo numa das duas pontas.
 */
export function AvisoDaFaixa({ faixa }: { faixa: Faixa }) {
  const nivel = nivelDaFaixa(faixa);
  if (nivel === "nenhum") return null;

  const acima = nivel === "acima";

  return (
    <div
      className={
        acima
          ? "mb-5 rounded-cartao border border-aviso-linha bg-aviso-bg px-5 py-4"
          : "mb-5 rounded-cartao border border-linha bg-folha px-5 py-3"
      }
    >
      <p className={`text-[13px] font-medium ${acima ? "text-aviso" : "text-tinta2"}`}>
        {fraseDaFaixa(faixa)}
      </p>

      {acima ? (
        <>
          <p className="mt-1.5 max-w-2xl text-[12.5px] leading-relaxed text-tinta2">
            {fraseDoQueNaoMuda(faixa)}
          </p>
          <p className="mt-1.5 max-w-2xl text-[12.5px] leading-relaxed text-tinta2">
            {fraseDoConvite(faixa)}
          </p>
        </>
      ) : (
        <p className="mt-1 text-[12px] leading-relaxed text-tinta2">
          {fraseDoRestante(faixa)} {fraseDoQueConta()}
        </p>
      )}
    </div>
  );
}

/**
 * A linha na tela da conta, sempre visível quando há faixa.
 *
 * Fica à vista o tempo todo, e não só quando estoura: um plano cujo número só
 * aparece quando morde não é plano, é armadilha. É a mesma regra que valia para
 * o teto que saiu — o que mudou foi o que o número significa.
 */
export function FaixaNaConta({ faixa }: { faixa: Faixa }) {
  if (!faixa.tem_faixa || faixa.e_fair_use) {
    return (
      <p className="text-[12.5px] text-tinta2">
        Seu plano não conta sessões.{" "}
        <span className="text-tinta3">
          As mensagens das suas pacientes saem sem teto, em qualquer plano.
        </span>
      </p>
    );
  }

  const barra = Math.min(100, faixa.pct);

  return (
    <div>
      <div className="flex items-baseline justify-between gap-3">
        <span className="text-[12.5px] text-tinta2">{fraseDaFaixa(faixa)}</span>
        <span className="font-mono text-[11.5px] tabular-nums text-tinta3">{faixa.pct}%</span>
      </div>
      <div className="mt-1.5 h-1.5 overflow-hidden rounded-full bg-folha2">
        <div
          className={`h-full ${faixa.acima ? "bg-aviso" : "bg-cheia"}`}
          style={{ width: `${barra}%` }}
        />
      </div>

      {faixa.profissionais > 1 && (
        <p className="mt-1.5 text-[11.5px] leading-relaxed text-tinta3">
          {faixa.limite} por profissional que atende, e você tem {faixa.profissionais}.
        </p>
      )}

      <p className="mt-1.5 text-[11.5px] leading-relaxed text-tinta3">
        {fraseDoQueConta()}{" "}
        <b className="font-medium text-tinta2">
          Passar desse número não trava nada e não gera cobrança extra
        </b>
        .
      </p>
    </div>
  );
}
