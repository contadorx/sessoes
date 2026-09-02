import Link from "next/link";
import { Moldura, Documento, Bloco } from "@/components/site/Moldura";

export const metadata = {
  title: "Segurança",
  description:
    "Isolamento entre contas no banco, separação de acesso clínico e financeiro, retenção de backup e o que ainda não está pronto.",
};

/**
 * A página de segurança.
 *
 * **O que ela evita:** "seus dados estão 100% seguros", cadeados, selos e
 * qualquer adjetivo que não possa ser conferido. Está na lista do doc 18 do que
 * não se escreve, e o motivo é prático: uma frase dessas não significa nada e
 * envelhece mal — no dia de um incidente, ela vira a citação do e-mail que a
 * cliente vai mandar.
 *
 * **E ela tem uma seção do que ainda não está pronto.** Essa é a parte que
 * quase nenhum concorrente publica, e é a que decide a credibilidade da página
 * inteira: uma lista só de acertos se lê como material de venda. As duas
 * ausências declaradas aqui (PITR e a tela da trilha) são as mesmas que estão
 * escritas no diário do projeto, com a mesma razão.
 */
export default function Seguranca() {
  return (
    <Moldura>
      <Documento
        titulo="Segurança"
        atualizado="1º de setembro de 2026"
        resumo="O que está construído, como dá para conferir, e o que ainda não está pronto — com número, e sem adjetivo."
      >
        <Bloco titulo="1. Uma conta não enxerga a outra, e isso está no banco">
          <p>
            O isolamento entre contas não é uma condicional no código da tela: é
            uma política de segurança em nível de linha, dentro do banco de
            dados. Toda leitura e toda escrita passam por ela, inclusive as que
            um erro nosso fizesse pela porta errada.
          </p>
          <p>
            Isso é conferido por uma suíte de testes adversariais que roda a cada
            alteração e que tenta, de propósito, fazer o sistema fazer o que ele
            não deve: ler a agenda de outra conta, forjar um carimbo de data,
            reescrever um documento emitido, apagar um registro dentro do prazo
            de guarda. Hoje são mais de vinte suítes e mais de setecentos testes
            automáticos.
          </p>
        </Bloco>

        <Bloco titulo="2. Quem trabalha com você não vê o que não precisa ver">
          <p>
            Numa clínica, secretária e administração existem para tirar trabalho
            de cima de quem atende — e nenhuma das duas precisa ler prontuário
            para marcar uma hora ou emitir um recibo.
          </p>
          <p>
            Acesso clínico e acesso financeiro são{" "}
            <b className="font-medium">duas decisões separadas</b>, e nenhuma
            delas vem junto com o cargo. A secretária não lê evolução, anamnese
            nem registro; quem cuida do financeiro não lê nada clínico; e a
            profissional lê o que é dela.
          </p>
          <p>
            A separação vive na mesma camada do isolamento entre contas, e não na
            interface. A diferença aparece na exportação: se a secretária baixar
            a exportação inteira da conta, o arquivo sai{" "}
            <b className="font-medium">sem</b> o conteúdo clínico — não porque a
            tela esconda, mas porque a consulta não enxergou. Um arquivo que vaza
            é a forma mais silenciosa desse erro, e é a que tem teste.
          </p>
          <p>
            E ninguém concede permissão a si mesmo: quem concede acesso clínico é
            a responsável pela conta, e nem ela pode se conceder o que já não
            tem.
          </p>
        </Bloco>

        <Bloco titulo="3. Quem abriu o quê fica registrado">
          <p>
            Toda leitura de ficha e toda exportação entram numa trilha com autor,
            data e ação. O carimbo é do servidor: uma tentativa de gravar outra
            data é reescrita com a hora real, e a trilha não aceita edição nem
            exclusão — nem pela conta que a gerou.
          </p>
          <p>
            A tela em que você lê a sua própria trilha ainda não existe. Está na
            lista do item 6 desta página.
          </p>
        </Bloco>

        <Bloco titulo="4. As cópias de segurança, com prazo">
          <p>
            Cópias automáticas diárias, cifradas, com{" "}
            <b className="font-medium">7 dias</b> de retenção — e depois desse
            prazo elas expiram e são destruídas automaticamente. É o mesmo número
            que está na{" "}
            <Link href="/privacidade" className="underline underline-offset-2 hover:text-vaga">
              política de privacidade
            </Link>
            , e ele vale para o dado que você apagou também.
          </p>
          <p>
            A granularidade é diária, e é honesto dizer o que isso custa: uma
            falha de infraestrutura pode custar até 24 horas de registro. A
            recuperação a ponto no tempo, que reduziria isso a minutos, é um
            serviço adicional caro e entra quando houver receita que o pague. Até
            lá o risco é de até um dia — não de tudo.
          </p>
        </Bloco>

        <Bloco titulo="5. O que o sistema recusa fazer, e continua recusando">
          <p>
            Algumas portas estão fechadas de um jeito que não depende de alguém
            lembrar de mantê-las fechadas:
          </p>
          <p>
            Não existe função que emita documento na Receita Federal por você — e
            existe um teste que falha se alguém criar uma com esse nome.
          </p>
          <p>
            Não existe caminho público para a anamnese: nenhum link, nenhum
            token, nenhuma função que a devolva por endereço. A anamnese é da
            sala, não de um formulário respondido às onze da noite.
          </p>
          <p>
            Não existe coluna de dinheiro em fila nenhuma, e há um teste de
            estrutura que reprova quem acrescentar uma. A ordem é a de chegada.
          </p>
          <p>
            Documento emitido não se edita, e cancelar queima o número. Evolução
            não se reescreve por cima: correção entra como acréscimo datado.
            Anamnese fechada não reabre — o que chega depois é adendo, com a data
            em que chegou.
          </p>
        </Bloco>

        <Bloco titulo="6. O que ainda não está pronto">
          <p>
            Esta seção existe porque uma lista só de acertos se lê como material
            de venda.
          </p>
          <p>
            <b className="font-medium">A tela da sua trilha de acesso.</b> A
            trilha é gravada e é imutável desde o começo; a tela em que você a lê
            está sendo construída. Enquanto isso, ela sai na exportação da conta.
          </p>
          <p>
            <b className="font-medium">Recuperação a ponto no tempo.</b> Ver o
            item 4: a granularidade hoje é diária.
          </p>
          <p>
            <b className="font-medium">
              Verificação em duas etapas para entrar.
            </b>{" "}
            Ainda não está disponível. Enquanto isso, a recomendação vale mais
            que o normal: use uma senha longa e que não exista em outro lugar.
          </p>
        </Bloco>

        <Bloco titulo="7. Encontrou uma falha?">
          <p>
            Escreva para{" "}
            <a
              href="mailto:oi@sessoes.com.br"
              className="underline underline-offset-2 hover:text-vaga"
            >
              oi@sessoes.com.br
            </a>{" "}
            com o que você viu e como reproduzir. Respondemos, corrigimos, e
            dizemos o que foi feito — e se a falha tiver exposto dado de alguém,
            avisamos quem foi afetado.
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
