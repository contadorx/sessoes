import Link from "next/link";
import { Marca } from "@/components/site/Marca";
import { Cascata } from "@/components/site/Cascata";
import { Discricao } from "@/components/site/Discricao";
import { Espera } from "@/components/site/Espera";

/**
 * A landing, depois da auditoria externa e da virada para produção.
 *
 * O QUE MUDOU, E POR QUÊ
 *
 * A versão anterior abria com uma pergunta: *"Vinte e cinco horas de
 * atendimento numa semana comum. Quantas viraram receita?"*. A auditoria
 * apontou o defeito, e ele é grave: a pergunta **cobra da leitora um número
 * que ela não tem**. Para a psicóloga que se descreve como "ruim com
 * números" — que é exatamente quem este produto existe para socorrer —, isso
 * não se lê como diagnóstico, se lê como acusação. A passagem adversarial
 * mostrou a saída dela: *"eu já sei que não controlo isso direito; não quero
 * outro sistema me mostrando que estou administrando mal"*.
 *
 * A hero agora descreve **o problema, não a leitora**. A tese contábil — o
 * destino de cada hora, receita por hora disponível, perda por causa —
 * continua na página inteira e continua sendo a diferenciação real; ela só
 * deixou de carregar a primeira impressão. Isso foi a autorrefutação da
 * própria auditoria, e eu concordo com ela: o problema não é o conceito, é
 * exigir que ele venha antes da prova de que o trabalho diminui.
 *
 * A ORDEM
 *
 *   hero → o mês espalhado → como uma sessão atravessa → o que aconteceu com
 *   o horário → os encaixes → sigilo → CFP → planos → conversa
 *
 * Primeiro o trabalho que some, depois o modelo que explica por quê. A ordem
 * antiga ensinava contabilidade antes de mostrar alívio.
 *
 * O QUE SAIU
 *
 * A lista de espera inteira. O produto está no ar; manter "entrar na lista",
 * "antes de escrever o produto inteiro", "preço em estudo" e "em construção"
 * no rodapé seria falso — e não é uma seção, é a postura da página. O que
 * ficou no lugar é a conversa: continuamos ouvindo psicóloga de verdade, e
 * isso é permanente, não é fase.
 *
 * As promessas absolutas também saíram. "O Pix encontra a sessão sozinho" e
 * "nenhum sistema deste mercado separa essas quatro" eram automações
 * condicionais e afirmações sobre concorrentes vendidas como certezas.
 * `conciliar_pagamento` casa pagador com sessão **quando dá** — e quando não
 * dá, gera divergência, que é o comportamento honesto e é o que a página
 * passa a descrever.
 */

function Secao({
  id,
  rotulo,
  titulo,
  linha,
  children,
  fundo = "papel",
}: {
  id?: string;
  rotulo: string;
  titulo: string;
  linha?: string;
  children?: React.ReactNode;
  fundo?: "papel" | "folha";
}) {
  return (
    <section
      id={id}
      className={`scroll-mt-16 border-t border-linha ${fundo === "folha" ? "bg-folha2" : ""}`}
    >
      <div className="mx-auto max-w-5xl px-5 py-14 sm:px-8 sm:py-20">
        <span className="rotulo">{rotulo}</span>
        <h2 className="mt-2 max-w-[24ch] font-serif text-[27px] leading-[1.18] tracking-[-0.015em] text-balance sm:text-[34px]">
          {titulo}
        </h2>
        {linha && (
          <p className="mt-3 max-w-[62ch] text-[14.5px] leading-relaxed text-tinta2">
            {linha}
          </p>
        )}
        {children && <div className="mt-8">{children}</div>}
      </div>
    </section>
  );
}

function Cartao({
  titulo,
  children,
}: {
  titulo: string;
  children: React.ReactNode;
}) {
  return (
    <div className="rounded-cartao border border-linha bg-folha p-5">
      <h3 className="font-serif text-[19px] leading-snug text-tinta">{titulo}</h3>
      <p className="mt-2 text-[13.5px] leading-relaxed text-tinta2">{children}</p>
    </div>
  );
}

/**
 * Os quatro planos ficam — decisão do Leandro, e ela é coerente com estar em
 * produção: um produto que cobra precisa dizer quanto custa.
 *
 * O que saiu foi o selo "a maioria" no Solo. Ele afirmava um fato sobre uma
 * base de clientes que ainda está se formando, e uma página que inventa
 * consenso social gasta a credibilidade que as outras seções levantam.
 *
 * "Pacientes sem limite" desceu de destaque: é argumento de preço, não de
 * resultado — quem escolhe software por isso está comparando planilha com
 * planilha.
 */
const PLANOS = [
  {
    nome: "Grátis",
    preco: "R$ 0",
    detalhe: "para sempre",
    linhas: [
      "Agenda, prontuário e o registro do que aconteceu com cada horário",
      "Lembrete de véspera e aviso de desmarque, sem limite",
      "Pacientes sem limite",
      "60 mensagens de fila e cobrança por mês",
    ],
  },
  {
    nome: "Solo",
    preco: "R$ 69",
    detalhe: "por mês",
    destaque: true,
    linhas: [
      "Receita por hora disponível e o que aconteceu com cada horário",
      "Fila e cobrança sem teto de mensagens",
      "Pix comparado com as sessões previstas",
      "Cobrança proposta com a política congelada",
      "Modo Receita Saúde e pasta do contador",
    ],
  },
  {
    nome: "Pro",
    preco: "R$ 129",
    detalhe: "por mês",
    linhas: [
      "Tudo do Solo",
      "NFS-e e a ramificação PJ, sem pendência falsa",
      "Página do paciente: confirmar, pagar e receber documento — sem nenhum campo clínico",
      "Acesso separado para secretaria e administração",
    ],
  },
  {
    nome: "Clínica",
    preco: "R$ 249",
    detalhe: "+ R$ 39 por profissional",
    linhas: [
      "Repasse e demonstrativo",
      "Agenda de salas",
      "Fiscal consolidado",
      "Sigilo entre profissionais por construção",
    ],
  },
];

const FRONTEIRAS = [
  [
    "Não entramos na sala.",
    "Nada de gravar paciente, transcrever sessão ou IA opinando sobre diagnóstico, conduta ou risco.",
  ],
  [
    "Não opinamos sobre frequência.",
    "O Código de Ética veda induzir alguém a recorrer aos seus serviços e prolongar desnecessariamente o atendimento. Nenhuma tela aqui sugere que alguém podia vir mais vezes.",
  ],
  [
    "Não reativamos ex-paciente, e não damos desconto para vender horário parado.",
    "Preço não é propaganda, e vínculo clínico não é lista de remarketing.",
  ],
  [
    "Não vendemos pacientes.",
    "Não somos marketplace, não rankeamos profissional e não intermediamos demanda.",
  ],
  [
    "A fila não é leilão.",
    "A regra de prioridade é clínica e é sua. Dinheiro não compra posição.",
  ],
  [
    "O contador vê finanças, nunca clínica. E quem trabalha com você também.",
    "Acesso clínico é uma decisão separada do cargo: quem marca a agenda não precisa ler a sessão. Minimização de dados por construção, não por promessa.",
  ],
];

export default function Home() {
  return (
    <>
      {/* ---------------- topo ---------------- */}
      <header className="sticky top-0 z-20 border-b border-linha bg-folha/85 backdrop-blur">
        <div className="mx-auto flex max-w-5xl items-center gap-4 px-5 py-3 sm:px-8">
          <Marca className="text-[21px]" />
          <span className="hidden text-[12px] text-tinta3 sm:inline">
            a parte do consultório que não é atender
          </span>
          <a
            href="#cfp"
            className="ml-auto hidden text-[12.5px] font-medium text-tinta2 transition-colors hover:text-vaga sm:inline"
          >
            CFP e sigilo
          </a>
          <a
            href="#planos"
            className="hidden text-[12.5px] font-medium text-tinta2 transition-colors hover:text-vaga sm:inline"
          >
            Preço
          </a>
          <Link
            href="/entrar"
            className="rounded-full border border-linha2 px-4 py-1.5 text-[12.5px] font-medium text-tinta2 transition-colors hover:border-vaga hover:text-vaga"
          >
            Entrar
          </Link>
        </div>
      </header>

      <main>
        {/* ---------------- hero ----------------

            Descreve o problema, não a leitora. A versão anterior perguntava
            quantas horas viraram receita — e cobrava um número que ela não
            tem, de alguém que já se sente mal com números. */}
        <section className="mx-auto max-w-5xl px-5 pb-14 pt-14 sm:px-8 sm:pb-20 sm:pt-24">
          <h1 className="max-w-[19ch] font-serif text-[38px] leading-[1.08] tracking-[-0.022em] text-balance sm:text-[62px]">
            Sua agenda diz uma coisa. O Pix, outra. No fim do mês, o <Marca />{" "}
            junta tudo.
          </h1>

          <p className="mt-6 max-w-[60ch] text-[16px] leading-relaxed text-tinta2 sm:text-[17px]">
            Você registra o atendimento uma vez. O <Marca /> acompanha o que foi
            realizado, o que já foi pago, o que ficou a receber, os recibos
            necessários e o que precisa chegar ao contador.
          </p>

          <p className="mt-3 max-w-[56ch] text-[14.5px] leading-relaxed text-tinta3">
            Tudo o que não é atender — sem transformar seu consultório num
            painel financeiro.
          </p>

          <div className="mt-8 flex flex-wrap items-center gap-4">
            <Link
              href="/entrar"
              className="rounded-full bg-vaga px-6 py-3 text-[13.5px] font-semibold text-white transition-opacity hover:opacity-90"
            >
              Começar de graça
            </Link>
            <a
              href="#mes"
              className="text-[13.5px] font-medium text-tinta2 underline decoration-linha2 underline-offset-4 transition-colors hover:text-vaga"
            >
              Ver como um mês inteiro funciona
            </a>
          </div>

          <p className="mt-4 max-w-[56ch] text-[12.5px] leading-relaxed text-tinta3">
            O plano Grátis não expira e não pede cartão. Agenda, prontuário e o
            registro do mês são dele; o que se cobra é o trabalho que o sistema
            faz no seu lugar.
          </p>
        </section>

        {/* ---------------- o mês espalhado ----------------

            Primeira seção depois da hero: o trabalho que some. A tese contábil
            vem depois — ensinar o modelo antes de mostrar alívio era o que
            fazia a página parecer um curso de gestão. */}
        <Secao
          id="mes"
          rotulo="O mês"
          titulo="O mês não fecha porque a conta está em cinco lugares."
          linha="Agenda num app, pagamento no extrato, recibo no site da Receita, controle numa planilha e o resto no WhatsApp. Aqui a sessão carrega tudo — quem confirmou, quem pagou, quem tem recibo, o que ficou a receber."
          fundo="folha"
        >
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <Cartao titulo="O Pix é comparado com as sessões previstas">
              Quando o valor e a referência batem, o pagamento é identificado
              sozinho. Quando não batem — pagamento sem sessão, sessão sem
              pagamento, valor diferente do combinado —, vira uma linha numa
              lista de divergências, para você resolver em trinta segundos em
              vez de conferir o extrato inteiro no fim do dia.
            </Cartao>
            <Cartao titulo="A política vem congelada na sessão">
              Vinte e quatro horas, cinquenta por cento — o que você combinou, na
              versão que valia <em>naquele dia</em>. O sistema propõe a cobrança
              com essa política e o histórico; quem confirma, perdoa ou ajusta é
              você. Exceção clínica não é decidível por regra.
            </Cartao>
            <Cartao titulo="A cobrança segue o ritmo que você definiu">
              O lembrete de pagamento em atraso não vem de você. Vem da agenda,
              no dia que você escolheu, no mesmo texto neutro — e parando
              sozinho. É para você não precisar puxar o assunto.
            </Cartao>
            <Cartao titulo="Receita Saúde, com a ramificação certa">
              A obrigação é de quem atende como pessoa física. Tratar como
              universal gera pendência falsa em toda conta PJ — e o recibo
              errado tem dez dias para ser corrigido.
            </Cartao>
            <Cartao titulo="No fim do mês, o contador recebe pronto">
              Receitas, estornos, recibos, taxas e pendências no formato que ele
              pede. Finanças, nunca prontuário.
            </Cartao>
            <Cartao titulo="Do jeito que você cobra">
              Por sessão, mensalidade fixa ou pacote fechado — com regra clara
              para o mês de cinco semanas e para a falta dentro da mensalidade.
            </Cartao>
          </div>
        </Secao>

        {/* ---------------- o registro único ---------------- */}
        <Secao
          rotulo="Um registro, não seis tarefas"
          titulo="Você registra a sessão uma vez. O restante acompanha esse registro."
          linha="Marcar que a sessão aconteceu é o único gesto obrigatório do dia. Dele saem a cobrança, o lembrete de pagamento, a linha do recibo, o número que o contador precisa e o fechamento do mês — como consequência do registro, e não como cinco tarefas novas que aparecem depois."
        >
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <Cartao titulo="A sessão responde por si">
              Registrar o que aconteceu, ver cobrança e pagamento, enviar ou
              pausar o lembrete, emitir documento, consultar reposição e ver o
              que falta para fechar — tudo no painel da própria sessão, sem
              atravessar módulo nenhum.
            </Cartao>
            <Cartao titulo="Campos pendentes aparecem antes de concluir">
              O Manual do CFP pede que não se deixe espaço em branco no
              prontuário. Aqui o que falta fica visível <em>antes</em> de você
              concluir o registro, em vez de sumir da tela — a lacuna que você
              não vê é a que fica.
            </Cartao>
            <Cartao titulo="Cinco eixos, não um estado">
              Num sistema comum, &ldquo;paga&rdquo; não diz se foi realizada,
              &ldquo;cancelada&rdquo; não diz se houve receita e
              &ldquo;remarcada&rdquo; não diz se consumiu outra hora. Aqui a
              sessão carrega os cinco separados: agenda, confirmação, pagamento,
              fiscal e o que aconteceu com o horário.
            </Cartao>
          </div>
        </Secao>

        {/* ---------------- o que aconteceu com o horário ----------------

            Os quatro rótulos foram trocados. "Perdida — não produziu nada" era
            punitivo sobre uma ausência que pode ter razão clínica, e os quatro
            antigos misturavam duas dimensões que a própria página diz serem
            separadas: o que aconteceu com o horário e o que aconteceu com o
            pagamento. */}
        <Secao
          id="destino"
          rotulo="O registro do mês"
          titulo="O que aconteceu com o horário — sem misturar com o pagamento."
          linha="Quatro situações, e elas não se confundem: um horário realizado pode estar pago ou a receber, e um horário que não foi ocupado é um fato da agenda, não um julgamento sobre você ou sobre o paciente. A reposição é a conta que ninguém faz — duas horas de capacidade, uma receita só —, e é onde a receita some sem ninguém perceber."
          fundo="folha"
        >
          <dl className="grid gap-px overflow-hidden rounded-cartao border border-linha bg-linha sm:grid-cols-2 lg:grid-cols-4">
            {[
              {
                r: "Realizada e recebida",
                c: "text-cheia",
                n: "a sessão aconteceu e o pagamento foi identificado",
              },
              {
                r: "Realizada, a receber",
                c: "text-aviso",
                n: "o atendimento aconteceu e o pagamento ainda não entrou",
              },
              {
                r: "Horário não ocupado",
                c: "text-vaga",
                n: "o horário existia na agenda e ninguém o ocupou — pode ter razão clínica, e o registro não opina",
              },
              {
                r: "Reposição realizada",
                c: "text-vaga",
                n: "você deu outro horário pelo mesmo dinheiro — duas horas, uma receita",
              },
            ].map((i) => (
              <div key={i.r} className="bg-folha px-5 py-5">
                <dt className={`font-serif text-[17px] leading-snug ${i.c}`}>{i.r}</dt>
                <dd className="mt-1.5 text-[12.5px] leading-relaxed text-tinta3">
                  {i.n}
                </dd>
              </div>
            ))}
          </dl>

          <p className="mt-6 max-w-[70ch] text-[13px] leading-relaxed text-tinta2">
            Com as quatro separadas, dois números passam a existir e a fazer
            sentido juntos: <b className="font-medium text-tinta">receita por hora disponível</b> e{" "}
            <b className="font-medium text-tinta">a causa de cada horário não ocupado</b>. Ocupação
            subindo com receita por hora caindo é sintoma, não sucesso — e só se
            enxerga com os dois lado a lado. Antecipado, aliás, não é atendido:
            receber por uma sessão que ainda não aconteceu entra como pago e não
            como receita reconhecida.
          </p>
        </Secao>

        {/* ---------------- os encaixes ---------------- */}
        <Secao
          id="encaixes"
          rotulo="Quando um horário abre"
          titulo="O horário é oferecido a quem pediu para ser avisado, no valor combinado."
          linha="Uma pessoa por vez, na ordem que você definiu, e a primeira que responder fica com o horário. Não é leilão e não tem desconto: quem entra paga o mesmo que já estava combinado. Se ninguém quiser, o horário fica registrado como não ocupado — e aparece na conta do mês pelo nome."
        >
          <Cascata />
          <p className="mt-6 max-w-[70ch] text-[12.5px] leading-relaxed text-tinta3">
            <b className="font-medium text-tinta2">
              E não prometemos que isso enche a sua agenda.
            </b>{" "}
            Enquanto não houver medida de que existe gente querendo as horas que
            vagam, prometer ocupação é vender hipótese. Estamos medindo isso num
            levantamento aberto, com o método publicado antes da coleta — e o
            resultado sai mesmo se for contra nós.
          </p>
        </Secao>

        {/* ---------------- discrição ---------------- */}
        <Secao
          rotulo="Sigilo"
          titulo="A mensagem que não expõe o seu paciente."
          linha="Um lembrete aparece na tela bloqueada — que pode estar na mesa da cozinha, na mão do marido, do pai, do chefe. Aqui a discrição é a posição padrão, não uma opção escondida nas configurações."
          fundo="folha"
        >
          <Discricao />
        </Secao>

        {/* ---------------- o CFP ----------------

            O título anterior — "A conformidade com o CFP é sua. O sistema
            existe para você não ter que pensar nela." — prometia eliminar uma
            decisão que não se terceiriza, e prometia isso na seção destinada a
            tranquilizar quem é atenta às obrigações profissionais. Justamente
            ela é quem perceberia a contradição. */}
        <Secao
          id="cfp"
          rotulo="As regras da profissão"
          titulo="A responsabilidade profissional continua sendo sua. O sistema reduz o trabalho de cumpri-la."
          linha="Nenhum software assume a responsabilidade da psicóloga pelo prontuário — quem disser o contrário está vendendo o que não pode entregar. O que dá para fazer é organizar registros, prazos, acessos e correções para que o cumprimento não dependa de memória nem de uma revisão apressada no fim do mês. O sistema orienta o caminho e preserva o histórico; a decisão profissional continua com você."
        >
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <Cartao titulo="O prontuário nos blocos que o Manual pede">
              Identificação, avaliação da demanda, evolução e encerramento — a
              estrutura da Resolução 001/2009 com a linguagem do Manual
              Orientativo de novembro de 2025, não um campo de texto livre com
              outro nome.
            </Cartao>
            <Cartao titulo="Evolução que não se apaga — e que se corrige">
              O que foi registrado fica com a data em que foi registrado.
              Correção não é proibida: ela entra como acréscimo datado, com a
              data em que chegou, sem apagar o histórico. Um registro que se
              reescreve por cima não é registro, é a versão de hoje da história.
            </Cartao>
            <Cartao titulo="Campos obrigatórios pendentes ficam visíveis">
              O Manual pede que não se deixe espaço em branco no prontuário.
              Aqui a seção que falta aparece antes de você concluir o registro,
              em vez de sumir da tela.
            </Cartao>
            <Cartao titulo="Cinco anos, e do menor conta da maioridade">
              O prazo de guarda é calculado por ficha, e o sistema recusa apagar
              o que ainda está dentro dele. Quando o paciente é menor, o relógio
              começa quando ele completa dezoito.
            </Cartao>
            <Cartao titulo="Trilha de quem viu o quê">
              Cada abertura de prontuário fica registrada, e a trilha é sua —
              não um log interno nosso. É o que permite responder com fato, e
              não com memória, se alguém perguntar.
            </Cartao>
            <Cartao titulo="Nosso suporte não vê prontuário">
              É limitação escrita no código, com teste automático que reprova a
              alteração se alguma função de suporte encostar em prontuário,
              evolução ou anamnese. Vemos conta, plano e erro técnico. Para
              recuperar acesso, agimos sobre a conta e o login — nunca abrindo o
              conteúdo clínico. Se um incidente exigir mais que isso, você é
              avisada antes, e a trilha registra.
            </Cartao>
          </div>

          <p className="mt-6 max-w-[74ch] text-[12.5px] leading-relaxed text-tinta3">
            Base normativa: <b className="font-medium text-tinta2">Resolução CFP nº 001/2009</b> (prontuário
            psicológico e guarda), <b className="font-medium text-tinta2">Resolução CFP nº 06/2019</b> (documentos
            escritos), <b className="font-medium text-tinta2">Resolução CFP nº 09/2024</b> (atendimento por
            tecnologias) e o <b className="font-medium text-tinta2">Manual Orientativo de nov/2025</b>, que é o
            texto que traz os quadros comparativos e a distinção entre prontuário
            e registro documental. Conferimos as quatro em 01/09/2026, e o que
            estiver desatualizado aqui é erro nosso — se você encontrar, escreva.
          </p>
        </Secao>

        {/* ---------------- fronteiras ---------------- */}
        <Secao
          rotulo="As linhas que não atravessamos"
          titulo="O Sessões vive fora da sala, e não opina sobre a clínica."
          linha="Um software que administra a agenda, o dinheiro e a papelada — e que nunca entra na sessão nem sugere o que fazer com um paciente. Isto não é promessa de marketing: são decisões de arquitetura, escritas antes da primeira linha de código, e algumas delas vêm direto do Código de Ética."
          fundo="folha"
        >
          <div className="grid gap-px overflow-hidden rounded-cartao border border-linha bg-linha sm:grid-cols-2">
            {FRONTEIRAS.map(([t, d]) => (
              <div key={t} className="bg-folha px-5 py-5">
                <h3 className="font-serif text-[18px] leading-snug text-tinta">{t}</h3>
                <p className="mt-1.5 text-[13px] leading-relaxed text-tinta2">{d}</p>
              </div>
            ))}
          </div>
          <p className="mt-5 max-w-[70ch] text-[12.5px] leading-relaxed text-tinta3">
            Prontuário é dado pessoal sensível. Criptografia, trilha de quem viu
            o quê, prazo de guarda declarado e portabilidade dos dois lados: você
            sai levando os seus dados, e o paciente recebe os dele — que é um
            direito.
          </p>
        </Secao>

        {/* ---------------- planos ---------------- */}
        <Secao
          id="planos"
          rotulo="Planos"
          titulo="O que é registro é de graça. O que se cobra é o trabalho que o sistema faz no seu lugar."
          linha="A regra do cardápio é uma só, e ela decide todo item desta tabela: o Grátis dá tudo o que é registro — agenda, prontuário, o que aconteceu com cada horário, pacientes sem limite — e o que se cobra é a máquina trabalhando por você: a fila que oferece sozinha, a régua que cobra sem você mandar a mensagem, o Pix conferido, o mês montado para o contador. Lembrete de véspera e aviso de desmarque nunca entram em teto nenhum, em plano nenhum: quem ficaria sem eles é o paciente."
        >
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {PLANOS.map((p) => (
              <div
                key={p.nome}
                className={`flex flex-col rounded-cartao border bg-folha p-5 ${
                  p.destaque ? "border-vaga-linha ring-1 ring-vaga-linha" : "border-linha"
                }`}
              >
                <span className="font-serif text-[20px] text-tinta">{p.nome}</span>
                <span className="tabular mt-3 font-mono text-[26px] font-medium leading-none text-tinta">
                  {p.preco}
                </span>
                <span className="mt-1 text-[12px] text-tinta3">{p.detalhe}</span>
                <ul className="mt-4 flex flex-col gap-2 border-t border-linha pt-4">
                  {p.linhas.map((l) => (
                    <li
                      key={l}
                      className="grid grid-cols-[12px_minmax(0,1fr)] gap-2 text-[12.5px] leading-snug text-tinta2"
                    >
                      <span className="text-cheia">·</span>
                      <span>{l}</span>
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>

          <p className="mt-6 max-w-[70ch] text-[12.5px] leading-relaxed text-tinta3">
            Sem contrato de fidelidade e sem cobrança de saída. Você exporta
            tudo — pacientes, sessões, prontuários, documentos e registros
            financeiros — em formato aberto, a qualquer momento, sem pedir para
            ninguém.
          </p>
        </Secao>

        {/* ---------------- a conversa ----------------

            Era a lista de espera. O produto está no ar, então isto deixou de
            ser um portão e virou o que sempre foi de verdade: continuar
            ouvindo quem usa. */}
        <section id="conversa" className="scroll-mt-16 border-t border-linha bg-folha2">
          <div className="mx-auto max-w-3xl px-5 py-16 sm:px-8 sm:py-24">
            <span className="rotulo">Conversa</span>
            <h2 className="mt-2 max-w-[24ch] font-serif text-[29px] leading-[1.15] tracking-[-0.015em] text-balance sm:text-[38px]">
              Estamos sempre ouvindo psicólogas de verdade para reduzir o
              trabalho que não é atendimento.
            </h2>
            <p className="mt-3 max-w-[58ch] text-[14.5px] leading-relaxed text-tinta2">
              Cada tela daqui saiu de uma conversa com quem fecha o mês. Se você
              quiser conversar vinte minutos sobre como é o seu mês de verdade —
              onde a conta trava, e o que você já resolve numa planilha —, deixe
              seu e-mail. Não é requisito para usar: a conta se cria agora, de
              graça.
            </p>
            <div className="mt-8">
              <Espera />
            </div>
            <p className="mt-6 text-[13px] text-tinta2">
              Ou{" "}
              <Link
                href="/entrar"
                className="font-medium text-vaga underline decoration-vaga-linha underline-offset-4"
              >
                criar sua conta agora
              </Link>{" "}
              — leva um minuto, e o plano Grátis não expira.
            </p>
          </div>
        </section>
      </main>

      {/* ---------------- rodapé ---------------- */}
      <footer className="border-t border-linha bg-folha">
        <div className="mx-auto flex max-w-5xl flex-col gap-3 px-5 py-8 text-[12px] text-tinta3 sm:flex-row sm:items-center sm:px-8">
          <Marca className="text-[16px]" />
          {/* "Feito por um contador que resolveu olhar a conta do consultório"
              reforçava autoridade financeira e, junto com ela, o medo de
              fiscalização. O que a psicóloga quer não é um contador olhando a
              conta dela — é não precisar olhar. */}
          <span className="max-w-[52ch] text-tinta2">
            Feito por um contador para tirar a conferência do caminho de quem
            atende.
          </span>
          <span className="sm:ml-auto">
            São Paulo ·{" "}
            <a
              href="mailto:oi@sessoes.com.br"
              className="underline decoration-linha2 underline-offset-2 transition-colors hover:text-vaga"
            >
              oi@sessoes.com.br
            </a>
          </span>
        </div>
      </footer>
    </>
  );
}
