import { Marca } from "@/components/site/Marca";
import { Cascata } from "@/components/site/Cascata";
import { Discricao } from "@/components/site/Discricao";
import { Espera } from "@/components/site/Espera";

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
        <h2 className="mt-2 max-w-[22ch] font-serif text-[27px] leading-[1.18] tracking-[-0.015em] text-balance sm:text-[34px]">
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

const PLANOS = [
  {
    nome: "Grátis",
    preco: "R$ 0",
    detalhe: "para começar",
    linhas: [
      "Agenda, pacientes e o livro-razão da sessão",
      "Lembrete de véspera sem limite",
      "60 mensagens de fila e cobrança por mês",
    ],
  },
  {
    nome: "Solo",
    preco: "R$ 69",
    detalhe: "por mês",
    destaque: true,
    linhas: [
      "Mensagens sem teto",
      "Conciliação do Pix com a sessão",
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
      "Página do paciente: confirmar, pagar, receber documento",
      "Receita por hora disponível e perda por causa",
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
    "O contador vê finanças, nunca clínica.",
    "Minimização de dados por construção, não por promessa.",
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
            para psicólogas e clínicas de psicologia
          </span>
          <a
            href="#lista"
            className="ml-auto rounded-full border border-linha2 px-4 py-1.5 text-[12.5px] font-medium text-tinta2 transition-colors hover:border-vaga hover:text-vaga"
          >
            Entrar na lista
          </a>
        </div>
      </header>

      <main>
        {/* ---------------- hero ---------------- */}
        <section className="mx-auto max-w-5xl px-5 pb-14 pt-14 sm:px-8 sm:pb-20 sm:pt-24">
          <h1 className="max-w-[18ch] font-serif text-[38px] leading-[1.08] tracking-[-0.022em] text-balance sm:text-[62px]">
            Sua semana tem 25 horas de atendimento. Quantas viraram receita?
          </h1>

          <p className="mt-6 max-w-[58ch] text-[16px] leading-relaxed text-tinta2 sm:text-[17px]">
            O <Marca /> é a operação financeira do consultório, com a agenda
            dentro. Ele mostra quanto da capacidade disponível virou receita —
            e por onde o resto foi.
          </p>

          <div className="mt-8 flex flex-wrap items-center gap-4">
            <a
              href="#lista"
              className="rounded-full bg-vaga px-6 py-3 text-[13.5px] font-semibold text-white transition-opacity hover:opacity-90"
            >
              Entrar na lista de espera
            </a>
            <a
              href="#destino"
              className="text-[13.5px] font-medium text-tinta2 underline decoration-linha2 underline-offset-4 transition-colors hover:text-vaga"
            >
              Ver os quatro destinos de uma hora
            </a>
          </div>

          {/* Os quatro destinos. Substituiu os três números da versão
              anterior — "1 hora / R$ 800 / 0 conversas" —, que projetavam
              receita recuperada em cima de uma hipótese que ainda não foi
              medida: a de que existe alguém querendo aquele horário. */}
          <dl className="mt-14 grid gap-px overflow-hidden rounded-cartao border border-linha bg-linha sm:grid-cols-2 lg:grid-cols-4">
            {[
              {
                r: "atendida e paga",
                c: "text-cheia",
                n: "a hora virou receita, e a receita ficou",
              },
              {
                r: "atendida e em aberto",
                c: "text-aviso",
                n: "o atendimento aconteceu e o dinheiro ainda não entrou",
              },
              {
                r: "perdida",
                c: "text-vaga",
                n: "não produziu nada, e ninguém ocupou o lugar",
              },
              {
                r: "reposta",
                c: "text-vaga",
                n: "você deu outro horário pelo mesmo dinheiro — duas horas, uma receita",
              },
            ].map((i) => (
              <div key={i.r} className="bg-folha px-5 py-5">
                <dt className={`font-serif text-[17px] leading-snug ${i.c}`}>
                  {i.r}
                </dt>
                <dd className="mt-1.5 text-[12.5px] leading-relaxed text-tinta3">
                  {i.n}
                </dd>
              </div>
            ))}
          </dl>
        </section>

        {/* ---------------- o destino da hora ---------------- */}
        <Secao
          id="destino"
          rotulo="O livro-razão"
          titulo="Cada hora tem um destino, e ele fica registrado."
          linha="Atendida e paga, atendida e em aberto, perdida, ou reposta — quando você dá outro horário pelo mesmo dinheiro. A última é a conta que ninguém faz, e é onde a receita some: duas horas de capacidade, uma receita só. Nenhum sistema deste mercado separa essas quatro."
          fundo="folha"
        >
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <Cartao titulo="Cinco eixos, não um estado">
              Hoje, num sistema comum, &ldquo;paga&rdquo; não diz se foi
              realizada, &ldquo;cancelada&rdquo; não diz se houve receita e
              &ldquo;remarcada&rdquo; não diz se consumiu outra hora. Aqui a
              sessão carrega os cinco separados: agenda, confirmação,
              financeiro, fiscal e o que aconteceu com a hora.
            </Cartao>
            <Cartao titulo="Antecipado não é atendido">
              Receber por uma sessão que ainda não aconteceu entra como pago, e
              não como receita reconhecida. Sem essa separação, o número mais
              importante do mês sobe recebendo por hora que ainda não existiu.
            </Cartao>
            <Cartao titulo="Quatro números, sempre juntos">
              Ocupação realizada, ocupação paga, receita por hora disponível e a
              perda por causa. Ocupação subindo com receita por hora caindo é
              sintoma, não sucesso — e só se enxerga com os dois lado a lado.
            </Cartao>
          </div>
        </Secao>

        {/* ---------------- os cinco lugares ---------------- */}
        <Secao
          rotulo="O mês"
          titulo="O mês não fecha porque a conta está em cinco lugares."
          linha="Agenda num app, pagamento no extrato, recibo no site da Receita, controle numa planilha e o resto no WhatsApp. Aqui a sessão carrega tudo — quem confirmou, quem pagou, quem tem recibo, o que ficou em aberto."
        >
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <Cartao titulo="O Pix encontra a sessão sozinho">
              Pagamento sem sessão, sessão sem pagamento, valor divergente — os
              três viram uma fila de divergências em vez de uma conferência de
              extrato no fim do dia.
            </Cartao>
            <Cartao titulo="A política vem congelada na sessão">
              Vinte e quatro horas, cinquenta por cento — o que você combinou, na
              versão que valia <em>naquele dia</em>. O sistema propõe a cobrança
              com essa política e o histórico; quem confirma, perdoa ou ajusta é
              você. Exceção clínica não é decidível por regra.
            </Cartao>
            <Cartao titulo="A régua é impessoal">
              O lembrete de pagamento em atraso não vem de você. Vem da agenda —
              e o alívio de não precisar mandar aquela mensagem é o que faz
              trocar de sistema.
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

        {/* ---------------- a fila ---------------- */}
        <Secao
          id="fila"
          rotulo="Quando um horário abre"
          titulo="O horário é oferecido a quem pediu para ser avisado, no valor combinado."
          linha="Uma pessoa por vez, na ordem que você definiu, e a primeira que responder fica com o horário. Não é leilão e não tem desconto: quem entra paga o mesmo que já estava combinado. Se ninguém quiser, a hora fica registrada como perdida — e aparece na conta do mês pelo nome."
          fundo="folha"
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
        >
          <Discricao />
        </Secao>

        {/* ---------------- planos ---------------- */}
        <Secao
          id="planos"
          rotulo="Planos"
          titulo="Preço em estudo, com quem vai usar."
          linha="Estes números são hipótese, e estão sendo testados com as primeiras psicólogas que conversam com a gente. Quem entrar na lista participa dessa conversa — e do piloto. O plano Grátis tem teto de mensagens, não de sessões: lembrete de véspera e aviso de desmarque saem sempre, em qualquer plano, porque quem ficaria sem eles é o paciente."
          fundo="folha"
        >
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {PLANOS.map((p) => (
              <div
                key={p.nome}
                className={`flex flex-col rounded-cartao border bg-folha p-5 ${
                  p.destaque ? "border-vaga-linha ring-1 ring-vaga-linha" : "border-linha"
                }`}
              >
                <div className="flex items-baseline justify-between gap-2">
                  <span className="font-serif text-[20px] text-tinta">{p.nome}</span>
                  {p.destaque && (
                    <span className="rounded-full bg-vaga-bg px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider text-vaga">
                      a maioria
                    </span>
                  )}
                </div>
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
        </Secao>

        {/* ---------------- fronteiras ---------------- */}
        <Secao
          rotulo="As linhas que não atravessamos"
          titulo="O Sessões vive fora da sala, e não opina sobre a clínica."
          linha="Um software que administra a agenda, o dinheiro e a papelada — e que nunca entra na sessão nem sugere o que fazer com um paciente. Isto não é promessa de marketing: são decisões de arquitetura, escritas antes da primeira linha de código, e algumas delas vêm direto do Código de Ética."
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

        {/* ---------------- lista ---------------- */}
        <section id="lista" className="scroll-mt-16 border-t border-linha bg-folha2">
          <div className="mx-auto max-w-3xl px-5 py-16 sm:px-8 sm:py-24">
            <span className="rotulo">Lista de espera</span>
            <h2 className="mt-2 max-w-[20ch] font-serif text-[29px] leading-[1.15] tracking-[-0.015em] text-balance sm:text-[38px]">
              Estamos construindo isto com psicólogas de verdade.
            </h2>
            <p className="mt-3 max-w-[58ch] text-[14.5px] leading-relaxed text-tinta2">
              Antes de escrever o produto inteiro, estamos ouvindo quem fecha o
              mês. Deixe seu e-mail para acompanhar — e, se quiser, para
              conversar vinte minutos com a gente sobre como é o seu mês de
              verdade: onde a conta trava, e o que você já resolve numa planilha.
            </p>
            <div className="mt-8">
              <Espera />
            </div>
          </div>
        </section>
      </main>

      {/* ---------------- rodapé ---------------- */}
      <footer className="border-t border-linha bg-folha">
        <div className="mx-auto flex max-w-5xl flex-col gap-3 px-5 py-8 text-[12px] text-tinta3 sm:flex-row sm:items-center sm:px-8">
          <Marca className="text-[16px]" />
          <span className="max-w-[46ch] text-tinta2">
            Feito por um contador que resolveu olhar a conta do consultório.
          </span>
          <span className="sm:ml-auto">
            Em construção · São Paulo ·{" "}
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
