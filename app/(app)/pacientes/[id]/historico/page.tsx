import { notFound } from "next/navigation";
import { obterPaciente, linhaDoTempoDoPaciente } from "../../dados";
import { LinhaDoTempo } from "@/components/app/LinhaDoTempo";
import { hoje } from "@/lib/tempo-servidor";

export const metadata = { title: "Linha do tempo" };

/**
 * A linha do tempo — e ela **não** está atrás do acesso clínico.
 *
 * O que mora aqui é aritmética de presença: quantas horas, quantas
 * aconteceram, quantas seguidas não aconteceram, há quantos dias foi a última.
 * Nenhum rótulo, nenhum escore, nenhum conteúdo de sessão. Quem marca a agenda
 * precisa saber que a pessoa não vem há três semanas; o que aconteceu na sala
 * continua atrás do acesso clínico, nas outras duas abas.
 *
 * É a mesma separação que a 0049 escreveu na RLS, e é a mesma decisão da B27:
 * o sistema conta, e a leitura é de quem atende.
 */
export default async function Historico({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const paciente = await obterPaciente(id);
  if (!paciente) notFound();

  const tempo = await linhaDoTempoDoPaciente(paciente.id);

  return (
    <section>
      <h2 className="font-serif text-[21px] leading-tight">A linha do tempo</h2>
      <p className="mt-2 max-w-xl text-[13.5px] leading-relaxed text-tinta2">
        As horas desta pessoa, na ordem em que aconteceram — ou não
        aconteceram. Faltar não é só um lançamento financeiro: é o que se leva
        para a próxima sessão.
      </p>

      <LinhaDoTempo linhas={tempo.linhas} ausencias={tempo.ausencias} hoje={hoje()} />

      <p className="mt-5 max-w-xl text-[11.5px] leading-relaxed text-tinta3">
        O sistema conta; quem lê é você. Aqui não há escore, alerta nem
        rótulo — só o que aconteceu e quando. E a nota existe na hora que{" "}
        <b className="font-medium">não</b> houve: a evolução da sessão
        atendida é prontuário, e fica na aba dele.
      </p>
    </section>
  );
}
