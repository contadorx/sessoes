import fs from "node:fs";
import path from "node:path";
import Image from "next/image";

/**
 * A prova de que existe software.
 *
 * A segunda auditoria fez a pergunta que nenhuma figura desta página responde:
 * *"isto é um produto usável ou ainda um conceito?"*. Os desenhos explicam a
 * tese — e explicam bem, é o que a auditoria mesma reconhece —, mas um desenho
 * a mais não responde essa pergunta. Só a tela responde.
 *
 * POR QUE A SEÇÃO É CONDICIONAL, E NÃO UM `<img>` FIXO
 *
 * As capturas precisam ser feitas da conta de demonstração rodando de verdade
 * (as instruções estão em `public/telas/LEIA-ME.md`), e enquanto elas não
 * existem a página **não pode** ter uma seção com moldura vazia, `alt` sem
 * imagem ou um "em breve". Isso seria a mesma promessa não cumprida que a
 * auditoria encontrou no funil.
 *
 * Então o servidor confere quais arquivos existem e monta a seção com o que
 * encontrar. Nenhum arquivo, nenhuma seção — a página continua íntegra, só sem
 * esta prova. Um arquivo, a seção nasce com um. É a mesma regra que a faixa de
 * pendências do aplicativo segue: **o que não tem conteúdo não ocupa espaço.**
 *
 * A LEITURA DE DISCO ACONTECE NO BUILD
 *
 * Esta página é estática. `existsSync` roda uma vez, na hora de gerar o HTML —
 * não a cada visita. Trocar uma captura exige um novo deploy, o que é correto:
 * a imagem faz parte do que a página afirma, e afirmação nova se publica.
 *
 * O QUE AS CAPTURAS NÃO PODEM TER
 *
 * Nome de paciente. A conta de demonstração foi semeada com iniciais, e o
 * LEIA-ME repete o aviso, porque uma landing com nome de paciente numa
 * captura seria, ela própria, o vazamento que a seção do sigilo promete que
 * não acontece.
 */

type Tela = {
  arquivo: string;
  titulo: string;
  legenda: string;
  largura: number;
  altura: number;
};

/** A ordem é a do dia de trabalho: o que vem, o que se registra, o que entra. */
const TELAS: Tela[] = [
  {
    arquivo: "agenda.png",
    titulo: "A semana",
    legenda:
      "Cada horário mostra em que estado está — confirmado, atendido, pago, a receber — sem você abrir nada.",
    largura: 1280,
    altura: 800,
  },
  {
    arquivo: "sessao.png",
    titulo: "A sessão por dentro",
    legenda:
      "Registrar o que aconteceu, ver cobrança e pagamento, emitir documento: tudo no painel da própria sessão.",
    largura: 1280,
    altura: 800,
  },
  {
    arquivo: "recebimentos.png",
    titulo: "O que ficou a receber",
    legenda:
      "A lista existe para você olhar só as divergências — não para conferir o extrato inteiro.",
    largura: 1280,
    altura: 800,
  },
];

function existentes(): Tela[] {
  const dir = path.join(process.cwd(), "public", "telas");
  return TELAS.filter((t) => {
    try {
      return fs.existsSync(path.join(dir, t.arquivo));
    } catch {
      return false;
    }
  });
}

export function Telas() {
  const telas = existentes();
  if (telas.length === 0) return null;

  return (
    <section
      id="telas"
      className="scroll-mt-16 border-t border-linha bg-folha2"
    >
      <div className="mx-auto max-w-5xl px-5 py-12 sm:px-8 sm:py-16">
        <p className="rotulo">O produto</p>
        <h2 className="mt-2 max-w-[26ch] font-serif text-[26px] leading-tight tracking-[-0.015em] text-balance sm:text-[34px]">
          Veja o Sessões funcionando.
        </h2>
        <p className="mt-4 max-w-[62ch] text-[14.5px] leading-relaxed text-tinta2">
          Telas do sistema no ar, capturadas de uma conta de demonstração. Os
          nomes são iniciais: nem numa imagem de divulgação um paciente
          aparece.
        </p>

        <div
          className={`mt-10 grid gap-6 ${
            telas.length === 1 ? "" : "lg:grid-cols-2"
          }`}
        >
          {telas.map((t, i) => (
            <figure
              key={t.arquivo}
              /* A primeira ocupa a largura toda quando há três: uma grade de
                 dois com três itens deixa um buraco, e o buraco chama mais
                 atenção que a terceira imagem. */
              className={`overflow-hidden rounded-cartao border border-linha bg-folha ${
                telas.length === 3 && i === 0 ? "lg:col-span-2" : ""
              }`}
            >
              <Image
                src={`/telas/${t.arquivo}`}
                alt={t.legenda}
                width={t.largura}
                height={t.altura}
                className="h-auto w-full border-b border-linha"
                sizes="(min-width: 1024px) 640px, 100vw"
              />
              <figcaption className="px-4 py-3.5">
                <span className="block text-[13.5px] font-medium text-tinta">
                  {t.titulo}
                </span>
                <span className="mt-1 block text-[12.5px] leading-relaxed text-tinta3">
                  {t.legenda}
                </span>
              </figcaption>
            </figure>
          ))}
        </div>
      </div>
    </section>
  );
}
