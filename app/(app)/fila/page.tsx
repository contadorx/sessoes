import Link from "next/link";
import {
  filaDaConta,
  foraDaFila,
  vagasAbertas,
  regrasDaConta,
  taxaDePreenchimento,
} from "./dados";
import { EditorFila } from "@/components/app/EditorFila";
import { RegrasDaFila } from "@/components/app/RegrasDaFila";
import { formatar, paraCentavos } from "@/lib/dinheiro";
import { somarDias } from "@/lib/semana";
import { hoje } from "@/lib/tempo-servidor";

export const metadata = { title: "Fila" };

const QUANDO = new Intl.DateTimeFormat("pt-BR", {
  timeZone: "America/Sao_Paulo",
  weekday: "short",
  day: "numeric",
  month: "short",
  hour: "2-digit",
  minute: "2-digit",
});

export default async function Fila() {
  const hojeStr = hoje();

  const [fila, candidatos, vagas, regras, metrica] = await Promise.all([
    filaDaConta(),
    foraDaFila(),
    vagasAbertas(),
    regrasDaConta(),
    taxaDePreenchimento(somarDias(hojeStr, -30), hojeStr),
  ]);

  const semOferta = vagas.filter((v) => v.ofertas === 0);

  return (
    <div>
      <h1 className="font-serif text-[28px] leading-tight tracking-[-0.015em]">A fila</h1>
      <p className="mt-2 max-w-[70ch] text-[14px] leading-relaxed text-tinta2">
        Quando um horário vaga, a fila oferece para uma pessoa por vez, na ordem
        que você definiu, e passa para a próxima se ninguém responder. Você não
        pede nada a ninguém.
      </p>

      {/* a métrica que decide o produto */}
      <dl className="mt-5 grid gap-px overflow-hidden rounded-cartao border border-linha bg-linha sm:grid-cols-4">
        <Numero rotulo="na fila" valor={String(fila.filter((f) => f.ativo).length)} />
        <Numero
          rotulo="vagas abertas"
          valor={String(vagas.filter((v) => !v.preenchida).length)}
          cor={semOferta.length > 0 ? "text-vaga" : undefined}
        />
        <Numero rotulo="preenchidas em 30 dias" valor={String(metrica.preenchidas)} cor="text-cheia" />
        <Numero
          rotulo="cancelamentos com oferta"
          valor={metrica.taxa === null ? "—" : `${metrica.taxa}%`}
          cor={
            metrica.taxa === null
              ? undefined
              : Number(metrica.taxa) >= 60
                ? "text-cheia"
                : "text-vaga"
          }
          nota="a meta é 60% — abaixo disso o produto não se justifica"
        />
      </dl>

      {/* as vagas esperando */}
      {vagas.length > 0 && (
        <section className="mt-8">
          <h2 className="rotulo">Horários vagos</h2>
          <ul className="mt-2 overflow-hidden rounded-cartao border border-linha bg-folha">
            {vagas.map((v) => (
              <li key={v.id} className="border-t border-linha first:border-t-0">
                <Link
                  href={`/fila/${v.id}`}
                  className="flex flex-wrap items-baseline gap-x-4 gap-y-1 px-5 py-3 transition-colors hover:bg-folha2"
                >
                  <span className="font-mono text-[13px] tabular text-tinta2">
                    {QUANDO.format(new Date(v.inicio))}
                  </span>
                  <span className="text-[13px] text-tinta3">
                    era de {v.pacientes?.nome ?? "—"}
                  </span>
                  {v.preenchida ? (
                    <span className="text-[11.5px] font-semibold text-cheia">✓ preenchida</span>
                  ) : v.ofertas > 0 ? (
                    <span className="text-[11.5px] font-semibold text-aviso">
                      {v.ofertas} oferta{v.ofertas > 1 ? "s" : ""} · em andamento
                    </span>
                  ) : (
                    <span className="text-[11.5px] font-semibold text-vaga">
                      ninguém foi avisado
                    </span>
                  )}
                  <span
                    className={`ml-auto font-mono text-[12.5px] tabular ${
                      v.preenchida ? "text-cheia" : "text-vaga"
                    }`}
                  >
                    {formatar(paraCentavos(v.valor))}
                  </span>
                </Link>
              </li>
            ))}
          </ul>
          {semOferta.length > 0 && (
            <p className="mt-2 text-[12px] text-vaga">
              {semOferta.length === 1
                ? "Um horário vago sem ninguém avisado."
                : `${semOferta.length} horários vagos sem ninguém avisado.`}{" "}
              Cada um deles é dinheiro parado.
            </p>
          )}
        </section>
      )}

      <div className="mt-10">
        <EditorFila fila={fila} candidatos={candidatos} />
      </div>

      <div className="mt-10">
        <RegrasDaFila regras={regras} />
      </div>
    </div>
  );
}

function Numero({
  rotulo,
  valor,
  cor = "text-tinta",
  nota,
}: {
  rotulo: string;
  valor: string;
  cor?: string;
  nota?: string;
}) {
  return (
    <div className="bg-folha px-5 py-4">
      <dt className="rotulo">{rotulo}</dt>
      <dd>
        <span className={`tabular mt-1 block font-mono text-[24px] font-medium leading-none ${cor}`}>
          {valor}
        </span>
        {nota && <span className="mt-1.5 block text-[11px] leading-relaxed text-tinta3">{nota}</span>}
      </dd>
    </div>
  );
}
