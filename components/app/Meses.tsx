import Link from "next/link";
import {
  nomeDoMes,
  marcasDoMes,
  marcaDoRecibo,
  fraseDoReciboGuardado,
  type LinhaDoMes,
} from "@/lib/meses";

/**
 * A linha do mês — o mesmo componente na tela dela e na página do paciente.
 *
 * **É de propósito que seja um só.** O §5.4 da estratégia do canal pede a mesma
 * linha, com as mesmas marcas, na mesma ordem e com as mesmas palavras, nos
 * dois lugares — e a maneira de garantir isso não é combinar, é não ter dois.
 * Precedente da casa: `Imprimir` também mora em `components/app/` e é desenhado
 * na página pública do documento; um componente sem estado, sem contexto e sem
 * sessão não pertence a uma área.
 *
 * O que muda entre os dois lados é uma coisa só, e ela vem por prop: **para
 * onde o recibo abre**. Ela abre pela ficha, com a RLS da conta; ele abre pelo
 * link, e só dentro da janela de 90 dias que `documento_do_link` exige. Quando
 * não há para onde abrir, a marca continua aparecendo — o recibo existe, e
 * esconder isso faria a pessoa achar que ele nunca foi emitido.
 */
export function Meses({
  linhas,
  comJanela,
  linkDoRecibo,
}: {
  linhas: LinhaDoMes[];
  /** `true` na página do paciente. Ver `marcaDoRecibo`. */
  comJanela: boolean;
  linkDoRecibo?: (l: LinhaDoMes) => string | null;
}) {
  if (linhas.length === 0) return null;

  const algumGuardado = linhas.some((l) => marcaDoRecibo(l, comJanela) === "guardado");

  return (
    <div className="mt-3 flex flex-col gap-2">
      {linhas.map((l) => {
        const marcas = marcasDoMes(l, comJanela);
        const href =
          marcaDoRecibo(l, comJanela) === "disponivel" ? (linkDoRecibo?.(l) ?? null) : null;

        return (
          <div
            key={l.competencia}
            className="rounded-cartao border border-linha bg-folha px-5 py-4"
          >
            <div className="flex items-baseline justify-between gap-3">
              <p className="text-[14.5px] text-tinta first-letter:uppercase">
                {nomeDoMes(l.competencia)}
              </p>
              {href && (
                <Link
                  href={href}
                  className="shrink-0 text-[12.5px] font-medium text-vaga underline decoration-linha2 underline-offset-4"
                >
                  abrir o recibo
                </Link>
              )}
            </div>

            {/* As três marcas, na ordem do §5.4. Nenhuma frase é escrita aqui:
                rótulo e texto vêm de `marcasDoMes`, que é a mesma função dos
                dois lados. */}
            <dl className="mt-2 grid gap-x-5 gap-y-1 sm:grid-cols-3">
              {marcas.map((m) => (
                <div key={m.chave}>
                  <dt className="text-[11px] uppercase tracking-wider text-tinta3">
                    {m.rotulo}
                  </dt>
                  <dd className="mt-0.5 text-[13px] text-tinta2">{m.texto}</dd>
                </div>
              ))}
            </dl>
          </div>
        );
      })}

      {comJanela && algumGuardado && (
        <p className="mt-1 text-[12px] leading-relaxed text-tinta3">
          {fraseDoReciboGuardado()}
        </p>
      )}
    </div>
  );
}
