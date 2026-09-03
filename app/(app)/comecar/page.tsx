import Link from "next/link";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { sessaoAtual } from "@/lib/conta";
import { Importar } from "@/components/app/Importar";
import { duracao } from "@/lib/capacidade";
import { faltando, feito } from "@/lib/comecar";
import { envioAutomaticoLigado } from "@/lib/promessa";

export const metadata = { title: "Começar" };

export type EstadoInicial = {
  pacientes: number;
  enquadres: number;
  sessoes: number;
  na_fila: number;
  com_canal: number;
  politica_definida: boolean;
  vagas_abertas: number;
  preenchidas: number;
  janelas: number;
  semana_min: number;
};

export async function estadoInicial(): Promise<EstadoInicial> {
  const supabase = await supabaseSessao();
  return (await db(
    "onboarding.estado",
    supabase.rpc("estado_inicial"),
  )) as unknown as EstadoInicial;
}

function Passo({
  n,
  titulo,
  feito,
  children,
}: {
  n: number;
  titulo: string;
  feito: boolean;
  children: React.ReactNode;
}) {
  return (
    <li className="grid grid-cols-[2rem_1fr] gap-x-4">
      <span
        className={`flex h-8 w-8 items-center justify-center rounded-full border font-mono text-[12px] ${
          feito
            ? "border-cheia-linha bg-cheia-bg text-cheia"
            : "border-linha2 bg-folha text-tinta3"
        }`}
        aria-hidden
      >
        {feito ? "✓" : n}
      </span>

      <div className="min-w-0 pb-8">
        <h2
          className={`text-[15px] font-semibold ${feito ? "text-tinta3" : "text-tinta"}`}
        >
          {titulo}
        </h2>
        <div className="mt-1.5 text-[13px] leading-relaxed text-tinta2">{children}</div>
      </div>
    </li>
  );
}

export default async function Comecar() {
  const [sessao, estado] = await Promise.all([sessaoAtual(), estadoInicial()]);

  // Os passos e o que falta saem de `lib/comecar.ts` — o mesmo módulo que a
  // faixa da agenda consulta. Enquanto eram duas contas, uma tela dizia três
  // passos e a outra se chamava "cinco passos".
  const temHoras = feito(estado, "horas");
  const temGente = feito(estado, "pessoas");
  const temFila = feito(estado, "fila");
  const faltam = faltando(estado);
  const automatico = envioAutomaticoLigado();

  return (
    <div className="mx-auto max-w-2xl">
      <h1 className="font-serif text-[28px] leading-tight tracking-[-0.015em]">
        {sessao.nome ? `${sessao.nome.split(" ")[0]}, ` : ""}três passos
      </h1>
      <p className="mt-2 max-w-xl text-[14px] leading-relaxed text-tinta2">
        No fim deles, quando alguém desmarcar, o horário vago é oferecido a quem
        está esperando{automatico ? ", uma pessoa por vez" : " — a oferta nasce escrita e sai do seu WhatsApp"}.
        Nenhum passo se marca à mão: cada um pergunta ao sistema como as coisas
        estão de verdade.
      </p>

      <ol className="mt-8">
        {/* ---------------------------------------------------------- o passo 1

            Ele é o primeiro porque é o **denominador**: sem saber quantas horas
            ela decide disponibilizar, nenhum número do produto tem com o que
            ser comparado — e "quanto da sua capacidade virou receita" fica sem
            resposta possível.

            E porque é a única pergunta desta lista que o sistema **não tem como
            adivinhar**. Paciente, horário e fila ele infere da planilha que ela
            colar; a decisão de quanto trabalhar é dela, e só ela sabe. */}
        <Passo n={1} titulo="Declare quantas horas você disponibiliza" feito={temHoras}>
          {temHoras ? (
            <p>
              {duracao(estado.semana_min)} por semana em {estado.janelas} faixa
              {estado.janelas > 1 ? "s" : ""}, contando o tempo de registro e de
              descanso.{" "}
              <Link href="/perfil/horarios" className="toque text-vaga hover:underline">
                revisar
              </Link>
            </p>
          ) : (
            <p>
              Quantas horas por semana você <b className="text-tinta">decide</b>{" "}
              disponibilizar, e para quê — atender, escrever prontuário,
              descansar. As três são horas de trabalho, e o sistema precisa saber
              disso para não tratar as duas últimas como buraco na agenda.{" "}
              <Link href="/perfil/horarios" className="toque text-vaga hover:underline">
                declarar a semana
              </Link>
            </p>
          )}
        </Passo>

        {/* ---------------------------------------------------------- o passo 2

            Aqui moravam dois passos. O segundo — "confira o combinado de cada
            uma" — se dava por feito com `enquadres > 0`, que é o que a
            importação deste aqui produz: ela nunca conferia valor nem política,
            e a tela dizia que tinha conferido. Um passo sem sinal próprio não é
            passo; é uma caixa que se marca sozinha.

            O que ele pedia continua pedido, como frase: conferir dia, hora,
            valor e política é trabalho de verdade, e o link para fazê-lo está
            no estado concluído, que é quando ela tem o que conferir. */}
        <Passo n={2} titulo="Traga sua agenda" feito={temGente}>
          {temGente ? (
            <>
              <p>
                {estado.pacientes} pessoa{estado.pacientes > 1 ? "s" : ""} no
                cadastro, {estado.enquadres} com horário fixo
                {estado.sessoes > 0
                  ? `, ${estado.sessoes} sessões já marcadas nas próximas semanas`
                  : ""}
                .
              </p>
              <p className="mt-1.5">
                Vale abrir uma a uma e conferir dia, hora, valor e a política de
                cancelamento — é a política de cada combinado que decide, sozinha,
                o que conta como cancelamento em cima da hora.{" "}
                <Link href="/pacientes" className="toque text-vaga hover:underline">
                  abrir os cadastros
                </Link>
              </p>
            </>
          ) : (
            <>
              <p>
                Cole a lista que você já tem — de uma planilha, da caderneta, do
                WhatsApp. Uma pessoa por linha; só o nome é obrigatório.
              </p>
              <div className="mt-3">
                <Importar />
              </div>
              {/* Quem tem seis pacientes na cabeça não tem lista para colar, e
                  esta tela só oferecia a colagem. Uma linha resolve. */}
              <p className="mt-3 text-[12.5px]">
                Sem lista à mão?{" "}
                <Link href="/pacientes/novo" className="toque text-vaga hover:underline">
                  cadastre uma pessoa por vez
                </Link>
              </p>
            </>
          )}
        </Passo>

        <Passo n={3} titulo="Monte a lista de espera" feito={temFila}>
          {temFila ? (
            <p>
              {estado.na_fila} pessoa{estado.na_fila > 1 ? "s" : ""} esperando
              encaixe.{" "}
              <Link href="/encaixes" className="toque text-vaga hover:underline">
                ver a fila
              </Link>
            </p>
          ) : (
            <p>
              Quem topa entrar num horário que vagar — com a janela de cada um
              (&ldquo;terça ou quarta, depois das 13h&rdquo;). Sem ninguém aqui, um
              cancelamento continua sendo só um buraco.{" "}
              <Link href="/encaixes" className="toque text-vaga hover:underline">
                montar a fila
              </Link>
            </p>
          )}
        </Passo>
      </ol>

      {/* ------------------------------------------------------ o que era o 5

          "Deixe a cascata correr" era uma caixa a marcar, com `vagas_abertas > 0`
          por sinal — quer dizer, ela só se marcava quando **uma paciente
          desmarcasse de verdade**. Não havia ação nenhuma nesta tela para dar
          esse passo. É a frase que fecha a página. */}
      <div className="border-t border-linha pt-5">
        {faltam.length === 0 ? (
          <p className="text-[13.5px] leading-relaxed text-tinta2">
            Está tudo de pé. Da próxima vez que alguém desmarcar, você abre a vaga
            em cascata: {automatico ? "a oferta vai" : "a oferta nasce escrita e você manda"} para
            uma pessoa por vez, na ordem de quem está há mais tempo sem sessão, e
            a próxima só é chamada depois que a anterior responde ou o prazo dela
            vence.{" "}
            {estado.vagas_abertas > 0 && (
              <>
                Até agora foram {estado.vagas_abertas} vaga
                {estado.vagas_abertas > 1 ? "s" : ""} oferecida
                {estado.vagas_abertas > 1 ? "s" : ""} e {estado.preenchidas}{" "}
                preenchida{estado.preenchidas === 1 ? "" : "s"}.{" "}
              </>
            )}
            <Link href="/agenda" className="toque text-vaga hover:underline">
              voltar para a agenda
            </Link>
          </p>
        ) : (
          <p className="text-[13.5px] leading-relaxed text-tinta2">
            Feitos os três, a cascata passa a correr sozinha quando alguém
            desmarcar: uma pessoa por vez, na ordem de quem está há mais tempo sem
            sessão, esperando a resposta antes de passar adiante.
          </p>
        )}

        {estado.com_canal === 0 && estado.pacientes > 0 && (
          <p className="mt-3 text-[13px] leading-relaxed text-aviso">
            Ninguém tem telefone cadastrado ainda — sem isso dá para ver a fila na
            tela, mas não avisar ninguém.
          </p>
        )}

        {!automatico && (
          <p className="mt-3 text-[12.5px] leading-relaxed text-tinta3">
            O envio automático ainda não está ligado: as mensagens de todos os
            planos nascem escritas e saem do seu WhatsApp, com um toque seu. A
            cascata, a fila e a cobrança não dependem disso.
          </p>
        )}
      </div>
    </div>
  );
}
