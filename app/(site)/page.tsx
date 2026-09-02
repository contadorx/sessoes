import Link from "next/link";
import { Marca } from "@/components/site/Marca";
import { Cascata } from "@/components/site/Cascata";
import { Discricao } from "@/components/site/Discricao";
import { Espera } from "@/components/site/Espera";
import { Telas } from "@/components/site/Telas";
import { UltimosTextos } from "@/components/site/UltimosTextos";
import { RodapeDoSite } from "@/components/site/Moldura";
import { Confirmar } from "@/components/app/Confirmar";
import {
  AgendaEExtrato,
  FiguraEditorial,
  GlifoDoDestino,
  FolhaDoProntuario,
  Fio,
} from "@/components/site/Figuras";

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
      <div className="mx-auto max-w-5xl px-5 py-12 sm:px-8 sm:py-16">
        <span className="flex items-center gap-2.5">
          <Fio className="shrink-0" />
          <span className="rotulo">{rotulo}</span>
        </span>
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

/**
 * O que sai da leitura corrida sem sair da página.
 *
 * A segunda auditoria mediu o problema: 31 títulos, ~9.600px, e a tese forte
 * diluída numa sucessão de explicações — *"hoje ela recebe cerca de quinze
 * mensagens concorrentes"*. Mas nada aqui era mentira nem enfeite: era detalhe
 * que a psicóloga cuidadosa vai querer, na hora em que ela quiser.
 *
 * Então o corte não apaga: recolhe. Fica visível o que decide, e a um clique o
 * que confirma. `<details>` nativo — sem JavaScript, e o conteúdo continua no
 * HTML para quem lê com leitor de tela e para quem indexa a página.
 */
function Mais({ rotulo, children }: { rotulo: string; children: React.ReactNode }) {
  return (
    <details className="group mt-6">
      <summary className="inline-flex cursor-pointer list-none items-center gap-1.5 text-[13px] font-medium text-tinta2 underline decoration-linha2 underline-offset-4 transition-colors hover:text-vaga">
        {rotulo}
        <span aria-hidden className="text-[11px] transition-transform group-open:rotate-90">
          ›
        </span>
      </summary>
      <div className="mt-5">{children}</div>
    </details>
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
/**
 * **O que saiu do Pro, e por quê.** A lista dele trazia "acesso separado para
 * secretaria e administração" como recurso pago. A segunda auditoria matou o
 * argumento numa frase: *"não se deve cobrar pela proteção mínima que impede a
 * secretária de ler prontuário"*.
 *
 * E ela está certa, com uma consequência técnica boa: a migração 0049 pôs esse
 * isolamento na **RLS**, não numa condicional de plano — a secretária de uma
 * conta Grátis já não lê evolução hoje, e não haveria como cobrar por isso sem
 * construir de propósito um jeito de desligar a proteção. O que se cobra no
 * Pro passa a ser o que de fato é trabalho a mais: matriz de permissões e
 * aprovação em etapas.
 *
 * **E o Solo ganhou um rótulo factual.** A borda colorida sugeria recomendação
 * sem dizer nada; "a maioria" saiu na primeira auditoria porque afirmava um
 * fato sobre uma base que não existe. O que ficou descreve para quem o plano é,
 * que é verdade no dia em que a primeira pessoa assina.
 */
const PLANOS = [
  {
    nome: "Grátis",
    preco: "R$ 0",
    detalhe: "para sempre",
    cta: "Criar conta grátis",
    href: "/entrar?criar",
    linhas: [
      "Agenda, prontuário e o registro do que aconteceu com cada horário",
      "Lembrete de véspera e aviso de desmarque saem sozinhos, sem limite",
      "Pacientes sem limite",
      "8 sessões por mês",
      "A fila e a cobrança saem do seu WhatsApp, com um toque seu",
    ],
  },
  {
    nome: "Solo",
    preco: "R$ 69",
    detalhe: "por mês",
    destaque: true,
    selo: "para quem atende sozinha",
    // **A escolha deixou de se perder, e o rótulo deixou de mentir.** Os dois
    // botões pagos apontavam para o mesmo `/entrar?criar`, e "Começar no Solo"
    // prometia um começo que não acontece: toda conta nasce no Grátis, porque
    // não existe assinatura self-service — quem abre é uma pessoa (OP5). Agora
    // o plano viaja na URL, aparece de volta na tela de criar conta e vai junto
    // nos metadados do cadastro, onde eu consigo lê-lo. E o rótulo diz o que o
    // clique faz: cria a conta e **pede** o plano.
    cta: "Criar conta e pedir o Solo",
    href: "/entrar?criar&plano=solo",
    // A ordem importa: quem chegou por agenda, Pix e recibo lê o primeiro item
    // como resumo do plano. "Receita por hora disponível" abrindo a lista
    // reintroduzia o vocabulário financeiro que a hero passou a evitar — vai
    // por último, onde é consequência e não porta de entrada.
    linhas: [
      "Pix comparado com as sessões previstas",
      "60 sessões por mês",
      "A fila e a cobrança saem sozinhas, na hora em que a vaga abre",
      "Modo Receita Saúde e pasta do contador",
      "Cobrança proposta com a política congelada",
      "Receita por hora disponível e o que aconteceu com cada horário",
    ],
  },
  {
    nome: "Pro",
    preco: "R$ 129",
    detalhe: "por mês",
    cta: "Criar conta e pedir o Pro",
    href: "/entrar?criar&plano=pro",
    linhas: [
      "Tudo do Solo, sem faixa de sessões",
      "NFS-e e a ramificação PJ, sem pendência falsa",
      "Página do paciente: confirmar, pagar e receber documento — sem nenhum campo clínico",
      "Permissões por pessoa: quem vê o quê, com aprovação em etapas",
    ],
  },
  {
    nome: "Clínica",
    preco: "R$ 249",
    detalhe: "+ R$ 39 por profissional que atende",
    cta: "Conversar sobre a clínica",
    href: "/#conversa",
    linhas: [
      "60 sessões por mês, por profissional que atende",
      "Repasse e demonstrativo",
      "Agenda de salas",
      "Fiscal consolidado",
      "Sigilo entre profissionais por construção",
    ],
  },
];


/**
 * A página inicial passou a ler o banco, e por isso ganhou prazo.
 *
 * A seção dos textos consulta `posts`. Sem `revalidate`, a landing continuaria
 * congelada no build e um texto publicado só apareceria no próximo deploy — o
 * sintoma seria "publiquei e não aconteceu nada", indistinguível de um botão
 * quebrado. As ações do painel já chamam `revalidatePath("/")`, então na
 * prática o texto aparece na hora; estes cinco minutos são a rede de segurança
 * para o dia em que essa chamada falhar sozinha.
 */
export const revalidate = 300;

export default function Home() {
  return (
    <>
      {/* ---------------- topo ---------------- */}
      {/* O "Site URL" do Supabase pode ser a raiz, e nesse caso o link de
          confirmação devolve a pessoa aqui — com a sessão pendurada no
          fragmento da URL, que nenhum componente de servidor enxerga. Sem
          fragmento de autenticação, isto não renderiza nada. */}
      <Confirmar />

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
          {/* "Textos" não dizia se era documentação, normas, blog ou material
              institucional — e num site que fala de CFP e de Receita Federal as
              quatro leituras são plausíveis. "Artigos" é o que está lá. */}
          <Link
            href="/blog"
            className="hidden text-[12.5px] font-medium text-tinta2 transition-colors hover:text-vaga sm:inline"
          >
            Artigos
          </Link>
          {/* Duas ações, e não uma. "Entrar" sozinho no topo parece destinado
              a quem já é cliente — e era a única porta visível para quem
              rolava a página inteira e decidia experimentar no fim. */}
          <Link
            href="/entrar"
            className="text-[12.5px] font-medium text-tinta2 transition-colors hover:text-vaga"
          >
            Já tenho conta
          </Link>
          <Link
            href="/entrar?criar"
            className="rounded-full bg-vaga px-4 py-1.5 text-[12.5px] font-semibold text-white transition-opacity hover:opacity-90"
          >
            Criar conta grátis
          </Link>
        </div>
      </header>

      <main>
        {/* ---------------- hero ----------------

            Descreve o problema, não a leitora. A versão anterior perguntava
            quantas horas viraram receita — e cobrava um número que ela não
            tem, de alguém que já se sente mal com números. */}
        <section className="relative overflow-hidden">
          {/* A ordem do DOM é a ordem do celular: frase, figura, botão. A figura
              entra como prova **antes** da ação — na versão anterior ela ficava
              depois de todo o texto e de todos os botões, ou seja, longe da
              dobra num aparelho de 390px: quem chega pelo telefone via a
              promessa e nunca via o desenho que a sustenta.

              No desktop as três peças voltam ao lugar pelas coordenadas de
              grade: texto em cima à esquerda, botão embaixo à esquerda, figura
              à direita ocupando as duas linhas. */}
          <div className="relative mx-auto grid max-w-5xl gap-8 px-5 pb-14 pt-14 sm:px-8 sm:pb-20 sm:pt-24 lg:grid-cols-[minmax(0,1fr)_minmax(0,400px)] lg:gap-x-14 lg:gap-y-9">
            <div className="lg:col-start-1 lg:row-start-1">
              {/* 46px, não 56. A relação com o logo do cabeçalho (21px) sai de
                  2,7× para 2,2×, e o salto para os títulos de seção (34px)
                  deixa de ser um degrau. Uma hero de cinco linhas em serif
                  pesada não é ênfase — é a página inteira gritando a primeira
                  frase e sussurrando o resto. */}
              {/* **A marca saiu de dentro da frase.** "No fim do mês, o
                  Sessões. junta tudo" põe um ponto final no meio de uma
                  oração, e o leitor não perdoa isso no maior texto da página —
                  lê como erro de digitação, não como assinatura.

                  A regra que fica: "Sessões." com ponto é **assinatura** (topo,
                  rodapé, ícone). Dentro de uma frase, ou o nome vem sem ponto,
                  ou a frase se escreve sem precisar dele. Aqui escolhi a
                  segunda: a hero ganhou um verbo melhor e perdeu a muleta. */}
              <h1 className="max-w-[20ch] font-serif text-[34px] leading-[1.1] tracking-[-0.02em] text-balance sm:text-[46px]">
                Sua agenda diz uma coisa. O Pix, outra. No fim do mês, tudo
                precisa bater.
              </h1>

              <p className="mt-6 max-w-[54ch] text-[16px] leading-relaxed text-tinta2 sm:text-[17px]">
                Você registra o atendimento uma vez. O <Marca peso="texto" /> acompanha o que
                foi realizado, o que já foi pago, o que ficou a receber, os
                recibos necessários e o que precisa chegar ao contador.
              </p>

              <p className="mt-3 max-w-[52ch] text-[14.5px] leading-relaxed text-tinta3">
                Tudo o que não é atender — sem transformar seu consultório num
                painel financeiro.
              </p>

            </div>

            {/* A hero em desenho — e ela mostra também o que não bate, porque
                a copy ao lado promete comparação, não mágica. */}
            <figure className="rounded-cartao border border-linha bg-folha p-4 shadow-[0_1px_0_rgba(31,38,42,0.04)] sm:p-5 lg:col-start-2 lg:row-span-2 lg:row-start-1 lg:self-center">
              <AgendaEExtrato className="h-auto w-full" />
              <figcaption className="mt-3 flex flex-wrap gap-x-4 gap-y-1 border-t border-linha pt-3 text-[11px] text-tinta3">
                <span className="inline-flex items-center gap-1.5">
                  <span className="inline-block h-2 w-2 rounded-[1px] bg-cheia" />
                  pagamento identificado
                </span>
                <span className="inline-flex items-center gap-1.5">
                  <span className="inline-block h-2 w-2 rounded-[1px] bg-aviso" />
                  a resolver
                </span>
                <span className="inline-flex items-center gap-1.5">
                  <span className="inline-block h-2 w-2 rounded-[1px] bg-vaga" />
                  horário não ocupado
                </span>
              </figcaption>
            </figure>

            <div className="lg:col-start-1 lg:row-start-2">
              <div className="flex flex-wrap items-center gap-4">
                <Link
                  href="/entrar?criar"
                  className="rounded-full bg-vaga px-6 py-3 text-[13.5px] font-semibold text-white transition-opacity hover:opacity-90"
                >
                  Criar conta grátis
                </Link>
                <a
                  href="#mes"
                  className="text-[13.5px] font-medium text-tinta2 underline decoration-linha2 underline-offset-4 transition-colors hover:text-vaga"
                >
                  Ver como um mês inteiro funciona
                </a>
              </div>

              <p className="mt-4 max-w-[52ch] text-[12.5px] leading-relaxed text-tinta3">
                O plano Grátis não expira e não pede cartão. Agenda, prontuário
                e o registro do mês são dele; o que se cobra é o trabalho que o
                sistema faz no seu lugar.
              </p>
            </div>
          </div>
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
          {/* A figura antiga era um diagrama de cinco caixas inclinadas, uma
              seta e outra caixa — e a copy acima já dizia exatamente isso. Um
              desenho que repete a frase ao lado não acrescenta nada; ocupa
              altura. Esta mostra a **convergência**: cinco origens diferentes,
              cada uma com a matéria dela, entrando num registro só. */}
          <FiguraEditorial
            className="mb-8 max-w-[720px]"
            src="/figuras/cinco-fontes-um-registro.webp"
            legenda="Agenda, pagamento, recibo, planilha e mensagens deixam de ser conferidos separadamente. A sessão passa a reunir o que aconteceu em cada um deles."
          />

          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <Cartao titulo="O Pix é comparado com as sessões previstas">
              Quando os dados disponíveis permitem uma correspondência segura, o
              pagamento é relacionado à sessão. Os demais — pagamento sem
              sessão, sessão sem pagamento, valor diferente do combinado — ficam
              separados numa lista, para você revisar só as divergências em vez
              de conferir o extrato inteiro no fim do dia.
            </Cartao>
            <Cartao titulo="A cobrança segue o ritmo que você definiu">
              O lembrete de pagamento em atraso não vem de você. Vem da agenda,
              no dia que você escolheu, no mesmo texto neutro. Ele para quando o
              pagamento é identificado, ou quando você interrompe a régua. É
              para você não precisar puxar o assunto.
            </Cartao>
            <Cartao titulo="No fim do mês, o contador recebe pronto">
              Receitas, estornos, recibos, taxas e pendências no formato que ele
              pede. Finanças, nunca prontuário.
            </Cartao>
          </div>

          <Mais rotulo="E também: política de falta, Receita Saúde e formas de cobrar">
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              <Cartao titulo="A política vem congelada na sessão">
                Vinte e quatro horas, cinquenta por cento — o que você combinou, na
                versão que valia <em>naquele dia</em>. O sistema propõe a cobrança
                com essa política e o histórico; quem confirma, perdoa ou ajusta é
                você. Exceção clínica não é decidível por regra.
              </Cartao>
              <Cartao titulo="Receita Saúde só para quem precisa">
                A obrigação é de quem atende como pessoa física. Tratar como
                universal gera pendência falsa em toda conta PJ — e o recibo
                errado tem dez dias para ser corrigido.
              </Cartao>
              <Cartao titulo="Do jeito que você cobra">
                Por sessão, mensalidade fixa ou pacote fechado — com regra clara
                para o mês de cinco semanas e para a falta dentro da mensalidade.
              </Cartao>
            </div>
          </Mais>
        </Secao>

        {/* ---------------- o registro único ---------------- */}
        <Secao
          rotulo="Um registro, não seis tarefas"
          titulo="Você registra a sessão uma vez. O restante acompanha esse registro."
          linha="Depois de registrar o que aconteceu com a sessão, o Sessões organiza as pendências que nascem desse registro: a cobrança, o lembrete de pagamento, a linha do recibo, o número que o contador precisa e o fechamento do mês. São consequências do que você já fez, e não cinco tarefas novas que aparecem depois."
        >
          {/* O conceito da figura antiga estava certo e o desenho parecia um
              fluxograma de arquitetura — com a frase de baixo espremida dentro
              do card. Aqui a origem é visualmente dominante e os cinco viram
              **consequências**, que é o argumento inteiro da seção: não são
              cinco tarefas novas. */}
          <FiguraEditorial
            className="mb-8 max-w-[720px]"
            src="/figuras/um-registro-cinco-consequencias.webp"
            legenda="Depois que você registra o que aconteceu, cobrança, lembrete, recibo, contador e fechamento continuam ligados à mesma sessão."
          />

          {/* Ficou UM cartão, não três.

              Os outros dois — "campos pendentes aparecem antes de concluir" e
              "cinco eixos, não um estado" — repetiam, com outras palavras, o
              que a seção do CFP e a dos quatro destinos já dizem inteiras. A
              segunda auditoria mediu o efeito: 31 títulos e ~9.600px de altura,
              e a diferenciação se diluindo numa sucessão de explicações. O
              custo de repetir não é a página ficar grande; é a ideia forte
              virar mais uma. */}
          <div className="max-w-[62ch] rounded-cartao border border-linha bg-folha p-5">
            <h3 className="font-serif text-[19px] leading-snug text-tinta">
              A sessão responde por si
            </h3>
            <p className="mt-2 text-[13.5px] leading-relaxed text-tinta2">
              Registrar o que aconteceu, ver cobrança e pagamento, enviar ou
              pausar o lembrete, emitir documento, consultar reposição e ver o
              que falta para fechar — tudo no painel da própria sessão, sem
              atravessar módulo nenhum.
            </p>
          </div>
        </Secao>

        {/* ---------------- a prova de que existe software ----------------

            Condicional: nasce só com as capturas que existirem em
            `public/telas/`. Enquanto não existirem, a página segue sem ela em
            vez de mostrar moldura vazia — a auditoria encontrou uma promessa
            não cumprida no funil, e eu não vou plantar outra aqui. O LEIA-ME
            daquela pasta tem as credenciais da conta de demonstração e o
            aviso sobre nome de paciente. */}
        <Telas />

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
          {/* Cada destino ganha o glifo da própria célula da grade — o mesmo
              vocabulário que ela encontra na agenda depois de criar a conta.
              Só o terceiro é rosa, porque só o terceiro é hora vazia. */}
          <dl className="grid gap-px overflow-hidden rounded-cartao border border-linha bg-linha sm:grid-cols-2 lg:grid-cols-4">
            {(
              [
                {
                  r: "Realizada e recebida",
                  c: "text-cheia",
                  g: "recebida",
                  n: "a sessão aconteceu e o pagamento foi identificado",
                },
                {
                  r: "Realizada, a receber",
                  c: "text-aviso",
                  g: "receber",
                  n: "o atendimento aconteceu e o pagamento ainda não entrou",
                },
                {
                  r: "Horário não ocupado",
                  c: "text-vaga",
                  g: "vazio",
                  n: "o horário existia na agenda e ninguém o ocupou — pode ter razão clínica, e o registro não opina",
                },
                {
                  r: "Reposição realizada",
                  c: "text-tinta",
                  g: "reposicao",
                  n: "você deu outro horário pelo mesmo dinheiro — duas horas, uma receita",
                },
              ] as const
            ).map((i) => (
              <div key={i.r} className="bg-folha px-5 py-5">
                <GlifoDoDestino tipo={i.g} />
                <dt className={`mt-3 font-serif text-[17px] leading-snug ${i.c}`}>{i.r}</dt>
                <dd className="mt-1.5 text-[12.5px] leading-relaxed text-tinta3">
                  {i.n}
                </dd>
              </div>
            ))}
          </dl>

          {/* Cortado pela metade. As quatro células acima já ensinam a
              separação; este parágrafo repetia a lição e só então dizia a coisa
              nova. Ficou a coisa nova. */}
          <p className="mt-6 max-w-[70ch] text-[13px] leading-relaxed text-tinta2">
            Separadas, elas produzem dois números que só fazem sentido juntos:{" "}
            <b className="font-medium text-tinta">receita por hora disponível</b> e{" "}
            <b className="font-medium text-tinta">a causa de cada horário não ocupado</b>. Ocupação
            subindo com receita por hora caindo é sintoma, não sucesso.
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
          {/* A ressalva fica — é o que separa esta página das outras sete do
              mercado —, mas em duas frases em vez de quatro. O método publicado
              antes da coleta é assunto do Panorama, e é lá que ele se lê. */}
          <p className="mt-6 max-w-[70ch] text-[12.5px] leading-relaxed text-tinta3">
            <b className="font-medium text-tinta2">
              E não prometemos que isso enche a sua agenda.
            </b>{" "}
            Enquanto não houver medida de que existe gente querendo as horas que
            vagam, prometer ocupação é vender hipótese — estamos medindo, e o
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

        {/* ---------------- o CFP e as fronteiras, agora numa seção só ----------------

            Eram duas seções longas e consecutivas, e a segunda auditoria
            apontou o custo: a leitora recebia duas listas grandes seguidas
            sobre o mesmo assunto — o que o produto faz com a responsabilidade
            profissional e o que ele se recusa a fazer.

            São o mesmo argumento visto de dois lados, e agora estão juntas:
            três compromissos e três recusas à vista, o resto a um clique. O
            título anterior — "a conformidade com o CFP é sua, o sistema existe
            para você não ter que pensar nela" — já tinha sido corrigido na
            primeira auditoria, porque prometia eliminar uma decisão que não se
            terceiriza. */}
        <Secao
          id="cfp"
          rotulo="As regras da profissão"
          titulo="A responsabilidade profissional continua sendo sua. O sistema reduz o trabalho de cumpri-la."
          linha="Nenhum software assume a responsabilidade da psicóloga pelo prontuário — quem disser o contrário está vendendo o que não pode entregar. O que dá para fazer é organizar registros, prazos, acessos e correções para que o cumprimento não dependa de memória nem de uma revisão apressada no fim do mês. E, do outro lado, recusar o que não deveria existir num software que vive fora da sala."
        >
          <div className="grid items-start gap-8 lg:grid-cols-[300px_minmax(0,1fr)]">
            <figure className="order-last rounded-cartao border border-linha bg-folha p-4 lg:order-first lg:sticky lg:top-20">
              <FolhaDoProntuario className="h-auto w-full" />
              <figcaption className="mt-3 border-t border-linha pt-3 text-[11.5px] leading-relaxed text-tinta3">
                Os quatro blocos da Res. CFP 001/2009. O que falta fica marcado
                em vez de sumir da tela.
              </figcaption>
            </figure>

            <div className="grid gap-4 sm:grid-cols-2">
              <Cartao titulo="O prontuário nos blocos que o Manual pede">
                Identificação, avaliação da demanda, evolução e encerramento — a
                estrutura da Resolução 001/2009 com a linguagem do Manual
                Orientativo de novembro de 2025, não um campo de texto livre com
                outro nome.
              </Cartao>
              <Cartao titulo="Cinco anos, e do menor conta da maioridade">
                O prazo de guarda é calculado por ficha, e o sistema recusa apagar
                o que ainda está dentro dele. Quando o paciente é menor, o relógio
                começa quando ele completa dezoito.
              </Cartao>
              <Cartao titulo="Não entramos na sala">
                Nada de gravar paciente, transcrever sessão ou IA opinando sobre
                diagnóstico, conduta ou risco. E nenhuma tela sugere que alguém
                podia vir mais vezes — o Código de Ética veda induzir a pessoa a
                recorrer aos seus serviços.
              </Cartao>
              <Cartao titulo="O contador vê finanças, nunca clínica. E quem trabalha com você também">
                Acesso clínico é uma decisão separada do cargo: quem marca a
                agenda não precisa ler a sessão. Minimização de dados por
                construção, não por promessa.
              </Cartao>
            </div>
          </div>

          <Mais rotulo="Ver todos os compromissos e todas as linhas que não atravessamos">
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
              <Cartao titulo="Evolução que não se apaga — e que se corrige">
                O que foi registrado fica com a data em que foi registrado.
                Correção não é proibida: ela entra como acréscimo datado, com a
                data em que chegou, sem apagar o histórico.
              </Cartao>
              <Cartao titulo="Campos obrigatórios pendentes ficam visíveis">
                O Manual pede que não se deixe espaço em branco no prontuário.
                Aqui a seção que falta aparece antes de você concluir o registro,
                em vez de sumir da tela.
              </Cartao>
              <Cartao titulo="Trilha de quem viu o quê">
                Cada abertura de prontuário fica registrada, e a trilha é sua —
                não um log interno nosso. É o que permite responder com fato, e
                não com memória, se alguém perguntar.
              </Cartao>
              <Cartao titulo="Nosso suporte não vê prontuário">
                É limitação escrita no código, com teste automático que reprova a
                alteração se alguma função de suporte encostar em prontuário,
                evolução ou anamnese. Para recuperar acesso, agimos sobre a conta
                e o login — nunca abrindo o conteúdo clínico.
              </Cartao>
              <Cartao titulo="Não reativamos ex-paciente, e não damos desconto para vender horário parado">
                Preço não é propaganda, e vínculo clínico não é lista de
                remarketing.
              </Cartao>
              <Cartao titulo="Não vendemos pacientes, e a fila não é leilão">
                Não somos marketplace, não rankeamos profissional e não
                intermediamos demanda. A ordem da fila é sua; dinheiro não compra
                posição.
              </Cartao>
            </div>

            <p className="mt-6 max-w-[74ch] text-[12.5px] leading-relaxed text-tinta3">
              Base normativa: <b className="font-medium text-tinta2">Resolução CFP nº 001/2009</b> (prontuário
              psicológico e guarda), <b className="font-medium text-tinta2">Resolução CFP nº 06/2019</b> (documentos
              escritos), <b className="font-medium text-tinta2">Resolução CFP nº 09/2024</b> (atendimento por
              tecnologias) e o <b className="font-medium text-tinta2">Manual Orientativo de nov/2025</b>. Conferimos
              as quatro em 01/09/2026, e o que estiver desatualizado aqui é erro
              nosso — se você encontrar, escreva.
            </p>

            <p className="mt-4 max-w-[70ch] text-[12.5px] leading-relaxed text-tinta3">
              Prontuário é dado pessoal sensível. Criptografia, trilha de quem viu
              o quê, prazo de guarda declarado e portabilidade dos dois lados: você
              sai levando os seus dados, e o paciente recebe os dele — que é um
              direito.
            </p>
          </Mais>
        </Secao>

        {/* ---------------- planos ---------------- */}
        <Secao
          id="planos"
          rotulo="Planos"
          // **A unidade mudou na OP8, e a frase mudou junto.** Até 02/09 o
          // Grátis vinha com "60 mensagens de fila e cobrança por mês", e a
          // régua era o limite de disparo. Duas coisas estavam erradas nisso:
          // mensagem é a nossa língua e sessão é a dela — ninguém sabe quantas
          // mensagens um mês gasta antes de o mês acabar —, e quando o limite
          // estourava quem ficava sem aviso era a paciente, que não escolheu
          // plano nenhum.
          //
          // Agora a régua é a **faixa de sessões**, e ela não é uma cerca:
          // passar dela não trava nada e não gera cobrança extra. Por isso a
          // frase abaixo diz "prevê" e não "permite".
          titulo="O registro é de graça. O que se cobra é o tamanho do mês e o que fecha ele."
          linha="O Grátis dá o registro inteiro — agenda, prontuário, o que aconteceu com cada horário, pacientes sem limite — e traz a fila e a cobrança funcionando, com o seu dedo: a mensagem nasce pronta e você toca para mandar, do seu próprio WhatsApp. Nos planos pagos ela sai sozinha, na hora. O que cada plano prevê é uma faixa de sessões por mês, e atender acima dela não bloqueia nada e não gera cobrança extra. E não existe limite de mensagem em plano nenhum — quem ficaria sem receber é o seu paciente, que não escolheu plano."
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
                {p.selo && (
                  <span className="mt-1 text-[11px] font-medium uppercase tracking-wider text-vaga">
                    {p.selo}
                  </span>
                )}
                <span className="tabular mt-3 font-mono text-[26px] font-medium leading-none text-tinta">
                  {p.preco}
                </span>
                <span className="mt-1 text-[12px] text-tinta3">{p.detalhe}</span>

                <ul className="mt-4 flex flex-1 flex-col gap-2 border-t border-linha pt-4">
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

                {/* **Cada plano tem uma porta.** Sem isto, a pessoa comparava os
                    quatro preços, decidia, e não achava onde clicar — o
                    cabeçalho oferecia só "Entrar", que parece ser para quem já
                    é cliente. Ela tinha de descobrir sozinha que precisava
                    voltar ao topo. */}
                <Link
                  href={p.href}
                  className={`mt-5 rounded-full px-4 py-2.5 text-center text-[12.5px] font-semibold transition-opacity hover:opacity-90 ${
                    p.destaque
                      ? "bg-vaga text-white"
                      : "border border-linha2 text-tinta2 hover:bg-folha2"
                  }`}
                >
                  {p.cta}
                </Link>
              </div>
            ))}
          </div>

          {/* O exemplo que faltava. "R$ 249 + R$ 39 por profissional" não
              respondia o que uma clínica de cinco pessoas paga, nem se a
              secretária conta — e quem não consegue calcular o próprio caso não
              escolhe o plano, adia. */}
          <div className="mt-5 rounded-cartao border border-linha bg-folha px-5 py-4">
            <p className="text-[13px] leading-relaxed text-tinta2">
              <b className="font-medium text-tinta">Clínica, na prática:</b> a
              base de R$ 249 já inclui uma profissional que atende. Cinco
              profissionais custam R$ 249 + 4 × R$ 39 ={" "}
              <b className="font-medium text-tinta">R$ 405 por mês</b>. Secretaria
              e administração <b className="font-medium text-tinta">não contam</b>{" "}
              como profissional e não são cobradas.
            </p>
          </div>

          {/* **De qual número sai a mensagem** — e isto está aqui porque quase
              ninguém neste mercado responde. Dos treze produtos que a pesquisa
              de 02/09 leu, só quatro declaram o número e só dois declaram usar a
              API oficial da Meta; três vendem "WhatsApp automático" sem uma
              linha sobre provedor, template ou Meta, inclusive nas políticas de
              privacidade onde listam todos os outros subprocessadores.

              Declarar isso é barato e é verdadeiro. Não afirmamos ter o degrau
              que não temos — automático E do seu número, que depende de uma
              conexão que ainda não existe aqui. */}
          <div className="mt-5 rounded-cartao border border-linha bg-folha px-5 py-4">
            <p className="text-[13px] leading-relaxed text-tinta2">
              <b className="font-medium text-tinta">De qual número sai:</b> no
              Grátis, do seu — a mensagem nasce escrita e você toca para enviar
              pelo seu WhatsApp, como já faz hoje, só que sem digitar. Nos planos
              pagos ela sai sozinha, pelo número do Sessões, pela API oficial da
              Meta. Enviar do <i>seu</i> número automaticamente ainda não
              existe aqui, e não prometemos que exista.
            </p>
          </div>

          <p className="mt-6 max-w-[70ch] text-[12.5px] leading-relaxed text-tinta3">
            Sem contrato de fidelidade e sem cobrança de saída. Você exporta
            tudo — pacientes, sessões, prontuários, documentos e registros
            financeiros — em formato aberto, a qualquer momento, sem pedir para
            ninguém.
          </p>
        </Secao>

        {/* ---------------- os textos ----------------

            Condicional: sem texto publicado, a seção não existe. Uma faixa
            "em breve, nossos artigos" é a promessa não cumprida que a segunda
            auditoria achou no funil, com outra roupa.

            E ela vem DEPOIS do preço de propósito. Três links de leitura no
            meio da decisão de assinar são três saídas da página; depois do
            preço, viram a outra coisa que a pessoa pode fazer se ainda não
            estiver pronta. */}
        <UltimosTextos />

        {/* ---------------- o fechamento ----------------

            A hierarquia estava invertida: o maior botão da página, depois de
            toda a argumentação, era "Quero conversar" — e "criar sua conta"
            aparecia como link de texto embaixo. A landing começava como produto
            aberto e terminava como pesquisa de descoberta.

            Agora a ação principal do fim repete a do início, e a conversa fica
            onde ela é útil: como saída para quem não está pronta.

            **A frase do título mudou, e agora por decisão dele.** A primeira
            auditoria sugeriu tirar "psicólogas de verdade" e eu mantive, com a
            divergência registrada aqui, porque o pedido do Leandro tinha sido
            explícito. A terceira leitura trouxe o argumento que faltava: a
            expressão implica que existem psicólogas não-verdadeiras, e o que se
            queria dizer era outra coisa — o contraste é com software feito sobre
            suposição. A frase nova diz o contraste sem a implicação. */}
        <section id="conversa" className="scroll-mt-16 border-t border-linha bg-folha2">
          <div className="mx-auto max-w-3xl px-5 py-14 sm:px-8 sm:py-20">
            <span className="flex items-center gap-2.5">
              <Fio className="shrink-0" />
              <span className="rotulo">Começar</span>
            </span>

            <h2 className="mt-2 max-w-[22ch] font-serif text-[29px] leading-[1.15] tracking-[-0.015em] text-balance sm:text-[38px]">
              Comece pelo próximo atendimento.
            </h2>

            {/* A tabela de planos, três seções acima, já diz que o Grátis não
                expira e o que ele traz. Repetir a lista aqui era a terceira vez
                na mesma página — e o fechamento não é lugar de reapresentar o
                cardápio, é lugar de dizer o próximo passo. */}
            <p className="mt-3 max-w-[58ch] text-[14.5px] leading-relaxed text-tinta2">
              A conta se cria em um minuto, sem cartão. Comece pelo horário que
              você tem marcado para amanhã.
            </p>

            <div className="mt-7 flex flex-wrap items-center gap-4">
              <Link
                href="/entrar?criar"
                className="rounded-full bg-vaga px-7 py-3.5 text-[14px] font-semibold text-white transition-opacity hover:opacity-90"
              >
                Criar minha conta grátis
              </Link>
              <Link
                href="/entrar"
                className="text-[13.5px] font-medium text-tinta2 underline decoration-linha2 underline-offset-4 transition-colors hover:text-vaga"
              >
                Já tenho conta
              </Link>
            </div>

            <div className="mt-10 border-t border-linha pt-8">
              <h3 className="max-w-[30ch] font-serif text-[22px] leading-snug text-tinta">
                Estamos construindo o Sessões com quem fecha o mês de um
                consultório real.
              </h3>
              <p className="mt-2.5 max-w-[58ch] text-[13.5px] leading-relaxed text-tinta2">
                Cada tela daqui saiu de uma conversa com quem fecha o mês. Ainda
                tem dúvida, ou quer conversar vinte minutos sobre como é o seu
                mês de verdade — onde a conta trava, e o que você já resolve numa
                planilha? Deixe seu e-mail.
              </p>
              <div className="mt-6">
                <Espera />
              </div>
            </div>
          </div>
        </section>
      </main>

      {/* ---------------- rodapé ----------------

          O rodapé virou componente compartilhado com as páginas de documento.
          O motivo é o item que ele passou a carregar: termos, privacidade e
          segurança **precisam estar a um clique de qualquer página**, e não só
          da inicial. O Manual do CFP de nov/2025 manda a psicóloga conferir as
          cláusulas de eliminação do software que ela usa — um link difícil de
          achar é uma cláusula difícil de conferir. Duas cópias do mesmo rodapé
          seriam duas listas para esquecer de atualizar. */}
      <RodapeDoSite />
    </>
  );
}
