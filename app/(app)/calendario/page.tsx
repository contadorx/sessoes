import Link from "next/link";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { hoje } from "@/lib/tempo-servidor";
import { PainelDoCalendario, TrazerHistorico } from "@/components/app/Calendario";
import type { PainelCalendario } from "@/lib/calendario";

export const metadata = { title: "Calendário" };

type Painel = PainelCalendario & { tem_credencial?: boolean; pendentes_antigas?: number };

export default async function Calendario() {
  const supabase = await supabaseSessao();

  const [bruto, pacientes] = await Promise.all([
    db("calendario.painel", supabase.rpc("calendario_do_profissional")) as Promise<unknown>,
    db(
      "calendario.exemplo",
      supabase.from("pacientes").select("nome").order("nome").limit(1),
    ) as Promise<unknown>,
  ]);

  const painel = (bruto ?? { ligado: false }) as Painel;

  // A prévia do título usa um nome de verdade da base dela. Um "Fulano de Tal"
  // não convence ninguém de nada — ela precisa ver o próprio paciente ali para
  // decidir se aquilo pode aparecer na tela do celular.
  const exemplo =
    ((pacientes ?? []) as { nome: string }[])[0]?.nome ?? "Maria Fernanda de Souza";

  return (
    <div className="mx-auto max-w-3xl">
      <h1 className="font-serif text-[28px] leading-tight tracking-[-0.015em]">
        A agenda que você já tem
      </h1>

      <p className="mt-3 max-w-2xl text-[14px] leading-relaxed text-tinta2">
        Metade das psicólogas vive na Google Agenda. Sem ligar as duas, este sistema{" "}
        <b className="font-semibold text-tinta">mente</b>: mostra a terça das 15h livre porque
        aqui ela está livre, enquanto no seu celular aquela hora é o dentista — e a fila oferece
        a hora para alguém.
      </p>

      <PainelDoCalendario painel={painel} exemplo={exemplo} />

      {/* --------------------------------------------- o que vai e o que vem */}
      <section className="mt-10 border-t border-linha pt-6">
        <h2 className="rotulo">O que sai daqui, e o que entra de lá</h2>
        <ul className="mt-3 max-w-2xl space-y-2 text-[13px] leading-relaxed text-tinta2">
          <li>
            <b className="font-medium text-tinta">O que sai não diz quem.</b> O evento nasce
            escrito só “Sessão”. A Google é um terceiro, e numa clínica de psicologia a lista de
            quem tem hora marcada <i>é</i> a lista de quem faz terapia. Você pode trocar para
            iniciais ou nome completo — mas é escolha sua, e não o padrão.
          </li>
          <li>
            <b className="font-medium text-tinta">O que entra não guarda o quê.</b> Dos seus
            compromissos eu trago o começo e o fim. Não guardo título, convidado, local nem
            descrição: a fila precisa saber que a hora está ocupada, não de quem é o
            compromisso.
          </li>
          <li>
            <b className="font-medium text-tinta">Se eu ficar sem ler, continuo bloqueando.</b>{" "}
            Autorização vencida ou sincronização pausada não liberam as horas que eu já conhecia.
            O erro cai para o lado de oferecer de menos, que custa uma vaga — o outro lado custa
            você chegando numa hora marcada em cima de outra coisa.
          </li>
          <li>
            <b className="font-medium text-tinta">Desconectar não apaga a sua agenda.</b> Os
            eventos que já foram para lá continuam lá. Sumir com duzentos compromissos porque
            você clicou em desconectar seria estrago, não limpeza.
          </li>
        </ul>
      </section>

      {/* ------------------------------------------------------- o histórico */}
      <section className="mt-12 border-t border-linha pt-6">
        <h2 className="font-serif text-[21px] leading-tight">O histórico de outro sistema</h2>
        <p className="mt-2 max-w-2xl text-[14px] leading-relaxed text-tinta2">
          Se você vem de outro lugar — ou de uma planilha —, traga o que já aconteceu. Isso
          preenche a linha do tempo de cada paciente, e é a diferença entre um sistema novo em
          folha e um sistema que sabe que a Maria está com você desde 2023.
        </p>

        <div className="mt-4 rounded-cartao border border-aviso-linha bg-aviso-bg px-5 py-4 text-[13px] leading-relaxed text-aviso">
          <b className="font-semibold">Histórico é memória, não dinheiro.</b> Sessão importada
          não vira cobrança, não entra no faturamento do mês, não aparece em “recebi?” e não
          gera pendência de Receita Saúde. Dois anos de planilha despejariam dezenas de milhares
          de reais em meses já fechados, e o seu carnê-leão passaria a não bater com extrato
          nenhum. O que passou pelo caixa <i>deste</i> sistema é o que ele escritura; o que veio
          de fora veio como memória.
        </div>

        <p className="mt-4 max-w-2xl text-[13px] leading-relaxed text-tinta2">
          Eu não crio paciente por aqui. Uma planilha de dois anos tem o mesmo nome escrito de
          cinco jeitos, e adivinhar partiria o histórico entre duas fichas. Cadastre ou importe
          as pessoas primeiro em{" "}
          <Link href="/comecar" className="underline underline-offset-2 hover:text-vaga">
            Começar
          </Link>{" "}
          — depois volte aqui.
        </p>

        <TrazerHistorico hoje={hoje()} />
      </section>
    </div>
  );
}
