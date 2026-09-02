"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { paginaAtiva, type PaginaDoPaciente } from "@/lib/navegacao";

/**
 * As abas da ficha.
 *
 * Cliente por um motivo só: saber qual está acesa. Tudo o mais — quais abas
 * existem para esta pessoa — é decidido no servidor, onde a permissão vale, e
 * chega aqui como lista pronta. Uma aba escondida no navegador não é uma aba
 * proibida, e este componente nunca decide isso.
 *
 * Rolagem horizontal no celular em vez de menu: cinco itens curtos cabem num
 * arrasto, e um menu sanfonado esconderia justamente o que a pessoa veio
 * escolher.
 */
export function AbasDoPaciente({
  id,
  paginas,
}: {
  id: string;
  paginas: PaginaDoPaciente[];
}) {
  const caminho = usePathname();
  const ativa = paginaAtiva(caminho, id);

  return (
    <nav className="-mx-5 mt-5 overflow-x-auto px-5 sm:mx-0 sm:px-0">
      <ul className="flex min-w-max gap-1 border-b border-linha">
        {paginas.map((p) => {
          const acesa = p.sufixo === ativa;
          return (
            <li key={p.sufixo}>
              <Link
                href={`/pacientes/${id}${p.sufixo}`}
                title={p.resumo}
                aria-current={acesa ? "page" : undefined}
                className={`-mb-px inline-block border-b-2 px-3 py-2 text-[13px] font-medium transition-colors ${
                  acesa
                    ? "border-vaga text-tinta"
                    : "border-transparent text-tinta3 hover:text-tinta2"
                }`}
              >
                {p.rotulo}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
