import Link from "next/link";
import { Marca } from "@/components/site/Marca";
import { sessaoAtual, acessosDa } from "@/lib/conta";
import { Sair } from "@/components/app/Sair";
import { Instalar } from "@/components/app/Instalar";
import {
  MenuPrincipal,
  SubNavegacao,
  BotaoNovo,
  Busca,
  BarraDoCelular,
  MenuDoPerfil,
} from "@/components/app/Navegacao";
import { destinos, acoesNovas } from "@/lib/navegacao";

/**
 * O cabeçalho, depois da auditoria.
 *
 * Ele tinha doze itens de mesmo peso, e o defeito não era o número: era que a
 * lista nomeava as tabelas do sistema — Fila, Vagas, Em aberto, Financeiro,
 * Receita, Contador, Documentos, Conta — em vez do trabalho dela. "Agenda",
 * aberta todo dia, disputava espaço com "Calendário", configurado uma vez.
 *
 * Agora são cinco destinos e nada mais:
 *
 *     Agenda · Encaixes · Pacientes · Recebimentos · Fechamento
 *
 * À direita, o que não é destino: buscar, o Novo e o perfil. Configuração e
 * arquivo saíram da rotina; Sair saiu do menu, porque sair não é lugar.
 *
 * Duas coisas mudaram de natureza junto:
 *
 *   - **Os prazos deixaram de ser itens permanentes.** "Receita" com um número
 *     ao lado ficava lá o ano inteiro, e um alarme que toca sempre é um alarme
 *     que se aprende a não ver. Virou a `FaixaDePendencias` no topo da Agenda,
 *     que só existe quando existe prazo correndo (`app/(app)/prazos.ts`).
 *
 *   - **O menu passou a respeitar a permissão.** Quem não tem o eixo
 *     financeiro não vê Recebimentos nem Fechamento. Isso é cortesia, não
 *     tranca: quem barra é a RLS da migração 0049, e ela barra igual para quem
 *     digitar a URL na mão.
 */
export default async function LayoutApp({ children }: { children: React.ReactNode }) {
  // Redireciona sozinha se não houver sessão. O middleware já barrou antes —
  // esta é a segunda porta, e a RLS no banco é a terceira e definitiva.
  const sessao = await sessaoAtual();
  const acessos = acessosDa(sessao);

  const primeiroNome = (sessao.nome ?? sessao.email).trim().split(/\s+/)[0];

  return (
    <div className="min-h-dvh pb-14 sm:pb-0">
      <header className="sticky top-0 z-20 border-b border-linha bg-folha">
        <div className="mx-auto flex max-w-6xl items-center gap-4 px-5 py-3 sm:px-8">
          <Link href="/agenda" className="shrink-0">
            <Marca className="text-[20px]" />
          </Link>

          <MenuPrincipal itens={destinos(acessos)} />

          <div className="ml-auto flex items-center gap-2.5">
            <Busca />
            <BotaoNovo acoes={acoesNovas(acessos)} />
            <div className="hidden sm:block">
              <MenuDoPerfil nome={primeiroNome} operador={sessao.operador}>
                <Sair />
              </MenuDoPerfil>
            </div>
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-6xl px-5 py-8 sm:px-8">
        <SubNavegacao />
        {children}
      </main>

      <BarraDoCelular acessos={acessos} />
      <Instalar />
    </div>
  );
}
