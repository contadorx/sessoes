import { notFound } from "next/navigation";
import { obterPaciente, anamneseDoPaciente } from "../../dados";
import { PainelAnamnese } from "@/components/app/Anamnese";
import { sessaoAtual, acessosDa } from "@/lib/conta";
import { podeClinico } from "@/lib/permissao";
import { SemAcessoClinico } from "@/components/app/SemAcessoClinico";

export const metadata = { title: "Anamnese" };

/**
 * A anamnese, agora numa página própria.
 *
 * E ganhar página própria não é arrumação: a anamnese tem um regime que nenhum
 * outro documento da ficha tem — **enquanto aberta, edita-se à vontade; depois
 * de fechada, congela, e o que chega entra como adendo com a data em que
 * chegou**. Embaixo do prontuário, num rolar contínuo, essa diferença ficava
 * dita numa linha de 13px entre duas caixas de texto parecidas.
 */
export default async function Anamnese({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const acessos = acessosDa(await sessaoAtual());
  if (!podeClinico(acessos)) return <SemAcessoClinico o="a anamnese" />;

  const paciente = await obterPaciente(id);
  if (!paciente) notFound();

  const anamnese = await anamneseDoPaciente(paciente.id);

  return (
    <section>
      <h2 className="font-serif text-[21px] leading-tight">A anamnese</h2>
      <p className="mt-2 max-w-xl text-[13.5px] leading-relaxed text-tinta2">
        A avaliação da demanda em profundidade — o bloco 2 do registro, escrito com tempo.
        Enquanto está aberta, edita-se à vontade; depois de fechada, o que chegar entra como
        adendo, com a data em que chegou.
      </p>

      <PainelAnamnese
        pacienteId={paciente.id}
        anamnese={anamnese.anamnese}
        aviso={anamnese.aviso}
      />
    </section>
  );
}
