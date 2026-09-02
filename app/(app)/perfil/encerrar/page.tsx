import Link from "next/link";
import { sessaoAtual } from "@/lib/conta";
import { ultimaExportacao } from "./dados";
import { EncerrarConta } from "@/components/app/Encerrar";

export const metadata = { title: "Encerrar a conta" };

/**
 * Encerrar a conta (B41).
 *
 * A `/privacidade`, publicada, promete que apagar a conta inteira tira os dados
 * do banco em produção no momento da confirmação. Até a migração 0062 isso não
 * existia — e uma política que descreve comportamento que o software não tem é
 * exatamente o erro que este projeto passou dois dias recusando.
 *
 * A tela é a segunda metade daquela migração, e ela **não repete as validações
 * da função**. `eliminar_conta` recusa em três casos e diz por quê em cada um;
 * o trabalho daqui é mostrar o estado — quando foi a última exportação, qual é
 * o nome exato a digitar — e pôr a exportação no caminho, em vez de mandar a
 * pessoa procurá-la.
 *
 * A ordem da página é a ordem da decisão: primeiro levar a cópia, depois
 * encerrar. Invertida, a exportação vira aviso legal no rodapé de uma tela que
 * já tem um botão pronto.
 */
export default async function EncerrarPagina() {
  const sessao = await sessaoAtual();
  const exportacao = await ultimaExportacao();

  return (
    <div className="mx-auto max-w-2xl">
      <Link href="/perfil" className="text-[12.5px] text-tinta3 hover:text-vaga">
        ← perfil
      </Link>

      <h1 className="mt-2 font-serif text-[28px] leading-tight tracking-[-0.015em]">
        Encerrar a conta
      </h1>

      <p className="mt-3 max-w-[64ch] text-[14px] leading-relaxed text-tinta2">
        Isto apaga <b className="font-semibold text-tinta">{sessao.contaNome}</b>{" "}
        do banco em produção: tudo o que está aqui deixa de existir, e não há
        como desfazer. A conta é sua, e sair dela é uma decisão sua — este
        produto não retém ninguém pelo trabalho que já colocou dentro dele.
      </p>

      <div className="mt-6">
        <EncerrarConta
          nomeDaConta={sessao.contaNome}
          exportacao={exportacao}
          ehDona={sessao.papel === "dona"}
        />
      </div>

      <p className="mt-8 max-w-[64ch] border-t border-linha pt-5 text-[11.5px] leading-relaxed text-tinta3">
        O que esta tela não decide: ela não recusa o encerramento porque o prazo
        de guarda de cinco anos está correndo. A guarda é obrigação sua, e um
        sistema que se recusasse a devolver a sua casa em nome da sua própria
        obrigação estaria sequestrando dado com nome de zelo. O que ele faz é
        dizer, na frase final, até quando você continua responsável.
      </p>
    </div>
  );
}
