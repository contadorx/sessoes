import { Marca } from "@/components/site/Marca";
import { Cascata } from "@/components/site/Cascata";
import { Simulador } from "@/components/site/Simulador";
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
    detalhe: "até 20 sessões por mês",
    linhas: ["Agenda e lembretes", "Fila com um preenchimento por mês", "Cadastro de pacientes"],
  },
  {
    nome: "Solo",
    preco: "R$ 69",
    detalhe: "por mês",
    destaque: true,
    linhas: [
      "Fila de espera completa",
      "Política de falta que se aplica sozinha",
      "Cobrança, recibo e régua impessoal",
      "Modo Receita Saúde e pasta do contador",
    ],
  },
  {
    nome: "Pro",
    preco: "R$ 129",
    detalhe: "por mês",
    linhas: [
      "Tudo do Solo",
      "NFS-e para quem tem CNPJ",
      "Briefing antes da sessão e radar de furo",
      "Portal do paciente e evolução por ditado",
    ],
  },
  {
    nome: "Clínica",
    preco: "R$ 249",
    detalhe: "+ R$ 39 por profissional",
    linhas: [
      "Repasse automático e demonstrativo",
      "Fila cruzada entre profissionais",
      "Agenda de salas",
      "Sigilo entre profissionais por construção",
    ],
  },
];

const FRONTEIRAS = [
  ["Não entramos na sala.", "Nada de gravar paciente, transcrever sessão ou IA opinando sobre diagnóstico, conduta ou risco."],
  ["Não vendemos pacientes.", "Não somos marketplace, não rankeamos profissional e não intermediamos demanda."],
  ["A fila não é leilão.", "A regra de prioridade é clínica e é sua. Dinheiro não compra posição."],
  ["O contador vê finanças, nunca clínica.", "Minimização de dados por construção, não por promessa."],
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
          <h1 className="max-w-[17ch] font-serif text-[38px] leading-[1.08] tracking-[-0.022em] text-balance sm:text-[62px]">
            Sua agenda não fura mais de graça, e você nunca mais precisa cobrar
            ninguém.
          </h1>

          <p className="mt-6 max-w-[58ch] text-[16px] leading-relaxed text-tinta2 sm:text-[17px]">
            O <Marca /> é o sistema que preenche a hora que abriu e cobra por
            você. O prontuário está lá, bem-feito — mas ele nunca foi a sua
            maior dor.
          </p>

          <div className="mt-8 flex flex-wrap items-center gap-4">
            <a
              href="#lista"
              className="rounded-full bg-vaga px-6 py-3 text-[13.5px] font-semibold text-white transition-opacity hover:opacity-90"
            >
              Entrar na lista de espera
            </a>
            <a
              href="#conta"
              className="text-[13.5px] font-medium text-tinta2 underline decoration-linha2 underline-offset-4 transition-colors hover:text-vaga"
            >
              Ver quanto a hora vazia te custa
            </a>
          </div>

          {/* a aritmética, em três números */}
          <dl className="mt-14 grid gap-px overflow-hidden rounded-cartao border border-linha bg-linha sm:grid-cols-3">
            {[
              {
                v: "1 hora",
                c: "text-vaga",
                r: "o que fura",
                n: "não é revendável nem recuperável — você já estava lá",
              },
              {
                v: "R$ 800",
                c: "text-cheia",
                r: "por mês",
                n: "o que volta se a fila recuperar um horário por semana",
              },
              {
                v: "0",
                c: "text-tinta",
                r: "conversas de cobrança",
                n: "quem fala de dinheiro passa a ser o sistema",
              },
            ].map((i) => (
              <div key={i.r} className="bg-folha px-5 py-5">
                <dt className="rotulo">{i.r}</dt>
                <dd>
                  <span
                    className={`tabular mt-1 block font-mono text-[30px] font-medium leading-none tracking-[-0.02em] ${i.c}`}
                  >
                    {i.v}
                  </span>
                  <span className="mt-2 block text-[12.5px] leading-relaxed text-tinta3">
                    {i.n}
                  </span>
                </dd>
              </div>
            ))}
          </dl>
        </section>

        {/* ---------------- a fila ---------------- */}
        <Secao
          id="fila"
          rotulo="A hora vazia"
          titulo="A fila que preenche o buraco antes de você perceber."
          linha="Sete sistemas de prontuário resolveram a mesma dor — escrever a evolução — e nenhum deles tem lista de espera. Aqui, o cancelamento vira uma cascata de ofertas: uma pessoa por vez, na ordem que você definiu, e a primeira que responder fica com o horário."
          fundo="folha"
        >
          <Cascata />
        </Secao>

        {/* ---------------- o simulador ---------------- */}
        <Secao
          id="conta"
          rotulo="A conta"
          titulo="Quanto a hora vazia já te custou este ano."
          linha="Mexa nos dois números e veja a sua própria conta. É a única promessa deste mercado que fecha em aritmética de padaria — e dá para conferir na primeira semana de uso."
        >
          <Simulador />
        </Secao>

        {/* ---------------- o dinheiro ---------------- */}
        <Secao
          rotulo="O dinheiro"
          titulo="Falar de dinheiro com quem chorou na sua frente é o trabalho mais pesado da profissão."
          linha="Por isso tanta gente simplesmente não cobra a falta — e some com a própria receita para não constranger ninguém. O acordo você escreve uma vez; quem executa é o sistema."
          fundo="folha"
        >
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <Cartao titulo="A política se aplica sozinha">
              Vinte e quatro horas, cinquenta por cento — o que você combinou. O
              cancelamento tardio já sai cobrado, com o texto que você escreveu
              uma vez, sem você dizer nada.
            </Cartao>
            <Cartao titulo="A régua é impessoal">
              O lembrete de pagamento em atraso não vem de você. Vem da agenda —
              e o alívio de não precisar mandar aquela mensagem é o que faz
              trocar de sistema.
            </Cartao>
            <Cartao titulo="Recibo, reembolso e o contador">
              Recibo emitido sozinho, PDF do mês para o convênio, informe anual
              em janeiro e o pacote mensal que vai direto para o seu contador —
              com finanças, nunca com prontuário.
            </Cartao>
            <Cartao titulo="Receita Saúde sem multa">
              Desde 2025 cada atendimento precisa de recibo emitido, sob multa
              por omissão. O sistema sabe quais sessões pagas ainda estão sem
              recibo e avisa antes do prazo virar.
            </Cartao>
            <Cartao titulo="Reajuste sem saia justa">
              A segunda conversa mais adiada da profissão. O sistema marca o
              aniversário do enquadre, sugere o valor, comunica com
              antecedência e aplica na data.
            </Cartao>
            <Cartao titulo="Do jeito que você cobra">
              Por sessão, mensalidade fixa ou pacote fechado — com regra clara
              para o mês de cinco semanas e para a falta dentro da mensalidade.
              Você decide, o sistema aplica.
            </Cartao>
          </div>
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
          titulo="Um horário recuperado paga o plano quase três vezes."
          linha="Preços em estudo, junto com as primeiras psicólogas que estão conversando com a gente. Quem entrar na lista de espera participa dessa conversa — e do piloto."
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
          titulo="O Sessões vive fora da sala."
          linha="Um software que administra a agenda, o dinheiro e a papelada — e que nunca entra na sessão. Isto não é uma promessa de marketing: é decisão de arquitetura, escrita antes da primeira linha de código."
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
              Antes de escrever o produto inteiro, estamos ouvindo quem vive a
              agenda que fura. Deixe seu e-mail para acompanhar — e, se quiser,
              para conversar vinte minutos com a gente sobre como é o seu mês.
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
