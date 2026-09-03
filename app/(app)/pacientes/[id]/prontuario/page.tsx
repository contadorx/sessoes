import { notFound } from "next/navigation";
import {
  obterPaciente,
  objetivosDoPaciente,
  registroDoPaciente,
  retencaoDaConta,
} from "../../dados";
import { PainelRegistro } from "@/components/app/Registro";
import { sessaoAtual, acessosDa } from "@/lib/conta";
import { podeClinico } from "@/lib/permissao";
import { hoje } from "@/lib/tempo-servidor";
import { SemAcessoClinico } from "@/components/app/SemAcessoClinico";
import { Objetivos } from "@/components/app/Objetivos";

export const metadata = { title: "Prontuário" };

/**
 * O prontuário — os quatro blocos que o CFP pede, e as evoluções.
 *
 * A conferência de acesso clínico aparece aqui **de novo**, e não porque a aba
 * some do menu para quem não pode. Menu não é autorização: quem digitar o
 * endereço chega. A RLS já devolveria vazio (0049), e o que esta linha
 * acrescenta é a frase — uma tela em branco se lê como defeito, e "você não tem
 * acesso clínico, e quem concede é a responsável pela conta" se lê como o que é.
 */
export default async function Prontuario({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const acessos = acessosDa(await sessaoAtual());
  if (!podeClinico(acessos)) return <SemAcessoClinico o="prontuário" />;

  const paciente = await obterPaciente(id);
  if (!paciente) notFound();

  const [registro, retencao, objetivos] = await Promise.all([
    registroDoPaciente(paciente.id),
    retencaoDaConta(),
    objetivosDoPaciente(paciente.id),
  ]);
  if (!registro) notFound();

  return (
    <section>
      <h2 className="font-serif text-[21px] leading-tight">O registro</h2>
      <p className="mt-2 max-w-xl text-[13.5px] leading-relaxed text-tinta2">
        O Prontuário Psicológico desta pessoa, nos quatro blocos que a Res. CFP 001/2009 e o
        Manual de nov/2025 pedem. O que estiver vazio aparece vazio — o Manual pede que se
        evitem espaços em branco, e um buraco anunciado é melhor que um silencioso.
      </p>

      <PainelRegistro
        pacienteId={paciente.id}
        registro={registro}
        ultimoRegistro={hoje()}
        retencaoAnos={retencao}
      />

      {/*
        O plano leve fica **junto do bloco 2**, e não numa aba nova.

        O bloco 2 é onde a demanda e os objetivos em texto livre já moram, e é
        onde ela olha quando a pergunta é "o que a gente combinou de trabalhar".
        Uma aba "Plano" teria a mesma sorte de qualquer métrica que mora onde
        ninguém abre — e este produto já tem telas demais competindo pela
        segunda-feira de manhã dela.

        `hoje` desce do servidor, em São Paulo: é ele que decide se uma data de
        revisão já chegou, e um `new Date()` no navegador às 21h daria o dia
        seguinte (lei 3).
      */}
      <Objetivos pacienteId={paciente.id} objetivos={objetivos} hoje={hoje()} />

      <p className="mt-5 max-w-xl text-[11.5px] leading-relaxed text-tinta3">
        O que estiver na <b className="font-medium">gaveta</b> não sai na cópia que o
        paciente pode pedir: é o Registro Documental, de acesso restrito a você. Tudo o
        mais sai — o direito de acesso ao próprio prontuário é dele. Nada aqui se apaga
        dentro do prazo de guarda, nem por engano.
      </p>
    </section>
  );
}
