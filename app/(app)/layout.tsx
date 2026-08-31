import Link from "next/link";
import { Marca } from "@/components/site/Marca";
import { sessaoAtual } from "@/lib/conta";
import { Sair } from "@/components/app/Sair";

export default async function LayoutApp({ children }: { children: React.ReactNode }) {
  // Redireciona sozinha se não houver sessão. O middleware já barrou antes —
  // esta é a segunda porta, e a RLS no banco é a terceira e definitiva.
  const sessao = await sessaoAtual();

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
            <Link href="/agenda" className="text-tinta2 hover:text-vaga">
              Agenda
            </Link>
            <Link href="/pacientes" className="text-tinta2 hover:text-vaga">
              Pacientes
            </Link>
            <Sair />
          </nav>
        </div>
      </header>

      <main className="mx-auto max-w-6xl px-5 py-8 sm:px-8">{children}</main>
    </div>
  );
}
