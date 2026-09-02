import Link from "next/link";
import { Moldura, Documento, Bloco } from "@/components/site/Moldura";

export const metadata = {
  title: "Termos de serviço",
  description:
    "O que o Sessões faz, o que ele não faz, e o que continua sendo responsabilidade de quem atende.",
};

/**
 * Os termos.
 *
 * **Este documento mora no repositório, e não no banco.** É a decisão escrita
 * no cabeçalho da 0051: o blog é conteúdo e se edita por uma tela; termos são
 * compromisso, e um compromisso precisa de histórico de alteração que eu não
 * consiga reescrever às onze da noite por um formulário. Cada mudança aqui é um
 * commit com data e diff.
 *
 * O QUE ESTE TEXTO EVITA, E POR QUÊ
 *
 * Ele não diz "seus dados estão 100% seguros", não promete prazo para uma
 * obrigação que é dela, e não copia a frase do Manual do CFP sobre "descarte
 * sem qualquer possibilidade de cópias" — as três estão na lista do doc 18 do
 * que não se escreve. A terceira é a mais tentadora e a mais desonesta: copiá-la
 * exigiria operar sem backup.
 *
 * E ele descreve **só o que o software faz hoje**. O item da exportação
 * obrigatória antes da exclusão, que a minuta do doc 18 previa, não está aqui,
 * porque essa exigência ainda não existe no produto — política que descreve
 * comportamento inexistente é pior que política omissa.
 */
export default function Termos() {
  return (
    <Moldura>
      <Documento
        titulo="Termos de serviço"
        atualizado="1º de setembro de 2026"
        resumo="O que o Sessões faz, o que ele não faz, e o que continua sendo seu — porque parte disso a lei e o Conselho não deixam terceirizar."
      >
        <Bloco titulo="1. Quem somos, e o que é este serviço">
          <p>
            O Sessões é um software de gestão para consultório de psicologia:
            agenda, prontuário, cobrança, documentos e o fechamento do mês. Ele é
            operado por Leandro Vieira, em São Paulo, e contratado por você, a
            profissional ou clínica que o usa.
          </p>
          <p>
            Nós fornecemos a ferramenta. O atendimento, a relação com o paciente
            e as decisões clínicas são seus, e continuam sendo em qualquer
            circunstância.
          </p>
        </Bloco>

        <Bloco titulo="2. O que o sistema não faz, por decisão">
          <p>
            Estas não são funcionalidades que faltam. São coisas que o software
            recusa fazer, e a recusa está escrita no código, com teste
            automático que reprova quem tentar desfazê-la:
          </p>
          <p>
            Ele não interpreta conteúdo clínico, não sugere diagnóstico ou
            conduta, não avalia risco e não opina sobre a frequência com que
            alguém deve ser atendido. Ele conta, ordena e lembra — a leitura é
            sua.
          </p>
          <p>
            Ele não emite documento na Receita Federal por você: o Receita Saúde
            não tem interface pública para isso. O que ele faz é avisar do prazo
            e registrar que você emitiu.
          </p>
          <p>
            Ele não transaciona o seu dinheiro. O Pix é seu, a chave é sua, e o
            valor cai direto na sua conta — nós comparamos o que entrou com o que
            estava previsto, e nada mais.
          </p>
          <p>
            A fila de espera nunca vira leilão: a ordem é a de chegada, e não
            existe no banco de dados nenhuma coluna que permita dinheiro
            interferir nela.
          </p>
        </Bloco>

        <Bloco titulo="3. O que continua sendo sua responsabilidade">
          <p>
            A conformidade com o Conselho Federal de Psicologia é sua. O sistema
            reduz o trabalho de cumpri-la — organiza o registro nos blocos que a
            Resolução CFP nº 001/2009 e o Manual de nov/2025 pedem, mostra o que
            está em branco, calcula o prazo de guarda —, mas quem responde pelo
            prontuário é a profissional que o assina.
          </p>
          <p>
            O mesmo vale para o que você escreve: o conteúdo do prontuário, das
            evoluções, das anamneses e dos documentos que você emite é seu, e nós
            não o revisamos, não o corrigimos e não o lemos.
          </p>
          <p>
            E vale para as mensagens: os textos enviados aos seus pacientes
            partem de modelos neutros e aprovados, mas quem tem o vínculo com a
            pessoa do outro lado é você.
          </p>
        </Bloco>

        <Bloco titulo="4. A conta, os planos e o que cada um dá">
          <p>
            O plano Gratuito não expira e não pede cartão. Ele inclui tudo o que é{" "}
            <b className="font-medium">registro</b>: agenda, prontuário,
            anamnese, pacientes sem limite e o registro do que aconteceu com cada
            horário. Cobrar por isso seria cobrar para você poder existir
            organizada.
          </p>
          <p>
            O que se paga é o trabalho que o sistema faz no seu lugar: a fila que
            oferece a vaga sozinha, a régua que cobra sem você mandar a mensagem,
            o fechamento que sai pronto para o contador. Os valores estão na{" "}
            <Link href="/#planos" className="underline underline-offset-2 hover:text-vaga">
              página de planos
            </Link>
            , e uma mudança de preço nunca se aplica ao que já foi cobrado.
          </p>
          <p>
            Cada plano tem uma <b className="font-medium">faixa de sessões por
            mês</b>, e é essa a unidade cobrada. Atender acima da faixa{" "}
            <b className="font-medium">não bloqueia nada e não gera cobrança
            extra</b>: a agenda continua, a fila continua oferecendo, e as
            mensagens continuam saindo. O que acontece é que avisamos você, e
            sugerimos o plano seguinte a partir do próximo ciclo.
          </p>
          <p>
            <b className="font-medium">No plano Gratuito, a fila e a cobrança são
            enviadas por você.</b> A mensagem é preparada pelo sistema, com o
            texto pronto, e sai do seu próprio WhatsApp quando você toca — não
            enviamos nada por você nesses dois casos. Lembrete de véspera, aviso
            de desmarque e confirmação de encaixe continuam saindo
            automaticamente, no Gratuito também. Nos planos pagos, tudo é
            automático, pelo número do Sessões.
          </p>
          <p>
            <b className="font-medium">Não cobramos por mensagem, e não
            limitamos mensagem por plano.</b> Um limite comercial nosso não pode
            decidir quem fica sem ser avisado de que a sessão de amanhã foi
            desmarcada — quem receberia esse aviso é o seu paciente, que não
            escolheu plano nenhum. Existem travas técnicas de segurança contra
            envio repetido por defeito; elas não são limite de plano e são iguais
            para todo mundo.
          </p>
        </Bloco>

        <Bloco titulo="5. Encerrar">
          <p>
            Você pode encerrar a qualquer momento, sem multa e sem período
            mínimo. Antes de encerrar, exporte tudo: pacientes, sessões,
            prontuários, anamneses, documentos emitidos e registros financeiros
            saem num arquivo aberto e legível, que é a sua cópia.
          </p>
          <p>
            Isso importa mais aqui do que em outro software: a obrigação de
            guardar o prontuário por cinco anos é sua e continua valendo depois
            que a conta acaba. A exportação existe para você poder cumpri-la.
          </p>
          <p>
            Do nosso lado, só encerramos uma conta por falta de pagamento
            reiterada ou por uso que viole a lei — e, nos dois casos, com aviso e
            com tempo para você exportar.
          </p>
        </Bloco>

        <Bloco titulo="6. Disponibilidade, e o que fazemos quando falha">
          <p>
            Nenhum serviço fica no ar o tempo todo, e não prometemos que este
            fique. O que prometemos é o que dá para cumprir: cópias de segurança
            diárias com sete dias de retenção, avisos quando algo sai do ar por
            nossa causa, e nenhuma manutenção que apague dado seu.
          </p>
          <p>
            A{" "}
            <Link href="/seguranca" className="underline underline-offset-2 hover:text-vaga">
              página de segurança
            </Link>{" "}
            explica o resto com número, não com adjetivo.
          </p>
        </Bloco>

        <Bloco titulo="7. Mudanças nestes termos">
          <p>
            Quando algum destes itens mudar, a data no topo muda junto e você é
            avisada por e-mail antes de a mudança valer. Alterações que reduzam o
            que você tem hoje só valem para quem concordar com elas.
          </p>
          <p>
            Dúvida sobre qualquer ponto:{" "}
            <a
              href="mailto:oi@sessoes.com.br"
              className="underline underline-offset-2 hover:text-vaga"
            >
              oi@sessoes.com.br
            </a>
            . Respondemos por escrito, e a resposta vale.
          </p>
        </Bloco>
      </Documento>
    </Moldura>
  );
}
