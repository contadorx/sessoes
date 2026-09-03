import Link from "next/link";
import { Moldura, Documento, Bloco } from "@/components/site/Moldura";

export const metadata = {
  title: "Privacidade",
  description:
    "Quem é controlador, quem é operador, o que guardamos, por quanto tempo, e o que a nossa equipe não consegue ver.",
};

/**
 * A política de privacidade.
 *
 * Ela é a minuta do doc 18 virada texto de tela, **com as duas correções que a
 * própria minuta pedia**:
 *
 *  · A cláusula 4 da minuta dizia que a exclusão da conta não se conclui *sem*
 *    exportação. Isso ainda não é verdade no produto — exportação existe,
 *    exclusão existe, e a exigência de uma antes da outra não está construída.
 *    Então a frase aqui **descreve o que existe** e recomenda a exportação, em
 *    vez de descrever uma trava que não há. Política que descreve comportamento
 *    inexistente é pior que política omissa.
 *
 *  · A cláusula 3 falava de uma tela que mostra a data de vencimento da guarda.
 *    A regra existe no banco (`elegiveis_para_eliminacao`, com a conta a partir
 *    da maioridade do menor); a tela é a B33. O texto fala do prazo, e não da
 *    tela.
 *
 * E a tensão que a minuta se recusa a esconder está aqui inteira: o Manual do
 * CFP pede *"descarte definitivo, sem qualquer possibilidade de cópias"*, e
 * todo banco sério tem backup, que é exatamente uma possibilidade de cópia. A
 * saída honesta não é escolher um lado — é declarar os dois com prazo escrito.
 */
export default function Privacidade() {
  return (
    <Moldura>
      <Documento
        titulo="Privacidade"
        atualizado="1º de setembro de 2026"
        resumo="Quem decide o que acontece com o dado do seu paciente é você. Nós operamos a seu mando — e esta página diz exatamente o que isso significa, com prazo e com número."
      >
        <Bloco titulo="1. Você é a controladora. Nós somos o operador.">
          <p>
            Na linguagem da LGPD (Lei 13.709/2018), quem decide por que e como os
            dados dos seus pacientes são tratados é você:{" "}
            <b className="font-medium">controladora</b>. Nós tratamos esses dados
            a seu mando e nos limites do que você contratou:{" "}
            <b className="font-medium">operador</b>.
          </p>
          <p>
            A distinção não é formalidade. Ela decide quem responde ao paciente
            que pede acesso ou correção — é você, porque é você quem tem o
            vínculo profissional e o dever de sigilo. Nós não atendemos esse
            pedido diretamente e nunca agimos sobre esse dado por conta própria.
          </p>
          <p>
            Dado de saúde é dado pessoal sensível pela LGPD (art. 5º, II), e num
            consultório de psicologia a própria lista de quem tem hora marcada já
            é isso. O produto é construído nessa premissa, e não em cima dela.
          </p>
        </Bloco>

        <Bloco titulo="2. O que guardamos">
          <p>
            <b className="font-medium">Sobre você:</b> nome, e-mail, telefone,
            dados do plano, histórico de cobrança e registros técnicos de erro.
          </p>
          <p>
            <b className="font-medium">Sobre os seus pacientes:</b> o que você
            registra — cadastro, contato, horários, sessões, valores, e o
            conteúdo clínico que você escrever (prontuário, evolução, anamnese).
            Nada disso vem de outro lugar; tudo entra por você.
          </p>
          <p>
            <b className="font-medium">O que não guardamos:</b> conteúdo de
            sessão gravado, transcrição de áudio, e o que você não digitar. O
            sistema não grava atendimento, e não existe função para isso.
          </p>
        </Bloco>

        <Bloco titulo="3. Ninguém da nossa equipe lê prontuário — e isso é código, não promessa">
          <p>
            As telas que usamos para operar o negócio e dar suporte enxergam
            conta, plano, cobrança e <b className="font-medium">contagem</b>:
            quantos pacientes, quantas sessões, quantas mensagens. Elas não
            enxergam nome de paciente, prontuário, evolução nem anamnese.
          </p>
          <p>
            Isso não é uma regra de conduta que alguém precisa lembrar. As
            funções do painel são escritas por lista de colunas nomeadas, e há um
            teste automático que lê o código dessas funções e{" "}
            <b className="font-medium">reprova a alteração</b> se qualquer uma
            passar a mencionar uma tabela clínica. Outro teste planta um nome
            improvável na base e falha se ele aparecer em qualquer saída.
          </p>
          <p>
            Também não existe no sistema um modo de assumir a sua sessão para
            &ldquo;ver o que está acontecendo&rdquo;. É a porta mais comum em softwares desse
            tipo, e ela está fechada aqui porque o sigilo é seu — você não pode
            nos dar acesso a ele nem se quiser (Código de Ética do Psicólogo,
            art. 9º).
          </p>
        </Bloco>

        <Bloco titulo="4. Com quem o dado se encontra, e só quando você manda">
          <p>
            <b className="font-medium">Infraestrutura:</b> os dados ficam em
            servidores da Supabase (Amazon Web Services), cifrados em repouso e
            em trânsito.
          </p>
          <p>
            <b className="font-medium">Mensagens:</b> quando você usa lembrete,
            oferta de vaga ou aviso de cobrança, a mensagem passa pelo provedor
            de WhatsApp. O texto padrão é discreto: remetente neutro, sem o seu
            nome profissional e sem a palavra terapia na tela bloqueada do
            celular de quem recebe.
          </p>
          <p>
            <b className="font-medium">Google Agenda:</b> é opcional e nasce
            desligada. Quando você liga, o evento sai escrito apenas &ldquo;Sessão&rdquo; —
            sem nome. Existe um modo que inclui o nome, ele exige um clique seu,
            e a tela mostra antes como o evento vai ficar, com um nome real da
            sua base, para você decidir vendo.
          </p>
          <p>
            <b className="font-medium">Contador:</b> a pasta mensal é opcional,
            nasce desligada, e leva dinheiro — nunca gente. Não existe uma
            opção de &ldquo;incluir os nomes&rdquo;, porque opção assim todo mundo marca.
          </p>
          <p>
            Não vendemos dado, não fazemos publicidade com ele, e não usamos
            prontuário, evolução ou anamnese para treinar modelos de
            inteligência artificial. Esse conteúdo também não é copiado para
            ambientes de teste ou demonstração.
          </p>
        </Bloco>

        <Bloco titulo="5. O que você apaga some na hora. E as cópias somem em até 7 dias.">
          <p>
            Quando você apaga o contato de um paciente ou encerra a conta
            inteira, os dados saem do banco em produção no momento da
            confirmação. A partir dali eles não aparecem em nenhuma tela,
            exportação, relatório ou integração.
          </p>
          <p>
            <b className="font-medium">Documento emitido é a exceção, e é de
            propósito:</b> recibo, declaração e informe não se apagam — se
            cancelam, com data e motivo, e o cancelamento fica no lugar. Um
            documento que some sem deixar rastro é um documento em que ninguém
            pode confiar, inclusive você, no dia em que precisar provar que
            emitiu.
          </p>
          <p>
            Mantemos cópias de segurança diárias para o caso de falha ou exclusão
            acidental. Um dado excluído continua existindo nessas cópias{" "}
            <b className="font-medium">por no máximo 7 dias</b>, quando elas
            expiram e são destruídas automaticamente. Nesse intervalo, as cópias
            são cifradas, não são acessíveis por nenhuma tela do produto, e só
            podem ser restauradas inteiras — não é possível extrair delas o
            registro de uma pessoa.
          </p>
          <p className="border-l-2 border-linha2 pl-4 text-tinta3">
            Por que não prometemos exclusão instantânea e definitiva: porque isso
            exigiria operar sem backup, e operar sem backup significa que uma
            falha nossa apagaria o prontuário dos seus pacientes para sempre.
            Preferimos um prazo curto, escrito e verificável a uma promessa que
            nos obrigaria a ser menos cuidadosos.
          </p>
        </Bloco>

        <Bloco titulo="6. O que a lei manda guardar, guardamos">
          <p>
            O prontuário psicológico tem guarda mínima de cinco anos (Resolução
            CFP nº 001/2009). Quando o paciente é menor de idade, o prazo conta a
            partir da maioridade dele, e não do último atendimento — sem isso, a
            ficha de quem foi atendido aos nove anos ficaria elegível para
            descarte aos catorze, antes de a própria pessoa ter idade para
            pedi-la.
          </p>
          <p>
            A guarda é uma obrigação sua como profissional, e o sistema existe
            para você poder cumpri-la. Por isso, antes de excluir qualquer coisa,
            ele diz até quando aquele registro ainda está no prazo — e a decisão
            de apagar continua sendo sua, porque quem responde por ela é você.
          </p>
          <p>
            O que <b className="font-medium">é</b> apagado a qualquer momento,
            mesmo dentro do prazo: telefone, e-mail, contato dos responsáveis e o
            consentimento para receber mensagem. Existe uma função específica
            para isso, e ela deixa o registro clínico intacto — apagar o contato
            é minimização de dado; apagar o registro seria descumprir a guarda.
          </p>
        </Bloco>

        <Bloco titulo="7. Encerrar a conta, e levar os dados">
          <p>
            A exportação sai a qualquer momento, em formato aberto e legível, com
            tudo: pacientes, sessões, prontuários, anamneses, documentos
            emitidos, registros financeiros e fiscais. Ela é a sua cópia.
          </p>
          <p>
            <b className="font-medium">Sem exportar, a conta não é encerrada.</b>{" "}
            A obrigação de guarda dos cinco anos continua sendo sua depois que a
            conta acaba, e encerrar sem exportar transfere para você um problema
            sem solução — o registro que o Conselho pode pedir daqui a quatro anos
            deixaria de existir em qualquer lugar do mundo. Por isso o sistema
            recusa: só encerra quem exportou nas últimas 24 horas.
          </p>
          <p>
            As 24 horas não são burocracia. Uma exportação de duas semanas atrás
            não tem as duas semanas — e o que você levaria seria um arquivo com
            cara de completo e um buraco no fim.
          </p>
          <p>
            Encerrar pede também <b className="font-medium">o nome da conta
            digitado</b>, e só a titular pode fazê-lo. É a única operação
            irreversível do produto, e um clique acidental não deve alcançá-la.
          </p>
        </Bloco>

        <Bloco titulo="8. Se algo acontecer">
          <p>
            Em caso de incidente de segurança que possa afetar dados dos seus
            pacientes, avisamos você{" "}
            <b className="font-medium">em até 24 horas</b> — com o que aconteceu,
            o que foi atingido na sua conta, o que já foi feito e a hora exata em
            que soubemos. Essa hora é de onde começa a contar o prazo de{" "}
            <b className="font-medium">três dias úteis</b> que a Resolução
            CD/ANPD nº 15/2024 dá a você para comunicar a ANPD e os pacientes.
          </p>
          <p>
            <b className="font-medium">E o dever de comunicar é seu</b>, nos
            dados dos pacientes: você é a controladora desses dados e nós somos o
            operador. A{" "}
            <a href="/incidente" className="underline underline-offset-2 hover:text-vaga">
              página do incidente
            </a>{" "}
            explica por quê, diz o que fazemos nas primeiras horas e traz o
            modelo do texto que você vai precisar mandar ao paciente.
          </p>
          <p>
            Para exercer qualquer direito, corrigir qualquer coisa desta página
            ou tirar dúvida:{" "}
            <a
              href="mailto:oi@sessoes.com.br"
              className="underline underline-offset-2 hover:text-vaga"
            >
              oi@sessoes.com.br
            </a>
            . A{" "}
            <Link href="/seguranca" className="underline underline-offset-2 hover:text-vaga">
              página de segurança
            </Link>{" "}
            detalha o lado técnico.
          </p>
        </Bloco>
      </Documento>
    </Moldura>
  );
}
