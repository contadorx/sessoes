import Link from "next/link";
import {
  filaDaConta,
  foraDaFila,
  vagasAbertas,
  regrasDaConta,
  taxaDePreenchimento,
  faixaDaConta,
} from "./dados";
import { AvisoDaFaixa } from "@/components/app/Faixa";
import { EditorFila } from "@/components/app/EditorFila";
import { RegrasDaFila } from "@/components/app/RegrasDaFila";
import { formatar, paraCentavos } from "@/lib/dinheiro";
import { somarDias } from "@/lib/semana";
import { hoje } from "@/lib/tempo-servidor";
import { fraseDaFilaOferece } from "@/lib/canal";
import { envioAutomaticoLigado } from "@/lib/promessa";

export const metadata = { title: "Encaixes" };

const QUANDO = new Intl.DateTimeFormat("pt-BR", {
  timeZone: "America/Sao_Paulo",
  weekday: "short",
  day: "numeric",
  month: "short",
  hour: "2-digit",
  minute: "2-digit",
});

export default async function Encaixes({
  searchParams,
}: {
  searchParams: Promise<{ novo?: string }>;
}) {
  const { novo } = await searchParams;
  const hojeStr = hoje();

  const [fila, candidatos, vagas, regras, metrica, faixa] = await Promise.all([
    filaDaConta(),
    foraDaFila(),
    vagasAbertas(),
    regrasDaConta(),
    taxaDePreenchimento(somarDias(hojeStr, -30), hojeStr),
    faixaDaConta(),
  ]);

  const semOferta = vagas.filter((v) => v.ofertas === 0);

  /*
    A tela ainda não aconteceu.

    Numa conta nova a faixa mostrava `0 · 0 · 0 · —` sem dizer que zero é o
    esperado, e quatro zeros lidos de primeira parecem quatro fracassos. O
    modelo é o estado vazio de `/pacientes`, que é o melhor do produto: diz o
    que a tela vai mostrar quando existir, e oferece o próximo passo.

    A condição é estrita de propósito — **nada** aconteceu ainda: fila vazia,
    nenhum horário jamais vago, nenhum preenchimento em 30 dias. Basta uma
    dessas três existir e os números voltam inteiros, zeros incluídos. Esconder
    um zero que significa alguma coisa seria "o filtro que esconde o
    inconveniente", e ele é antipadrão nomeado aqui.
  */
  const nadaAconteceu =
    fila.length === 0 && vagas.length === 0 && metrica.preenchidas === 0;

  return (
    <div>
      <h1 className="font-serif text-[28px] leading-tight tracking-[-0.015em]">A fila</h1>
      {/* A frase vem de `fraseDaFilaOferece`, e não do teclado: enquanto não há
          provedor, "Você não pede nada a ninguém" é falso — a mensagem sai do
          WhatsApp dela, com um toque. Ver o comentário da função. */}
      <p className="mt-2 max-w-[70ch] text-[14px] leading-relaxed text-tinta2">
        {fraseDaFilaOferece(envioAutomaticoLigado())}
      </p>

      {/* A faixa de sessões substituiu o teto de mensagens aqui na OP8, e o
          sentido do bloco mudou junto. O teto avisava que a fila ia parar; a
          faixa não para nada — ela diz o preço. Continua nesta tela porque é a
          tela em que o volume do mês aparece, e não numa aba de cobrança:
          quem olha a fila está olhando quantas sessões o mês teve. */}
      <div className="mt-5">
        <AvisoDaFaixa faixa={faixa} />
      </div>

      {nadaAconteceu ? (
        <div className="mt-6 rounded-cartao border border-dashed border-linha2 bg-folha px-6 py-10 text-center">
          <p className="font-serif text-[20px] text-tinta">A fila ainda está vazia.</p>
          <p className="mx-auto mt-2 max-w-[52ch] text-[13.5px] leading-relaxed text-tinta2">
            Enquanto ninguém estiver esperando encaixe, um cancelamento continua
            sendo só um buraco na agenda. Os números desta tela — quem está
            esperando, quais horários vagaram e quantos foram preenchidos —
            começam a existir a partir da primeira pessoa aqui.
          </p>
        </div>
      ) : (
      <>
      {/* a métrica que decide o produto */}
      <dl className="mt-5 grid gap-px overflow-hidden rounded-cartao border border-linha bg-linha sm:grid-cols-4">
        <Numero rotulo="na fila" valor={String(fila.filter((f) => f.ativo).length)} />
        <Numero
          rotulo="vagas abertas"
          valor={String(vagas.filter((v) => !v.preenchida).length)}
          cor={semOferta.length > 0 ? "text-vaga" : undefined}
        />
        <Numero rotulo="preenchidas em 30 dias" valor={String(metrica.preenchidas)} />
        {/*
          O número fica; a meta sai, e a cor junto.

          Estava escrito aqui "a meta é 60% — abaixo disso o produto não se
          justifica", em verde acima de 60% e vermelho abaixo. A regra 3 de
          `lib/risco.ts` proíbe isso com todas as letras: *"não existe meta, e
          nada elogia... nenhuma cor que melhore com o número subindo"*. E a
          verificação do P5 existia — só olhava o cockpit, e esta tela é outra.

          A meta era minha, não dela. "Abaixo disso o produto não se justifica"
          é uma frase sobre o meu negócio, pintada de vermelho na tela de quem
          está tentando preencher um horário — e o número já é o dela, sem
          precisar de juízo em cima.
        */}
        <Numero
          rotulo="cancelamentos com oferta"
          valor={metrica.taxa === null ? "—" : `${metrica.taxa}%`}
          nota="quantos dos horários que abriram chegaram a ser oferecidos"
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
                  href={`/encaixes/${v.id}`}
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
      </>
      )}

      <div className="mt-10">
        <EditorFila
          fila={fila}
          candidatos={candidatos}
          abrirDeInicio={novo === "pedido"}
        />
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
