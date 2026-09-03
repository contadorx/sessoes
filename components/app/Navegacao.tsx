"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import {
  destinoAtivo,
  barraDoCelular,
  type Destino,
  type AcaoNova,
  type Pendencia,
  SECOES,
} from "@/lib/navegacao";
import type { Acessos } from "@/lib/permissao";

/**
 * O menu, a busca, o Novo e a barra do celular.
 *
 * É client component por um motivo só: `usePathname`. Quem decide o que
 * aparece continua sendo `lib/navegacao.ts`, que é puro e testado — aqui só se
 * desenha o que ele devolveu.
 */

// ============================================ desktop

export function MenuPrincipal({ itens }: { itens: Destino[] }) {
  const caminho = usePathname();
  return (
    <nav className="hidden items-center gap-5 text-[13.5px] sm:flex">
      {itens.map((d) => {
        const aberto = destinoAtivo(caminho, d.href);
        return (
          <Link
            key={d.href}
            href={d.href}
            title={d.descricao}
            aria-current={aberto ? "page" : undefined}
            className={
              aberto
                ? "border-b-2 border-vaga pb-0.5 font-medium text-tinta"
                : "border-b-2 border-transparent pb-0.5 text-tinta2 transition-colors hover:text-vaga"
            }
          >
            {d.rotulo}
          </Link>
        );
      })}
    </nav>
  );
}

/**
 * A sub-navegação de um destino — só aparece quando ele tem seções.
 *
 * É aqui que "Vagas", "Financeiro", "Receita", "Contador" e "Documentos"
 * foram parar. Eles não sumiram: deixaram de disputar o cabeçalho com a
 * Agenda, que ela abre todo dia.
 */
export function SubNavegacao() {
  const caminho = usePathname();
  const destino = Object.keys(SECOES).find((d) => destinoAtivo(caminho, d));
  if (!destino) return null;
  const secoes = SECOES[destino];

  return (
    <nav className="mb-6 flex flex-wrap gap-x-5 border-b border-linha pb-1 text-[13px]">
      {secoes.map((s) => {
        const aqui = caminho === s.href;
        return (
          <Link
            key={s.href}
            href={s.href}
            aria-current={aqui ? "page" : undefined}
            className={`inline-flex min-h-11 items-center ${
              aqui ? "font-medium text-tinta" : "text-tinta3 transition-colors hover:text-vaga"
            }`}
          >
            {s.rotulo}
          </Link>
        );
      })}
    </nav>
  );
}

// ============================================ a faixa de pendências

/**
 * O que vence, no topo da tela que ela abre.
 *
 * Compacta e **dispensável**: some sozinha quando não há prazo, e fecha com um
 * clique quando há. Sem gráfico, sem percentual, sem linguagem de painel — ela
 * atende daqui a dez minutos.
 */
export function FaixaDePendencias({ itens, frase }: { itens: Pendencia[]; frase: string }) {
  const [fechada, setFechada] = useState(false);
  if (itens.length === 0 || fechada) return null;
  const urgente = itens.some((i) => i.urgente);

  return (
    <div
      className={`mb-6 flex flex-wrap items-baseline gap-x-3 gap-y-1 rounded-cartao border px-4 py-2.5 text-[13px] ${
        urgente ? "border-vaga-linha bg-vaga-bg" : "border-linha bg-folha2"
      }`}
    >
      <span className="sr-only">{frase}</span>
      <span aria-hidden className="text-tinta2">
        {itens.length === 1 ? "1 pendência com prazo:" : `${itens.length} pendências com prazo:`}
      </span>
      {itens.map((p) => (
        <Link
          key={p.chave}
          href={p.href}
          aria-hidden
          className={
            p.urgente
              ? "font-medium text-vaga underline decoration-vaga-linha underline-offset-4"
              : "text-tinta2 underline decoration-linha2 underline-offset-4 transition-colors hover:text-vaga"
          }
        >
          {p.o_que} até {p.ate}
        </Link>
      ))}
      <button
        type="button"
        onClick={() => setFechada(true)}
        className="ml-auto text-[12px] text-tinta3 transition-colors hover:text-tinta2"
      >
        fechar
      </button>
    </div>
  );
}

/**
 * Abrir e fechar um menu, uma vez só.
 *
 * Havia dois menus no cabeçalho e duas cópias desta lógica, e elas já tinham
 * divergido: o **Novo** fechava com Escape, o **do perfil** não — registrava só
 * `mousedown`. Quem abre com o teclado ficava preso no menu, tendo que sair
 * clicando fora, que é justamente o que não se faz com o teclado.
 *
 * E nenhum dos dois devolvia o foco ao botão ao fechar. Sem isso o foco volta
 * para o começo do documento, e a pessoa reatravessa o cabeçalho inteiro para
 * chegar onde já estava.
 *
 * Duas cópias de uma regra são duas oportunidades de a segunda ficar para trás.
 * Aqui é uma.
 */
function useMenu() {
  const [aberto, setAberto] = useState(false);
  const caixa = useRef<HTMLDivElement>(null);
  const botao = useRef<HTMLButtonElement>(null);

  // O foco volta para o botão que abriu — e só quando o menu estava aberto,
  // para não roubar o foco de quem nunca abriu nada.
  const fechar = (devolverFoco: boolean) => {
    setAberto((estava) => {
      if (estava && devolverFoco) botao.current?.focus();
      return false;
    });
  };

  useEffect(() => {
    if (!aberto) return;
    const fora = (e: MouseEvent) => {
      if (caixa.current && !caixa.current.contains(e.target as Node)) setAberto(false);
    };
    const esc = (e: KeyboardEvent) => {
      if (e.key === "Escape") fechar(true);
    };
    document.addEventListener("mousedown", fora);
    document.addEventListener("keydown", esc);
    return () => {
      document.removeEventListener("mousedown", fora);
      document.removeEventListener("keydown", esc);
    };
  }, [aberto]);

  return { aberto, alternar: () => setAberto((v) => !v), fechar, caixa, botao };
}

// ============================================ o botão Novo

export function BotaoNovo({ acoes }: { acoes: AcaoNova[] }) {
  const { aberto, alternar, fechar, caixa, botao } = useMenu();

  return (
    <div ref={caixa} className="relative">
      <button
        ref={botao}
        type="button"
        onClick={alternar}
        aria-expanded={aberto}
        aria-haspopup="menu"
        className="rounded-full bg-vaga px-3.5 py-1.5 text-[12.5px] font-semibold text-white transition-opacity hover:opacity-90"
      >
        Novo
      </button>
      {aberto && (
        <div
          role="menu"
          className="absolute right-0 z-30 mt-2 min-w-[13rem] overflow-hidden rounded-cartao border border-linha bg-folha shadow-lg"
        >
          {acoes.map((a) => (
            <Link
              key={a.href}
              href={a.href}
              role="menuitem"
              onClick={() => fechar(false)}
              className="block px-4 py-2.5 text-[13px] text-tinta2 transition-colors hover:bg-folha2 hover:text-vaga"
            >
              {a.rotulo}
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}

// ============================================ a busca

/**
 * A busca global.
 *
 * No desktop ela mora atrás de `/` — atalho que não colide com nada e que
 * quem digita rápido já espera. **No celular ela é visível**, sem atalho:
 * procurar paciente navegando por abas com o polegar era caro, e era a queixa
 * concreta da auditoria sobre a tela aberta todo dia.
 */
export function Busca() {
  const campo = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const atalho = (e: KeyboardEvent) => {
      if (e.key !== "/") return;
      const alvo = e.target as HTMLElement | null;
      const digitando =
        alvo?.tagName === "INPUT" || alvo?.tagName === "TEXTAREA" || alvo?.isContentEditable;
      if (digitando) return;
      e.preventDefault();
      campo.current?.focus();
    };
    document.addEventListener("keydown", atalho);
    return () => document.removeEventListener("keydown", atalho);
  }, []);

  return (
    <form action="/buscar" className="relative">
      <label htmlFor="busca-global" className="sr-only">
        Buscar paciente, sessão, documento ou pagamento
      </label>
      <input
        ref={campo}
        id="busca-global"
        name="q"
        type="search"
        autoComplete="off"
        placeholder="Buscar"
        className="w-32 rounded-full border border-linha bg-folha2 px-3.5 py-1.5 text-[12.5px] text-tinta placeholder:text-tinta3 focus:w-48 focus:border-vaga focus:outline-none sm:w-36 sm:focus:w-56"
      />
    </form>
  );
}

// ============================================ celular

export function BarraDoCelular({ acessos }: { acessos: Acessos }) {
  const caminho = usePathname();
  const itens = barraDoCelular(acessos);

  return (
    <nav className="barra-do-dedo fixed inset-x-0 bottom-0 z-20 grid grid-flow-col border-t border-linha bg-folha/95 backdrop-blur sm:hidden">
      {itens.map((i) => {
        const aberto = destinoAtivo(caminho, i.href);
        return (
          <Link
            key={i.href}
            href={i.href}
            aria-current={aberto ? "page" : undefined}
            className={`flex min-h-11 items-center justify-center px-1 text-center text-[11.5px] ${
              aberto ? "font-semibold text-vaga" : "text-tinta2"
            }`}
          >
            {i.curto}
          </Link>
        );
      })}
    </nav>
  );
}

/**
 * O menu do perfil, no canto. Sair mora aqui — não é destino, é fim de dia.
 */
export function MenuDoPerfil({
  nome,
  operador,
  children,
}: {
  nome: string;
  operador: boolean;
  children: React.ReactNode;
}) {
  const { aberto, alternar, fechar, caixa, botao } = useMenu();

  return (
    <div ref={caixa} className="relative">
      <button
        ref={botao}
        type="button"
        onClick={alternar}
        aria-expanded={aberto}
        aria-haspopup="menu"
        className="rounded-full border border-linha px-3 py-1.5 text-[12.5px] text-tinta2 transition-colors hover:border-vaga hover:text-vaga"
      >
        {nome}
      </button>
      {aberto && (
        <div
          role="menu"
          className="absolute right-0 z-30 mt-2 min-w-[15rem] overflow-hidden rounded-cartao border border-linha bg-folha shadow-lg"
        >
          {SECOES["/perfil"].map((s) => (
            <Link
              key={s.href}
              href={s.href}
              role="menuitem"
              onClick={() => fechar(false)}
              className="block px-4 py-2.5 text-[13px] text-tinta2 transition-colors hover:bg-folha2 hover:text-vaga"
            >
              {s.rotulo}
            </Link>
          ))}
          <Link
            href="/perfil#privacidade"
            role="menuitem"
            onClick={() => fechar(false)}
            className="block px-4 py-2.5 text-[13px] text-tinta2 transition-colors hover:bg-folha2 hover:text-vaga"
          >
            Privacidade e dados
          </Link>
          {operador && (
            // O backoffice, e ele é meu. Fica aqui, fora da navegação das
            // clientes: quem não é operadora não vê o link **e** recebe 404 na
            // rota — não "acesso negado", que confirmaria a existência de uma
            // tela escondida dentro do sistema onde ela guarda prontuário.
            <Link
              href="/negocio"
              role="menuitem"
              onClick={() => fechar(false)}
              className="block border-t border-linha px-4 py-2.5 text-[13px] text-tinta3 transition-colors hover:bg-folha2 hover:text-vaga"
            >
              Painel do negócio
            </Link>
          )}
          <div className="border-t border-linha px-4 py-2.5">{children}</div>
        </div>
      )}
    </div>
  );
}
