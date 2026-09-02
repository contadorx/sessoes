import Link from "next/link";
import { Moldura, Documento, Bloco } from "@/components/site/Moldura";

export const metadata = {
  title: "Se acontecer um incidente",
  description:
    "O que o Sessões faz nas primeiras 24 horas, em quanto tempo você é avisada, de quem é o dever de comunicar a ANPD e o paciente, e o modelo do texto que você vai precisar mandar.",
};

/**
 * A página do plano de incidente (B40).
 *
 * POR QUE ELA É PÚBLICA, E POR QUE ELA É ESTÁTICA
 *
 * **Pública** porque metade do plano não é minha: num incidente com dado de
 * paciente, quem comunica a ANPD e os titulares é a psicóloga — ela é a
 * controladora desses dados, e eu sou o operador. Uma obrigação que é dela não
 * pode morar num documento interno meu. É também o que ela mostra ao CRP e o
 * que ela lê antes de decidir confiar prontuário a um terceiro, que é o que o
 * Manual do CFP de nov/2025 manda fazer.
 *
 * **Estática** porque o dia em que ela mais precisa desta página pode ser o dia
 * em que o resto do produto está com problema. Nada aqui lê o banco, nada aqui
 * exige sessão, e a rota está na lista pública do `proxy.ts` — que é
 * exatamente o que faltava para `/termos`, `/privacidade` e `/seguranca`
 * durante meses.
 *
 * O QUE ELA NÃO FAZ
 *
 * Não promete que não vai acontecer, não promete uptime, e não diz "seus dados
 * estão seguros". Diz prazo, diz de quem é o dever, e entrega o texto pronto —
 * que é o que serve às três da manhã. O plano operacional inteiro é o
 * `claude/26`; aqui está a parte que é dela.
 */
export default function Incidente() {
  return (
    <Moldura>
      <Documento
        titulo="Se acontecer um incidente"
        atualizado="2 de setembro de 2026"
        resumo="Em quanto tempo você é avisada, de quem é o dever de comunicar, e o texto pronto que você vai precisar mandar. Com prazo, e sem adjetivo."
      >
        <Bloco titulo="1. O compromisso, em uma linha">
          <p>
            Se um incidente de segurança atingir dados dos seus pacientes,{" "}
            <b className="font-medium text-tinta">
              você é avisada em até 24 horas
            </b>{" "}
            — individualmente, com o que aconteceu, o que foi atingido{" "}
            <em>na sua conta</em>, o que já foi feito, e a hora exata em que eu
            soube.
          </p>
          <p>
            Essa hora não é detalhe: é dela que começa a contar o prazo que a lei
            dá a você. Por isso ela vai escrita na mensagem.
          </p>
        </Bloco>

        <Bloco titulo="2. De quem é o dever de comunicar — e a resposta incomoda">
          <p>
            Pela LGPD, quem decide as finalidades do tratamento de um dado é o{" "}
            <b className="font-medium">controlador</b>, e quem o trata por conta
            dele é o <b className="font-medium">operador</b>. No prontuário dos
            seus pacientes, <b className="font-medium text-tinta">
              a controladora é você
            </b>{" "}
            e o operador é o Sessões.
          </p>
          <p>
            A consequência é direta: num incidente que atinja dado de paciente,{" "}
            <b className="font-medium text-tinta">
              quem comunica a ANPD e os pacientes é você
            </b>
            . O meu dever é te dar, a tempo, tudo o que essa comunicação exige —
            e é por isso que a seção 4 existe.
          </p>
          <p>
            Nos dados <em>da sua conta</em> — o seu e-mail, a sua senha, as suas
            faturas —, o controlador sou eu, e quem comunica sou eu.
          </p>
        </Bloco>

        <Bloco titulo="3. Os prazos, e de quando eles contam">
          <p>
            A Resolução CD/ANPD nº 15/2024 dá{" "}
            <b className="font-medium text-tinta">três dias úteis</b> para
            comunicar à ANPD e aos titulares, contados{" "}
            <em>do conhecimento de que o incidente afetou dados pessoais</em> —
            não da data em que ele aconteceu, e não do fim da apuração.
          </p>
          <p>
            A norma dá seis dias úteis a agentes de pequeno porte, e o Sessões é
            um. <b className="font-medium">Aqui dentro o plano opera em três</b>:
            a classificação pode ser contestada no pior momento possível, e um
            plano que mira o prazo longo perde o curto. Os seis dias são folga,
            não meta.
          </p>
          <p>
            <b className="font-medium">Não saber ainda a extensão não adia
            nada.</b>{" "}
            Comunica-se no prazo com o que se sabe, e complementa-se em até vinte
            dias úteis. Esperar a apuração terminar é o erro mais comum e o mais
            caro.
          </p>
        </Bloco>

        <Bloco titulo="4. O texto que você vai precisar mandar">
          <p>
            Está pronto porque texto escrito às três da manhã sai errado. É um
            modelo — os colchetes são o que você preenche —, e ele já vem na
            ordem dos sete itens que a norma exige da comunicação ao titular.
          </p>
          <div className="rounded-cartao border border-linha bg-folha2 px-4 py-3.5 text-[13px] leading-relaxed text-tinta2">
            <p>Olá, [nome].</p>
            <p className="mt-2.5">
              Escrevo para te contar, como é meu dever, que houve um incidente de
              segurança no sistema que uso para organizar os atendimentos, e que
              dados seus podem ter sido atingidos.
            </p>
            <p className="mt-2.5">
              <b className="font-medium">O que pode ter sido acessado:</b> [lista
              específica — seu nome e telefone; as datas dos seus atendimentos; o
              registro do acompanhamento].
            </p>
            <p className="mt-2.5">
              <b className="font-medium">Quando eu soube:</b> [data].
            </p>
            <p className="mt-2.5">
              <b className="font-medium">O que já foi feito:</b> [medidas].
            </p>
            <p className="mt-2.5">
              <b className="font-medium">O que isso pode significar para você:</b>{" "}
              [riscos concretos, sem minimizar e sem dramatizar].
            </p>
            <p className="mt-2.5">
              Estou à disposição para conversar sobre isso, e você tem o direito
              de pedir uma cópia do seu registro a qualquer momento.
            </p>
            <p className="mt-2.5">[nome], CRP [número]</p>
          </div>
          <p>
            A norma pede{" "}
            <b className="font-medium">linguagem simples e comunicação
            individual</b>{" "}
            — não é estilo, é o art. 9º. E o modelo deliberadamente não pede
            desculpas em três parágrafos, não explica a arquitetura do sistema e
            não sugere que a pessoa não precisa se preocupar: quem decide isso é
            ela.
          </p>
          <p>
            Para a sua comunicação à ANPD, a parte técnica — o que foi atingido,
            quais medidas existiam antes e depois, qual foi a causa — eu escrevo
            para você. É a parte que só eu tenho como responder.
          </p>
        </Bloco>

        <Bloco titulo="5. O que eu faço nas primeiras horas">
          <p>
            Nesta ordem, e a ordem tem motivo:{" "}
            <b className="font-medium">anotar a hora</b> em que soube; cortar o
            caminho do incidente rotacionando as credenciais;{" "}
            <b className="font-medium">congelar os registros</b> antes que eles
            rotacionem sozinhos; e só então delimitar o que foi atingido, conta
            por conta.
          </p>
          <p>
            Derrubar o produto não é a primeira medida, e isso é decisão: uma
            psicóloga que não abre a agenda no meio da manhã tem paciente na
            porta. Cortar o caminho vem antes de cortar o acesso de quem está
            trabalhando.
          </p>
          <p>
            E cada psicóloga afetada recebe um aviso{" "}
            <b className="font-medium">com o que aconteceu na conta dela</b>, e
            não uma nota geral dizendo que “algumas contas podem ter sido
            afetadas” — isso transferiria para dezenas de pessoas a tarefa de
            descobrir se são elas.
          </p>
        </Bloco>

        <Bloco titulo="6. Perder dado também é incidente">
          <p>
            A LGPD fala em acesso não autorizado{" "}
            <em>e em situações acidentais ou ilícitas de destruição, perda,
            alteração, comunicação ou difusão</em>. Perder registro é o caso mais
            óbvio de perda — e, num sistema que guarda prontuário, é o pior dos
            três cenários previstos no plano.
          </p>
          <p>
            Se acontecer, você recebe <b className="font-medium">o que foi
            perdido, com precisão</b> — quais dias, quais registros. A guarda de
            cinco anos é obrigação sua perante o Conselho, e uma comunicação
            vaga aqui te impediria de reconstruir o que falta.
          </p>
          <p>
            O que existe hoje contra isso está escrito, com número, na{" "}
            <Link
              href="/seguranca"
              className="underline underline-offset-2 hover:text-vaga"
            >
              página de segurança
            </Link>
            : backup diário, sete dias de retenção, e o que a granularidade
            diária custa no pior caso.
          </p>
        </Bloco>

        <Bloco titulo="7. O que este plano não promete">
          <p>
            <b className="font-medium">Não existe SLA de disponibilidade aqui.</b>{" "}
            Prometer um tempo no ar que não se mede é a mesma classe de frase que
            “seus dados estão 100% seguros” — não significa nada, e vira citação
            de e-mail no dia do incidente.
          </p>
          <p>
            E não há promessa de que não vai acontecer. Há um plano escrito para
            quando acontecer, e a parte dele que é sua está nesta página.
          </p>
        </Bloco>

        <Bloco titulo="8. Encontrou uma falha?">
          <p>
            Escreva para{" "}
            <a
              href="mailto:oi@sessoes.com.br"
              className="underline underline-offset-2 hover:text-vaga"
            >
              oi@sessoes.com.br
            </a>
            . Todo incidente fica registrado — inclusive o que, depois de
            avaliado, não precisou ser comunicado, e nesse caso com o motivo
            escrito. É exigência da norma, e é o que separa uma decisão de uma
            omissão.
          </p>
          <p>
            Não temos programa de recompensa. Temos o compromisso de não tratar
            quem avisa como problema.
          </p>
        </Bloco>
      </Documento>
    </Moldura>
  );
}
