import Link from "next/link";
import { Marca } from "@/components/site/Marca";

/**
 * O cabeçalho e o rodapé das páginas que não são a landing.
 *
 * A landing carrega os dela por dentro, porque o cabeçalho dela tem estados que
 * mais nenhuma página tem (âncoras para seções que só existem lá). O que se
 * repete — a marca, a porta de entrada, os três documentos — mora aqui.
 *
 * **O rodapé é o lugar dos três documentos, e isso não é decoração.** Termos,
 * privacidade e segurança precisam estar a um clique de qualquer página, e não
 * escondidos numa página de ajuda: a psicóloga que vai assinar isto tem uma
 * obrigação profissional de conferir o que o Manual do CFP de nov/2025 manda
 * conferir — *"profissionais usando plataformas pagas devem verificar cláusulas
 * sobre eliminação"*. Um link difícil de achar é uma cláusula difícil de
 * conferir.
 */
export function Moldura({ children }: { children: React.ReactNode }) {
  return (
    <>
      <header className="sticky top-0 z-20 border-b border-linha bg-folha/85 backdrop-blur">
        <div className="mx-auto flex max-w-5xl items-center gap-4 px-5 py-3 sm:px-8">
          <Link href="/">
            <Marca className="text-[21px]" />
          </Link>

          <div className="ml-auto flex items-center gap-4">
            <Link
              href="/blog"
              className="hidden text-[12.5px] font-medium text-tinta2 transition-colors hover:text-vaga sm:inline"
            >
              Artigos
            </Link>
            <Link
              href="/#planos"
              className="hidden text-[12.5px] font-medium text-tinta2 transition-colors hover:text-vaga sm:inline"
            >
              Preço
            </Link>
            <Link
              href="/entrar"
              className="text-[12.5px] font-medium text-tinta2 transition-colors hover:text-vaga"
            >
              Já tenho conta
            </Link>
            <Link
              href="/entrar?criar"
              className="rounded-full bg-vaga px-4 py-1.5 text-[12.5px] font-semibold text-white transition-opacity hover:opacity-90"
            >
              Criar conta grátis
            </Link>
          </div>
        </div>
      </header>

      <main>{children}</main>

      <RodapeDoSite />
    </>
  );
}

/** O rodapé, também usado pela landing — para os três links existirem nos dois. */
export function RodapeDoSite() {
  return (
    <footer className="border-t border-linha bg-folha">
      <div className="mx-auto max-w-5xl px-5 py-8 sm:px-8">
        <div className="flex flex-col gap-3 text-[12px] text-tinta3 sm:flex-row sm:items-center">
          <Marca className="text-[16px]" />
          <span className="max-w-[52ch] text-tinta2">
            Feito por um contador para tirar a conferência do caminho de quem
            atende.
          </span>
          <span className="sm:ml-auto">
            São Paulo ·{" "}
            <a
              href="mailto:oi@sessoes.com.br"
              className="underline decoration-linha2 underline-offset-2 transition-colors hover:text-vaga"
            >
              oi@sessoes.com.br
            </a>
          </span>
        </div>

        <div className="mt-5 flex flex-wrap gap-x-5 gap-y-2 border-t border-linha pt-4 text-[12px] text-tinta2">
          <Link href="/blog" className="transition-colors hover:text-vaga">
            Artigos
          </Link>
          <Link href="/termos" className="transition-colors hover:text-vaga">
            Termos de serviço
          </Link>
          <Link href="/privacidade" className="transition-colors hover:text-vaga">
            Privacidade
          </Link>
          <Link href="/seguranca" className="transition-colors hover:text-vaga">
            Segurança
          </Link>
          {/* O quarto documento. Ele entra no rodapé pelo mesmo motivo dos
              outros três: metade do plano de incidente é obrigação **dela**, e
              obrigação de alguém não mora atrás de um clique difícil. */}
          <Link href="/incidente" className="transition-colors hover:text-vaga">
            Se acontecer um incidente
          </Link>
        </div>
      </div>
    </footer>
  );
}

/** O corpo de uma página de documento: uma coluna, medida para leitura longa. */
export function Documento({
  titulo,
  atualizado,
  resumo,
  children,
}: {
  titulo: string;
  atualizado: string;
  resumo: string;
  children: React.ReactNode;
}) {
  return (
    <article className="mx-auto max-w-[68ch] px-5 py-12 sm:px-8 sm:py-16">
      <h1 className="font-serif text-[30px] leading-tight tracking-[-0.015em] text-balance sm:text-[38px]">
        {titulo}
      </h1>
      <p className="mt-3 text-[14.5px] leading-relaxed text-tinta2">{resumo}</p>
      <p className="mt-2 text-[12px] text-tinta3">Atualizado em {atualizado}.</p>
      <div className="mt-9 flex flex-col gap-7">{children}</div>
    </article>
  );
}

export function Bloco({ titulo, children }: { titulo: string; children: React.ReactNode }) {
  return (
    <section>
      <h2 className="font-serif text-[20px] leading-snug text-tinta">{titulo}</h2>
      <div className="mt-2 flex flex-col gap-2.5 text-[14px] leading-relaxed text-tinta2">
        {children}
      </div>
    </section>
  );
}
