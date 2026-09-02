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
 * Quase tudo é SVG inline, sem dependência: a página continua sendo um
 * documento que carrega de uma vez. A exceção são as duas figuras editoriais do
 * fim do arquivo — elas explicam uma **ideia** (fragmentação e consequência) em
 * vez de desenhar um comportamento, e para ideia a ilustração matérica ganha de
 * um diagrama. Ver o cabeçalho de `FiguraEditorial`.
 */

import Image from "next/image";

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


// ============================================================ um registro


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


/**
 * A moldura das duas figuras fotografadas.
 *
 * **Elas não são SVG, e é a primeira exceção deste arquivo.** As outras figuras
 * daqui existem porque desenham comportamento — a cascata da fila, a tela
 * bloqueada, a folha do prontuário. Estas duas explicam uma ideia (fragmentação
 * e consequência), e para ideia a ilustração matérica ganha: ela dá
 * profundidade a uma página que, fora as figuras, é feita de caixas brancas.
 *
 * TRÊS DECISÕES DE IMPLEMENTAÇÃO
 *
 * **1 · Nenhuma palavra dentro da imagem.** A explicação fica na legenda, em
 * HTML — legível por leitor de tela, traduzível, indexável pelo buscador e
 * responsiva. Texto gravado em pixel é texto que não existe para metade da
 * internet.
 *
 * **2 · `alt` vazio e `aria-hidden`.** A legenda já diz o que a figura diz; um
 * `alt` repetindo a legenda faria o leitor de tela ler a mesma frase duas
 * vezes. Imagem decorativa de conteúdo já descrito ao lado se marca como
 * decorativa — é o que a WCAG chama de texto redundante.
 *
 * **3 · A proporção é a da própria imagem (3:2), e não 16:9.** Com uma moldura
 * de proporção diferente sobraria faixa nas laterais, e `object-fit: cover`
 * resolveria isso cortando — justamente o que não se pode fazer aqui, porque os
 * objetos encostam nas bordas. Declarar `width` e `height` reserva o espaço
 * certo antes de a imagem chegar, e a página não pula durante o carregamento.
 */
export function FiguraEditorial({
  src,
  legenda,
  className = "",
}: {
  src: string;
  legenda: React.ReactNode;
  className?: string;
}) {
  return (
    <figure className={`overflow-hidden rounded-cartao border border-linha ${className}`}>
      <Image
        src={src}
        alt=""
        aria-hidden="true"
        width={1536}
        height={1024}
        loading="lazy"
        className="block h-auto w-full"
        // O celular recebe um recorte de ~430px, e não os 1536 do arquivo. É a
        // diferença entre 70 KB e 15 KB numa página que alguém abre pelo
        // telefone, no meio do dia, entre duas sessões.
        sizes="(min-width: 1024px) 720px, 100vw"
      />
      <figcaption className="border-t border-linha bg-folha px-5 py-3.5 text-[12px] leading-relaxed text-tinta3">
        {legenda}
      </figcaption>
    </figure>
  );
}
