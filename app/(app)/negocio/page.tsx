import { notFound } from "next/navigation";
import { sessaoAtual } from "@/lib/conta";
import { lerPainel, lerContas, lerMedidaDoReceitaSaude } from "./dados";
import { PainelNegocio } from "@/components/app/Negocio";

export const metadata = { title: "Negócio" };

/**
 * O painel do negócio — a única tela deste produto que não é dela.
 *
 * Devolve **404**, e não "acesso negado", para quem não for operador. A
 * diferença importa: uma negação confirma que a rota existe, e uma psicóloga
 * curiosa que descobrisse `/negocio` aprenderia que há um painel escondido no
 * sistema onde ela guarda prontuário. Não há motivo para ela saber disso, e
 * "existe uma tela que eu não posso ver" é uma frase que corrói confiança sem
 * dar nada em troca. É o mesmo padrão do `/api/*` (404 sem o segredo, nunca
 * 403) e da rota de abrir documento do Enquadria.
 *
 * A tranca de verdade não é esta: as duas funções do banco conferem
 * `e_operador()` por dentro e levantam exceção. Isto aqui é a porta; a
 * fechadura está lá.
 */
export default async function Negocio({
  searchParams,
}: {
  searchParams: Promise<{ mes?: string }>;
}) {
  const sessao = await sessaoAtual();
  if (!sessao.operador) notFound();

  const params = await searchParams;
  const mes = /^\d{4}-(0[1-9]|1[0-2])-01$/.test(params.mes ?? "") ? params.mes! : undefined;

  const [painel, contas, medida] = await Promise.all([
    lerPainel(mes),
    lerContas(),
    lerMedidaDoReceitaSaude(),
  ]);

  return <PainelNegocio painel={painel} contas={contas} medida={medida} />;
}
