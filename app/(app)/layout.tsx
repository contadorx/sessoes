import Link from "next/link";
import { Marca } from "@/components/site/Marca";
import { sessaoAtual } from "@/lib/conta";
import { Sair } from "@/components/app/Sair";
import { estadoInicial } from "./comecar/page";
import { Instalar } from "@/components/app/Instalar";
import { alarmeFiscal } from "./receita-saude/alarme";

export default async function LayoutApp({ children }: { children: React.ReactNode }) {
  // Redireciona sozinha se não houver sessão. O middleware já barrou antes —
  // esta é a segunda porta, e a RLS no banco é a terceira e definitiva.
  const sessao = await sessaoAtual();

  // O "Começar" só existe enquanto faz falta. Um item de menu que aponta para
  // uma lista toda marcada é entulho — e some sozinho quando a primeira vaga é
  // oferecida.
  const estado = await estadoInicial();
  const comecando = estado.pacientes === 0 || estado.na_fila === 0 || estado.vagas_abertas === 0;

  // O alarme de fevereiro mora no menu, e não numa tela que ela pode passar
  // meses sem abrir: um alarme que só toca dentro da sala não é alarme.
  const fiscal = await alarmeFiscal();

  return (
    <div className="min-h-dvh">
      <header className="sticky top-0 z-20 border-b border-linha bg-folha">
        <div className="mx-auto flex max-w-6xl flex-wrap items-baseline gap-x-4 gap-y-1 px-5 py-3 sm:px-8">
          <Link href="/agenda">
            <Marca className="text-[20px]" />
          </Link>
          <span className="text-[12px] text-tinta3">
            {sessao.contaNome}
            {sessao.contaTipo === "clinica" && " · clínica"}
          </span>
          <nav className="ml-auto flex items-center gap-4 text-[13px]">
            {comecando && (
              <Link href="/comecar" className="font-medium text-vaga hover:underline">
                Começar
              </Link>
            )}
            <Link href="/agenda" className="text-tinta2 hover:text-vaga">
              Agenda
            </Link>
            <Link href="/calendario" className="text-tinta2 hover:text-vaga">
              Calendário
            </Link>
            <Link href="/fila" className="text-tinta2 hover:text-vaga">
              Fila
            </Link>
            <Link href="/vagas" className="text-tinta2 hover:text-vaga">
              Vagas
            </Link>
            <Link href="/pacientes" className="text-tinta2 hover:text-vaga">
              Pacientes
            </Link>
            <Link href="/em-aberto" className="text-tinta2 hover:text-vaga">
              Em aberto
            </Link>
            <Link href="/financeiro" className="text-tinta2 hover:text-vaga">
              Financeiro
            </Link>
            <Link
              href="/receita-saude"
              className={
                fiscal.urgente
                  ? "font-semibold text-vaga hover:underline"
                  : "text-tinta2 hover:text-vaga"
              }
            >
              Receita{fiscal.pendentes > 0 && ` ${fiscal.pendentes}`}
            </Link>
            <Link href="/contador" className="text-tinta2 hover:text-vaga">
              Contador
            </Link>
            <Link href="/documentos" className="text-tinta2 hover:text-vaga">
              Documentos
            </Link>
            <Link href="/conta" className="text-tinta2 hover:text-vaga">
              Conta
            </Link>
            {/* O painel do negócio, e ele só existe para mim. Para todo mundo
                mais o link não aparece **e** a rota devolve 404 — não "acesso
                negado", que confirmaria a existência de uma tela escondida
                dentro do sistema onde ela guarda prontuário. */}
            {sessao.operador && (
              <Link href="/negocio" className="text-tinta3 hover:text-vaga">
                Negócio
              </Link>
            )}
            <Sair />
          </nav>
        </div>
      </header>

      <main className="mx-auto max-w-6xl px-5 py-8 sm:px-8">{children}</main>

      <Instalar />
    </div>
  );
}
