import { notFound } from "next/navigation";
import { obterPaciente } from "../../dados";
import { atualizarPaciente } from "../../acoes";
import { FormPaciente } from "@/components/app/FormPaciente";
import { Privacidade } from "@/components/app/Privacidade";

export const metadata = { title: "Cadastro" };

/**
 * O cadastro — quem é, como avisar, e os direitos de LGPD.
 *
 * Esta é a aba **sem guarda legal**: o que está aqui se edita à vontade, e o
 * contato se apaga a qualquer momento mesmo dentro do prazo de cinco anos.
 * Separá-la das abas clínicas é o que faz a diferença de regime ficar visível
 * — na página única, o campo "anotação administrativa" ficava a três seções de
 * distância da evolução, e a distinção entre os dois dependia de alguém ler a
 * nota embaixo do campo.
 */
export default async function Ficha({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const paciente = await obterPaciente(id);
  if (!paciente) notFound();

  return (
    <>
      <section>
        <h2 className="rotulo">Cadastro</h2>
        {paciente.arquivado_em ? (
          <div className="mt-2 rounded-cartao border border-linha bg-folha2 px-5 py-4">
            <p className="text-[12.5px] leading-relaxed text-tinta2">
              Ficha arquivada — só leitura. Encerramento registrado:
            </p>
            <p className="mt-2 whitespace-pre-wrap text-[13px] leading-relaxed text-tinta">
              {paciente.encerramento}
            </p>
          </div>
        ) : (
          <div className="mt-2">
            <FormPaciente
              acao={atualizarPaciente}
              paciente={paciente}
              rotuloBotao="Salvar cadastro"
            />
          </div>
        )}
      </section>

      <Privacidade
        pacienteId={paciente.id}
        nome={paciente.nome}
        arquivado={Boolean(paciente.arquivado_em)}
        contatoEsquecidoEm={paciente.contato_esquecido_em}
        restricaoJudicial={paciente.restricao_judicial}
      />
    </>
  );
}
