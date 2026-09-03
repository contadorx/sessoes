import Link from "next/link";
import { sessaoAtual, acessosDa } from "@/lib/conta";
import { podeFinanceiro } from "@/lib/permissao";
import { notFound } from "next/navigation";
import { prazosDoMes } from "@/app/(app)/prazos";
import { pendencias } from "@/lib/navegacao";

export const metadata = { title: "Fechamento" };

/**
 * O mês, em três caminhos.
 *
 * "Receita", "Contador" e "Documentos" eram três itens no menu principal, de
 * uso mensal, disputando espaço com a Agenda. Aqui eles são o que sempre
 * foram: as três coisas que se faz uma vez por mês, na ordem em que se faz.
 *
 * A página não é um painel. Ela diz o que está pendente e leva para a lista —
 * sem gráfico, sem percentual e sem indicador, porque nenhum número aqui muda
 * uma decisão dela: o que muda é a data de vencimento.
 */
export default async function Fechamento() {
  const sessao = await sessaoAtual();
  const acessos = acessosDa(sessao);

  // 404, e não "acesso negado": a segunda resposta confirmaria a existência de
  // uma tela com o dinheiro da conta para quem não deveria saber que ela
  // existe. Mesma decisão do painel do negócio.
  if (!podeFinanceiro(acessos)) notFound();

  const prazos = await prazosDoMes();
  const abertas = pendencias(prazos, acessos);

  const caminhos = [
    {
      // Primeiro da lista porque é a pergunta que se faz ao fechar o mês, antes
      // de qualquer obrigação: o que aconteceu com as horas.
      href: "/fechamento/livro",
      titulo: "O que aconteceu com cada hora",
      linha:
        "Quanto da sua capacidade virou receita, e por onde o resto foi — hora por hora, sem nenhuma linha preenchida à mão.",
      chave: null,
    },
    {
      href: "/fechamento/receita-saude",
      titulo: "Receita Saúde",
      linha:
        "Os recibos que a Receita Federal espera de quem atende como pessoa física. O prazo do ano anterior vence no fim de fevereiro, e o recibo errado tem dez dias para ser corrigido.",
      chave: "recibos",
    },
    {
      href: "/fechamento/contador",
      titulo: "Pasta do contador",
      linha:
        "Receitas, estornos, recibos, taxas e pendências do mês fechado, no formato que ele pede. Finanças, nunca prontuário.",
      chave: "contador",
    },
    {
      href: "/fechamento/documentos",
      titulo: "Documentos",
      linha:
        "Recibos, declarações de comparecimento e informes anuais já emitidos — com o retrato congelado de quem era quem no dia.",
      chave: null,
    },
  ];

  return (
    <div className="mx-auto max-w-3xl">
      <h1 className="font-serif text-[28px] leading-tight tracking-[-0.015em]">
        O fechamento do mês
      </h1>
      <p className="mt-3 max-w-[62ch] text-[14px] leading-relaxed text-tinta2">
        O que precisa acontecer uma vez por mês, e o que tem prazo. O prazo
        aparece ao lado do caminho que está com ele correndo; quando não há
        nenhum, os quatro ficam aqui sem aviso nenhum — é para ser assim.
      </p>

      <div className="mt-8 grid gap-px overflow-hidden rounded-cartao border border-linha bg-linha">
        {caminhos.map((c) => {
          const pendente = c.chave ? abertas.find((p) => p.chave === c.chave) : undefined;
          return (
            <Link key={c.href} href={c.href} className="group bg-folha px-5 py-5">
              <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                <h2 className="font-serif text-[19px] leading-snug text-tinta group-hover:text-vaga">
                  {c.titulo}
                </h2>
                {pendente && (
                  <span
                    className={`text-[12px] ${
                      pendente.urgente ? "font-medium text-vaga" : "text-tinta2"
                    }`}
                  >
                    {pendente.o_que} até {pendente.ate}
                  </span>
                )}
              </div>
              <p className="mt-1.5 max-w-[70ch] text-[13px] leading-relaxed text-tinta2">
                {c.linha}
              </p>
            </Link>
          );
        })}
      </div>
    </div>
  );
}
