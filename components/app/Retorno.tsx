import { formatar, paraCentavos, somar } from "@/lib/dinheiro";

export type LinhaRetorno = {
  canceladas: number;
  oferecidas: number;
  preenchidas: number;
  taxa: number | null;
  valor_preenchido: string;
  valor_recebido: string;
  valor_em_aberto: string;
  valor_perdoado: string;
  horas_recuperadas: string;
};

/**
 * O painel que prova o ROI — e que precisa ser mais honesto do que vendedor.
 *
 * A tentação é somar tudo num número grande. É também a forma mais rápida de
 * perder a cliente: ela confere contra o extrato, a conta não bate, e a partir
 * daí nenhum número desta tela é acreditado de novo.
 *
 * Então **em aberto** aparece separado e nunca é somado — cobrado não é
 * recebido. E **perdoado** aparece sem alerta e sem cor de aviso: é informação
 * sobre ela mesma, que ela nunca teve como ver, e não uma cobrança disfarçada
 * de estatística.
 */
export function Retorno({ r, rotulo }: { r: LinhaRetorno; rotulo: string }) {
  const preenchido = paraCentavos(r.valor_preenchido ?? "0");
  const recebido = paraCentavos(r.valor_recebido ?? "0");
  const emAberto = paraCentavos(r.valor_em_aberto ?? "0");
  const perdoado = paraCentavos(r.valor_perdoado ?? "0");
  const horas = Number(r.horas_recuperadas ?? 0);

  const total = somar(preenchido, recebido);

  if (r.canceladas === 0 && total === 0) {
    return (
      <section className="rounded-cartao border border-linha bg-folha2 px-5 py-4">
        <h2 className="rotulo">Retorno · {rotulo}</h2>
        <p className="mt-2 text-[13px] leading-relaxed text-tinta2">
          Nenhum cancelamento no período. Quando houver, é aqui que aparece o que
          a fila recuperou — e o que ficou pelo caminho.
        </p>
      </section>
    );
  }

  return (
    <section className="rounded-cartao border border-linha bg-folha2 px-5 py-4">
      <h2 className="rotulo">Retorno · {rotulo}</h2>

      <p className="mt-2 font-serif text-[26px] leading-none tracking-[-0.02em] text-cheia">
        {formatar(total)}
      </p>
      <p className="mt-1 text-[12.5px] leading-relaxed text-tinta2">
        que não teria entrado sem a fila e sem a política.
        {horas > 0 && (
          <> São {horas.toFixed(1).replace(".", ",")} horas que estariam vazias.</>
        )}
      </p>

      <dl className="mt-4 grid grid-cols-2 gap-x-4 gap-y-3 sm:grid-cols-4">
        <Numero
          rotulo="vagas preenchidas"
          valor={`${r.preenchidas}/${r.canceladas}`}
          nota={r.taxa !== null ? `${r.taxa}% oferecidas` : undefined}
        />
        <Numero rotulo="horário recuperado" valor={formatar(preenchido)} />
        <Numero rotulo="cobrança recebida" valor={formatar(recebido)} />
        <Numero
          rotulo="cobrado, ainda não pago"
          valor={formatar(emAberto)}
          apagado
          nota="não entra na soma"
        />
      </dl>

      {perdoado > 0 && (
        <p className="mt-4 border-t border-linha pt-3 text-[12.5px] leading-relaxed text-tinta2">
          Você abriu mão de <b className="font-medium text-tinta">{formatar(perdoado)}</b>{" "}
          no período. Está aqui só para você saber — decidir não cobrar continua
          sendo sua.
        </p>
      )}
    </section>
  );
}

function Numero({
  rotulo,
  valor,
  nota,
  apagado,
}: {
  rotulo: string;
  valor: string;
  nota?: string;
  apagado?: boolean;
}) {
  return (
    <div>
      <dt className="text-[10.5px] font-semibold uppercase tracking-wider text-tinta3">
        {rotulo}
      </dt>
      <dd
        className={`mt-0.5 font-mono text-[15px] tabular-nums ${
          apagado ? "text-tinta3" : "text-tinta"
        }`}
      >
        {valor}
      </dd>
      {nota && <p className="text-[11px] text-tinta3">{nota}</p>}
    </div>
  );
}
