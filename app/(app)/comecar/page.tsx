import Link from "next/link";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { sessaoAtual } from "@/lib/conta";
import { Importar } from "@/components/app/Importar";

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

  const temGente = estado.pacientes > 0;
  const temHorario = estado.enquadres > 0;
  const temFila = estado.na_fila > 0;
  const jaRodou = estado.vagas_abertas > 0;

  return (
    <div className="mx-auto max-w-2xl">
      <h1 className="font-serif text-[28px] leading-tight tracking-[-0.015em]">
        {sessao.nome ? `${sessao.nome.split(" ")[0]}, ` : ""}quatro passos
      </h1>
      <p className="mt-2 max-w-xl text-[14px] leading-relaxed text-tinta2">
        No fim deles, a próxima vez que alguém desmarcar, o horário é oferecido
        sozinho para quem está esperando. Nenhum passo se marca à mão — cada um
        pergunta ao sistema como as coisas estão de verdade.
      </p>

      <ol className="mt-8">
        <Passo n={1} titulo="Traga sua agenda" feito={temGente}>
          {temGente ? (
            <p>
              {estado.pacientes} pessoa{estado.pacientes > 1 ? "s" : ""} no
              cadastro, {estado.enquadres} com horário fixo.{" "}
              <Link href="/pacientes" className="text-vaga hover:underline">
                ver
              </Link>
            </p>
          ) : (
            <>
              <p>
                Cole a lista que você já tem — de uma planilha, da caderneta, do
                WhatsApp. Uma pessoa por linha; só o nome é obrigatório.
              </p>
              <div className="mt-3">
                <Importar />
              </div>
            </>
          )}
        </Passo>

        <Passo n={2} titulo="Confira o combinado de cada uma" feito={temHorario}>
          {temHorario ? (
            <p>
              {estado.enquadres} horário{estado.enquadres > 1 ? "s" : ""} fixo
              {estado.enquadres > 1 ? "s" : ""} valendo, e{" "}
              {estado.sessoes > 0
                ? `${estado.sessoes} sessões já marcadas nas próximas semanas.`
                : "a agenda das próximas semanas montada a partir deles."}
            </p>
          ) : (
            <p>
              Dia, hora, valor e a política de cancelamento. É esse combinado que
              vira agenda — e é a política dele que decide, sozinha, o que é
              cancelamento em cima da hora.{" "}
              <Link href="/pacientes" className="text-vaga hover:underline">
                abrir os cadastros
              </Link>
            </p>
          )}
        </Passo>

        <Passo n={3} titulo="Monte a lista de espera" feito={temFila}>
          {temFila ? (
            <p>
              {estado.na_fila} pessoa{estado.na_fila > 1 ? "s" : ""} esperando
              encaixe.{" "}
              <Link href="/fila" className="text-vaga hover:underline">
                ver a fila
              </Link>
            </p>
          ) : (
            <p>
              Quem topa entrar num horário que vagar — com a janela de cada um
              (&ldquo;terça ou quarta, depois das 13h&rdquo;). Sem ninguém aqui, um
              cancelamento continua sendo só um buraco.{" "}
              <Link href="/fila" className="text-vaga hover:underline">
                montar a fila
              </Link>
            </p>
          )}
        </Passo>

        <Passo n={4} titulo="Deixe a cascata correr" feito={jaRodou}>
          {jaRodou ? (
            <p>
              {estado.vagas_abertas} vaga{estado.vagas_abertas > 1 ? "s" : ""}{" "}
              oferecida{estado.vagas_abertas > 1 ? "s" : ""},{" "}
              {estado.preenchidas} preenchida{estado.preenchidas === 1 ? "" : "s"}.{" "}
              <Link href="/agenda" className="text-vaga hover:underline">
                seus números
              </Link>
            </p>
          ) : (
            <p>
              Da próxima vez que alguém desmarcar, abra a vaga em cascata: o
              sistema oferece para uma pessoa por vez, na ordem de quem está há
              mais tempo sem sessão, e espera a resposta antes de passar adiante.
              {estado.com_canal === 0 && (
                <>
                  {" "}
                  <b className="text-tinta">
                    Ninguém tem telefone cadastrado ainda
                  </b>{" "}
                  — sem isso, dá para ver a fila na tela, mas não avisar ninguém.
                </>
              )}
            </p>
          )}
        </Passo>
      </ol>

      <p className="mt-2 border-t border-linha pt-5 text-[12.5px] leading-relaxed text-tinta3">
        Enquanto o WhatsApp não estiver ligado, tudo aqui funciona igual — as
        mensagens são preparadas e ficam registradas, só não saem. A cascata, a
        fila e a cobrança não dependem disso.
      </p>
    </div>
  );
}
