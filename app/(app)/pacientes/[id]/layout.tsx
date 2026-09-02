import Link from "next/link";
import { notFound } from "next/navigation";
import { obterPaciente } from "../dados";
import { sessaoAtual, acessosDa } from "@/lib/conta";
import { paginasDoPaciente } from "@/lib/navegacao";
import { AbasDoPaciente } from "@/components/app/AbasDoPaciente";

/**
 * A moldura da ficha: o nome, o estado da ficha, e as abas.
 *
 * O QUE ESTA MUDANÇA DESFAZ
 *
 * A ficha era uma página só, com dez seções empilhadas. O Leandro nomeou o
 * defeito: *"tem fichas que são distintas e se perdem na mesma página"*. E o
 * problema não era comprimento — era que três dessas seções são **documentos
 * distintos, com regimes de sigilo distintos**, apresentados como um rolar
 * contínuo.
 *
 * O prontuário tem guarda de cinco anos e não se apaga. A anamnese congela ao
 * fechar, e o que chega depois é adendo com a data em que chegou. O cadastro se
 * edita à vontade. Empilhar os três ensina que são a mesma coisa — e a primeira
 * consequência disso não é confusão de navegação, é alguém escrever matéria
 * clínica no campo de anotação administrativa, que é o único ali que não tem
 * guarda nenhuma.
 *
 * A MOLDURA CARREGA O NOME, E SÓ
 *
 * Ela lê o paciente para saber o nome e se a ficha está arquivada, e cada
 * página filha lê os dados que ela mesma mostra. É uma consulta a mais por
 * navegação, e é o preço de a aba errada não carregar prontuário: com tudo na
 * moldura, abrir "Cadastro" leria evolução, e a trilha de acesso registraria
 * uma leitura de prontuário que ninguém fez.
 *
 * **E as abas clínicas não são escondidas: elas não existem.** A lista sai de
 * `paginasDoPaciente(acessos)`, no servidor. Esconder no navegador seria
 * decoração — a RLS já devolveria vazio (migração 0049) —, e uma aba que abre
 * uma tela em branco é pior que uma aba ausente: ela promete o que a próxima
 * tela nega.
 */
export default async function MolduraDoPaciente({
  children,
  params,
}: {
  children: React.ReactNode;
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const acessos = acessosDa(await sessaoAtual());
  const paciente = await obterPaciente(id);
  if (!paciente) notFound();

  return (
    <div className="mx-auto max-w-3xl">
      <Link href="/pacientes" className="text-[12.5px] text-tinta3 hover:text-vaga">
        ← pacientes
      </Link>

      <div className="mt-2 flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <h1 className="font-serif text-[28px] leading-tight tracking-[-0.015em]">
          {paciente.nome}
        </h1>
        {paciente.arquivado_em && (
          <span className="rounded-full bg-folha2 px-2 py-0.5 text-[11px] font-medium text-tinta3">
            ficha arquivada
          </span>
        )}
        {paciente.restricao_judicial && (
          <span className="rounded-full bg-aviso-bg px-2 py-0.5 text-[11px] font-medium text-aviso">
            restrição judicial
          </span>
        )}
      </div>

      <AbasDoPaciente id={id} paginas={paginasDoPaciente(acessos)} />

      <div className="mt-7">{children}</div>
    </div>
  );
}
