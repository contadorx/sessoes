/**
 * As figuras da landing.
 *
 * A PREMISSA, E ELA É UMA ORDEM
 *
 * *"Gosto do ícone que está no app, pois ele remete a mais coisas de
 * psicologia. Os demais são gráficos e parecidos com financeiros, e o que
 * queremos é um aplicativo com a linguagem e a ajuda a profissionais de
 * psicologia — adote essa premissa sempre."*
 *
 * Então **nenhuma figura aqui é gráfico**. Sem barra, sem pizza, sem linha de
 * série temporal, sem medidor, sem cartão de indicador. Tudo é a mesma coisa
 * desenhada de ângulos diferentes: **a grade de horários em papel** — que é o
 * ícone, que é o produto, e que é o objeto que a psicóloga já tem em cima da
 * mesa.
 *
 * A tentação era desenhar dashboard. Um dashboard na landing responde à
 * pergunta errada ("quanto eu faturei?") para uma leitora que a auditoria
 * mostrou fugindo exatamente dessa pergunta. A grade responde à pergunta
 * certa: *o que aconteceu com este horário?*
 *
 * AS REGRAS DE COR, QUE VÊM DO DOC 09 E NÃO SE NEGOCIAM
 *
 *   - **Rosa (`vaga`) é exclusivo da hora vazia. Nunca decorativo.** Se
 *     aparecer rosa numa figura, é porque ali há um horário que não foi
 *     ocupado — em nenhuma outra hipótese. Foi por isso que os separadores e
 *     as marcas d'água daqui são cinza, e não rosa: seria bonito e seria
 *     mentira.
 *   - Verde (`cheia`) é horário preenchido e dinheiro que voltou.
 *   - Âmbar (`aviso`) é o que está pendente e tem prazo.
 *   - O resto é papel e tinta.
 *
 * ACESSIBILIDADE
 *
 * Figura que só ilustra o texto ao lado leva `aria-hidden` — ler duas vezes a
 * mesma coisa é pior que não ler. Figura que **carrega informação que o texto
 * não dá** leva `role="img"` e `<title>`, e o título diz o que a figura mostra,
 * não como ela é desenhada.
 *
 * Tudo é SVG inline, sem dependência e sem imagem externa: a página inteira
 * continua sendo um documento que carrega de uma vez.
 */

// ============================================================ a marca d'água

/**
 * A grade 3×3 do ícone, muito clara, atrás de um bloco.
 *
 * É ornamento — e por ser ornamento é **cinza**, nunca rosa. A célula marcada
 * do ícone real significa hora vazia; repetida como enfeite pelo fundo da
 * página, ela deixaria de significar isso.
 */
export function Marcadagua({ className = "" }: { className?: string }) {
  return (
    <svg
      aria-hidden
      viewBox="0 0 120 120"
      className={`pointer-events-none select-none ${className}`}
      fill="none"
    >
      {[0, 1, 2].map((l) =>
        [0, 1, 2].map((c) => (
          <rect
            key={`${l}-${c}`}
            x={4 + c * 38}
            y={4 + l * 38}
            width={34}
            height={34}
            stroke="var(--color-linha)"
            strokeWidth={1}
          />
        )),
      )}
    </svg>
  );
}

// ============================================================ hero

/**
 * A hero em desenho: a agenda de um lado, o extrato do outro.
 *
 * É a frase da hero virada figura — *"sua agenda diz uma coisa, o Pix outra,
 * no fim do mês o Sessões junta tudo"* —, e ela mostra o mecanismo inteiro,
 * inclusive a parte que não é bonita:
 *
 *   - três linhas casam (verde);
 *   - uma sessão ficou sem pagamento (âmbar, a receber);
 *   - um Pix chegou sem sessão correspondente (âmbar, divergência);
 *   - um horário não foi ocupado (rosa — e é o único rosa da figura).
 *
 * Desenhar só os casamentos que dão certo seria a versão publicitária, e seria
 * a mesma promessa absoluta que a auditoria mandou tirar da copy. A figura
 * conta a mesma verdade que o texto: o Pix **é comparado**, e o que não bate
 * vira uma linha para ela resolver.
 */
export function AgendaEExtrato({ className = "" }: { className?: string }) {
  /**
   * Cada linha é um dos quatro casos reais, e o `caso` decide tudo — cor,
   * traço e o que existe de cada lado. A primeira versão desta figura derivava
   * o desenho de `nome` e `pix` serem nulos ou não, e errou duas vezes pelo
   * mesmo motivo: `nome: "—"` é string cheia, então a linha vazia ganhou o
   * tracejado de "atendida e não paga"; e a linha do Pix sem sessão ganhou
   * contorno rosa, que significa hora vazia e ali não havia hora nenhuma.
   *
   * Estado derivado de ausência é assim: parece econômico e mente em silêncio.
   */
  const linhas = [
    { hora: "09:00", nome: "A. M.", pix: "R$ 200", caso: "casa" },
    { hora: "10:00", nome: "R. S.", pix: "R$ 200", caso: "casa" },
    { hora: "11:00", nome: null, pix: null, caso: "vazia" },
    { hora: "14:00", nome: "P. L.", pix: null, caso: "receber" },
    { hora: "15:00", nome: "C. D.", pix: "R$ 180", caso: "casa" },
    { hora: null, nome: null, pix: "R$ 200", caso: "sobra" },
  ] as const;

  const COR = {
    casa: "var(--color-cheia)",
    receber: "var(--color-aviso)",
    vazia: "var(--color-vaga)",
    sobra: "var(--color-aviso)",
  } as const;

  return (
    <svg
      role="img"
      aria-label="De um lado a agenda da terça-feira, do outro os Pix do dia. Três sessões casam com o pagamento; a das quatorze foi atendida e ainda não foi paga; o horário das onze não foi ocupado; e um Pix de duzentos reais chegou sem sessão correspondente."
      viewBox="0 0 420 268"
      className={className}
      fill="none"
    >
      <title>A agenda e o extrato, lado a lado</title>

      <text x="8" y="14" fontSize="9.5" letterSpacing="1.2" fill="var(--color-tinta3)">
        AGENDA · TERÇA
      </text>
      <text x="286" y="14" fontSize="9.5" letterSpacing="1.2" fill="var(--color-tinta3)">
        PIX DO DIA
      </text>

      {linhas.map((l, i) => {
        const y = 30 + i * 38;
        const cor = COR[l.caso];
        const temAgenda = l.caso !== "sobra";
        const vazia = l.caso === "vazia";

        return (
          <g key={l.caso + i}>
            {/* --- o lado da agenda --- */}
            {temAgenda && (
              <>
                <rect
                  x="8"
                  y={y}
                  width="150"
                  height="30"
                  rx="3"
                  fill={vazia ? "var(--color-vaga-bg)" : "var(--color-folha)"}
                  stroke={vazia ? "var(--color-vaga-linha)" : "var(--color-linha)"}
                />
                {/* a barrinha de estado só existe onde houve atendimento */}
                {!vazia && <rect x="8" y={y} width="3" height="30" rx="1.5" fill={cor} />}
                <text
                  x="20"
                  y={y + 19}
                  fontSize="11"
                  fontFamily="var(--font-mono)"
                  fill={vazia ? "var(--color-vaga)" : "var(--color-tinta2)"}
                >
                  {l.hora}
                </text>
                <text
                  x="66"
                  y={y + 19}
                  fontSize="11"
                  fill={vazia ? "var(--color-vaga)" : "var(--color-tinta)"}
                >
                  {vazia ? "não ocupado" : l.nome}
                </text>
              </>
            )}

            {/* --- o traço do meio --- */}
            {l.caso === "casa" && (
              <path
                d={`M 160 ${y + 15} C 200 ${y + 15}, 240 ${y + 15}, 280 ${y + 15}`}
                stroke="var(--color-cheia-linha)"
                strokeWidth="1.5"
              />
            )}
            {l.caso === "receber" && (
              <>
                <path
                  d={`M 160 ${y + 15} h 44`}
                  stroke="var(--color-aviso-linha)"
                  strokeWidth="1.5"
                  strokeDasharray="3 3"
                />
                <text x="210" y={y + 19} fontSize="9.5" fill="var(--color-aviso)">
                  a receber
                </text>
              </>
            )}
            {l.caso === "sobra" && (
              <>
                <path
                  d={`M 280 ${y + 15} h -44`}
                  stroke="var(--color-aviso-linha)"
                  strokeWidth="1.5"
                  strokeDasharray="3 3"
                />
                <text x="150" y={y + 19} fontSize="9.5" fill="var(--color-aviso)">
                  qual sessão?
                </text>
              </>
            )}

            {/* --- o lado do extrato --- */}
            {l.pix && (
              <>
                <rect
                  x="280"
                  y={y}
                  width="132"
                  height="30"
                  rx="3"
                  fill="var(--color-folha)"
                  stroke="var(--color-linha)"
                />
                <rect x="280" y={y} width="3" height="30" rx="1.5" fill={cor} />
                <text
                  x="292"
                  y={y + 19}
                  fontSize="11"
                  fontFamily="var(--font-mono)"
                  fill="var(--color-tinta2)"
                >
                  {l.pix}
                </text>
                <text x="348" y={y + 19} fontSize="9.5" fill="var(--color-tinta3)">
                  {l.caso === "sobra" ? "sem sessão" : "identificado"}
                </text>
              </>
            )}
          </g>
        );
      })}
    </svg>
  );
}

// ============================================================ os cinco lugares

/**
 * O mês espalhado — e o mesmo mês junto.
 *
 * O desenho da esquerda é deliberadamente torto: os cinco cartões desalinhados,
 * com linhas cruzando entre eles. É a única figura da página que **não** está
 * em grade, e a desordem é o argumento: a leitora reconhece o próprio mês antes
 * de ler a legenda.
 */
export function CincoLugares({ className = "" }: { className?: string }) {
  /**
   * Os cinco tortos, e **sem se cobrir**.
   *
   * A primeira versão sobrepunha os cartões de propósito, para o desenho
   * parecer bagunçado. Ficou bagunçado do jeito errado: um cartão tapava o
   * texto do outro, e a figura passava a parecer defeito de renderização em
   * vez de retrato do mês dela. Desordem que se lê é argumento; desordem que
   * esconde informação é só desordem.
   */
  const espalhados = [
    { x: 4, y: 10, r: -3.5, t: "agenda no app" },
    { x: 122, y: 44, r: 3, t: "extrato do banco" },
    { x: 2, y: 82, r: 2.5, t: "site da Receita" },
    { x: 124, y: 116, r: -2.5, t: "planilha" },
    { x: 8, y: 154, r: 1.5, t: "WhatsApp" },
  ];

  return (
    <svg
      role="img"
      aria-label="À esquerda, cinco lugares desalinhados e ligados por linhas tortas: agenda no app, extrato do banco, site da Receita, planilha e WhatsApp. À direita, uma folha só com tudo dentro."
      viewBox="0 0 470 200"
      className={className}
      fill="none"
    >
      <title>Cinco lugares, e depois um só</title>

      {/* --- o emaranhado --- */}
      <g>
        {[
          "M 112 26 C 128 26, 132 40, 128 56",
          "M 56 40 C 44 56, 48 74, 54 92",
          "M 176 74 C 186 92, 176 108, 160 124",
          "M 108 100 C 128 106, 130 116, 132 128",
          "M 52 112 C 44 132, 50 150, 58 166",
          "M 118 132 C 100 148, 86 156, 76 168",
        ].map((d) => (
          <path key={d} d={d} stroke="var(--color-linha2)" strokeWidth="1.1" strokeDasharray="2.5 3" />
        ))}

        {espalhados.map((c) => (
          <g key={c.t} transform={`rotate(${c.r} ${c.x + 55} ${c.y + 14})`}>
            <rect
              x={c.x}
              y={c.y}
              width="110"
              height="28"
              rx="3"
              fill="var(--color-folha)"
              stroke="var(--color-linha)"
            />
            <text x={c.x + 12} y={c.y + 18} fontSize="10.5" fill="var(--color-tinta2)">
              {c.t}
            </text>
          </g>
        ))}
      </g>

      {/* --- a seta --- */}
      <path d="M 244 100 h 34" stroke="var(--color-linha2)" strokeWidth="1.5" />
      <path d="M 272 95 l 8 5 l -8 5" stroke="var(--color-linha2)" strokeWidth="1.5" />

      {/* --- a folha única --- */}
      <rect
        x="296"
        y="24"
        width="156"
        height="152"
        rx="4"
        fill="var(--color-folha)"
        stroke="var(--color-linha2)"
      />
      <text x="310" y="44" fontSize="9.5" letterSpacing="0.9" fill="var(--color-tinta3)">
        UMA SESSÃO
      </text>
      {[
        "quem confirmou",
        "quem pagou",
        "quem tem recibo",
        "o que ficou a receber",
        "o que vai ao contador",
      ].map((t, i) => (
        <g key={t}>
          <rect
            x="310"
            y={56 + i * 23}
            width="4"
            height="4"
            fill={i === 3 ? "var(--color-aviso)" : "var(--color-cheia)"}
          />
          <text x="324" y={62 + i * 23} fontSize="10.5" fill="var(--color-tinta2)">
            {t}
          </text>
        </g>
      ))}
    </svg>
  );
}

// ============================================================ um registro

/**
 * Um gesto, cinco consequências.
 *
 * A auditoria disse que a página *"ensina o modelo contábil antes de mostrar o
 * trabalho que desaparece"*. Esta figura é a prova visual do contrário: o
 * quadrado à esquerda é a única coisa que a psicóloga faz; tudo à direita
 * acontece porque ela fez aquilo — e não é tarefa nova.
 *
 * As linhas saem todas do mesmo ponto de propósito. Se saíssem em cascata, o
 * desenho diria "cinco passos", que é exatamente o que ele existe para negar.
 */
export function UmRegistro({ className = "" }: { className?: string }) {
  const saidas = [
    "a cobrança do combinado",
    "o lembrete de pagamento",
    "a linha do recibo",
    "o número do contador",
    "o fechamento do mês",
  ];

  return (
    <svg
      role="img"
      aria-label="Um único gesto — marcar que a sessão aconteceu — e dele saem a cobrança, o lembrete de pagamento, a linha do recibo, o número do contador e o fechamento do mês."
      viewBox="0 0 440 190"
      className={className}
      fill="none"
    >
      <title>Você registra uma vez; o resto acompanha</title>

      {/* o gesto */}
      <rect
        x="6"
        y="66"
        width="150"
        height="58"
        rx="4"
        fill="var(--color-cheia-bg)"
        stroke="var(--color-cheia-linha)"
      />
      <rect x="6" y="66" width="3" height="58" rx="1.5" fill="var(--color-cheia)" />
      <text x="22" y="90" fontSize="10" letterSpacing="1.1" fill="var(--color-tinta3)">
        VOCÊ FAZ ISTO
      </text>
      <text x="22" y="110" fontSize="13" fill="var(--color-tinta)">
        a sessão aconteceu
      </text>

      {/* as consequências */}
      {saidas.map((t, i) => {
        const y = 14 + i * 34;
        return (
          <g key={t}>
            <path
              d={`M 156 95 C 196 95, 196 ${y + 14}, 236 ${y + 14}`}
              stroke="var(--color-linha2)"
              strokeWidth="1.2"
            />
            <rect
              x="236"
              y={y}
              width="198"
              height="28"
              rx="3"
              fill="var(--color-folha)"
              stroke="var(--color-linha)"
            />
            <text x="250" y={y + 18} fontSize="11" fill="var(--color-tinta2)">
              {t}
            </text>
          </g>
        );
      })}

      <text x="236" y="186" fontSize="9.5" letterSpacing="1.1" fill="var(--color-tinta3)">
        O SISTEMA FAZ ISTO — NÃO SÃO TAREFAS NOVAS
      </text>
    </svg>
  );
}

// ============================================================ os quatro glifos

/**
 * Um glifo por destino do horário, na própria célula da grade.
 *
 * Aqui a regra da cor faz todo o trabalho: **só o terceiro é rosa**, porque só
 * o terceiro é hora vazia. É o mesmo vocabulário que ela vai encontrar na
 * agenda depois de criar a conta — a landing não inventa uma linguagem visual
 * que a tela não usa.
 */
export function GlifoDoDestino({
  tipo,
}: {
  tipo: "recebida" | "receber" | "vazio" | "reposicao";
}) {
  const comum = { width: 34, height: 34, rx: 3 } as const;

  return (
    <svg aria-hidden viewBox="0 0 76 40" className="h-9 w-[76px]" fill="none">
      {tipo === "recebida" && (
        <>
          <rect
            x="3"
            y="3"
            {...comum}
            fill="var(--color-cheia-bg)"
            stroke="var(--color-cheia-linha)"
          />
          <path
            d="M 11 20 l 6 6 l 12 -14"
            stroke="var(--color-cheia)"
            strokeWidth="2"
            fill="none"
          />
        </>
      )}

      {tipo === "receber" && (
        <>
          <rect
            x="3"
            y="3"
            {...comum}
            fill="var(--color-cheia-bg)"
            stroke="var(--color-cheia-linha)"
          />
          <path d="M 11 20 l 6 6 l 12 -14" stroke="var(--color-cheia)" strokeWidth="2" fill="none" />
          <rect
            x="41"
            y="3"
            {...comum}
            fill="var(--color-aviso-bg)"
            stroke="var(--color-aviso-linha)"
            strokeDasharray="3 3"
          />
          <text
            x="52"
            y="26"
            fontSize="15"
            fontFamily="var(--font-mono)"
            fill="var(--color-aviso)"
          >
            ?
          </text>
        </>
      )}

      {tipo === "vazio" && (
        <rect
          x="3"
          y="3"
          {...comum}
          fill="var(--color-vaga-bg)"
          stroke="var(--color-vaga-linha)"
        />
      )}

      {tipo === "reposicao" && (
        <>
          <rect x="3" y="3" {...comum} fill="var(--color-folha)" stroke="var(--color-linha2)" />
          <path d="M 12 20 h 16" stroke="var(--color-linha2)" strokeWidth="1.5" />
          <path
            d="M 39 20 h 8"
            stroke="var(--color-linha2)"
            strokeWidth="1.2"
            strokeDasharray="2 2"
          />
          <rect
            x="41"
            y="3"
            {...comum}
            fill="var(--color-cheia-bg)"
            stroke="var(--color-cheia-linha)"
          />
          <path d="M 49 20 l 6 6 l 12 -14" stroke="var(--color-cheia)" strokeWidth="2" fill="none" />
        </>
      )}
    </svg>
  );
}

// ============================================================ o prontuário

/**
 * A folha do prontuário, com a lacuna aparecendo.
 *
 * O Manual do CFP pede que não se deixe espaço em branco. A frase antiga da
 * página — *"o que está em branco aparece em branco"* — era tautológica, e a
 * auditoria pediu que comunicasse a ação. O desenho faz o que a frase sozinha
 * não fazia: mostra o bloco vazio **marcado**, e não sumido.
 *
 * A marca do bloco vazio é âmbar, não rosa: é pendência com consequência, e
 * rosa aqui significaria hora não ocupada, que não é o assunto.
 */
export function FolhaDoProntuario({ className = "" }: { className?: string }) {
  /**
   * As alturas são somadas de cima para baixo, e a `viewBox` tem de caber a
   * soma. A primeira versão não cabia: o quarto bloco começava em y=258 numa
   * caixa de 260, e o **bloco pendente — que é o argumento inteiro da figura**
   * — ficava fora do desenho. Sobrava uma folha bonita provando o contrário do
   * que o texto ao lado dizia.
   */
  const blocos = [
    { t: "Identificação", n: 2, cheio: true },
    { t: "Avaliação da demanda", n: 3, cheio: true },
    { t: "Evolução", n: 4, cheio: true },
    { t: "Encerramento", n: 0, cheio: false },
  ];

  let y = 28;

  return (
    <svg
      role="img"
      aria-label="Uma folha de prontuário com quatro blocos: identificação, avaliação da demanda e evolução preenchidos, e encerramento mostrado explicitamente como pendente em vez de sumir da tela."
      viewBox="0 0 300 320"
      className={className}
      fill="none"
    >
      <title>Os quatro blocos, e a lacuna que aparece</title>

      <rect
        x="4"
        y="4"
        width="292"
        height="312"
        rx="4"
        fill="var(--color-folha)"
        stroke="var(--color-linha2)"
      />

      {blocos.map((b) => {
        const alturaBloco = b.cheio ? 20 + b.n * 9 + 6 : 52;
        const topo = y;
        y += alturaBloco + 12;

        return (
          <g key={b.t}>
            <text x="20" y={topo + 11} fontSize="9" letterSpacing="0.9" fill="var(--color-tinta3)">
              {b.t.toUpperCase()}
            </text>

            {b.cheio ? (
              Array.from({ length: b.n }).map((_, l) => (
                <rect
                  key={l}
                  x="20"
                  y={topo + 20 + l * 9}
                  width={l === b.n - 1 ? 148 : 258}
                  height="3.5"
                  rx="1.75"
                  fill="var(--color-linha)"
                />
              ))
            ) : (
              <>
                <rect
                  x="20"
                  y={topo + 18}
                  width="258"
                  height="28"
                  rx="3"
                  fill="var(--color-aviso-bg)"
                  stroke="var(--color-aviso-linha)"
                  strokeDasharray="4 3"
                />
                <text x="32" y={topo + 36} fontSize="10" fill="var(--color-aviso)">
                  pendente — aparece antes de concluir
                </text>
              </>
            )}
          </g>
        );
      })}

      {/* o carimbo de guarda, no rodapé da folha */}
      <path d="M 20 288 h 258" stroke="var(--color-linha)" />
      <text x="20" y="303" fontSize="9" fill="var(--color-tinta3)">
        guarda até 03/2031 · trilha de acesso ativa
      </text>
    </svg>
  );
}

// ============================================================ o separador

/**
 * Três células da grade, ao lado do rótulo da seção.
 *
 * Nasceu como um fio de um lado a outro com as células no meio, e flutuava
 * acima do rótulo como se fosse enfeite de convite. Encolheu para o que
 * precisava ser: uma marca pequena **na mesma linha** do rótulo, que diz de
 * onde a página vem sem disputar espaço com o que ela diz.
 *
 * Cinza, pelo motivo de sempre — rosa aqui significaria hora vazia.
 */
export function Fio({ className = "" }: { className?: string }) {
  return (
    <svg aria-hidden viewBox="0 0 40 10" className={`h-2.5 w-10 ${className}`} fill="none">
      {[0, 14, 28].map((x) => (
        <rect key={x} x={x + 0.5} y="0.5" width="9" height="9" stroke="var(--color-linha2)" />
      ))}
    </svg>
  );
}
