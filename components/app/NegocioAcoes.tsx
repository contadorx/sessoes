"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import {
  abrirAssinatura,
  cancelarAssinatura,
  mudarPlano,
  emitirFatura,
  baixarFatura,
  estornarFatura,
  cancelarFatura,
  marcarContaDeTeste,
  lancarCustoFixo,
  definirPrecoCanal,
  marcarAvisoEnviado,
  type Resultado,
} from "@/app/(app)/negocio/acoes";
import { causasParaEscolher, type Plano } from "@/lib/negocio";

/**
 * Os controles do painel — a parte que a OP1 não construiu.
 *
 * Todos seguem a mesma forma: um `form` que chama uma ação do servidor, que
 * chama uma função do banco. Nenhum deles escreve numa tabela, e nenhum
 * confere permissão sozinho: quem confere é a função, três camadas abaixo.
 *
 * O que estes componentes fazem de próprio é **não oferecer o que vai ser
 * recusado** e **mostrar a frase do banco quando algo é recusado mesmo assim**.
 * As mensagens da 0050 foram escritas para serem lidas por gente ("esta conta
 * já tem assinatura viva — cancele a atual antes de abrir outra"), então
 * traduzi-las de novo aqui só faria as duas versões divergirem com o tempo.
 */

const INICIAL: Resultado = { estado: "ok", mensagem: "" };

function Botao({ children, perigo = false }: { children: React.ReactNode; perigo?: boolean }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className={`rounded-full px-3.5 py-1.5 text-[12.5px] font-medium transition-opacity disabled:opacity-45 ${
        perigo
          ? "border border-vaga-linha text-vaga hover:bg-vaga-bg"
          : "border border-linha2 text-tinta2 hover:bg-folha2"
      }`}
    >
      {pending ? "…" : children}
    </button>
  );
}

function Aviso({ r }: { r: Resultado }) {
  if (!r.mensagem) return null;
  return (
    <p
      className={`mt-2 text-[12px] leading-relaxed ${
        r.estado === "erro" ? "text-vaga" : "text-cheia"
      }`}
    >
      {r.mensagem}
    </p>
  );
}

const campo =
  "rounded-[5px] border border-linha2 bg-folha px-2.5 py-1.5 text-[12.5px] text-tinta";

// ============================================ assinatura

export function AbrirAssinatura({ conta, planos }: { conta: string; planos: Plano[] }) {
  const [r, acao] = useActionState(abrirAssinatura, INICIAL);
  return (
    <form action={acao} className="flex flex-wrap items-center gap-2">
      <input type="hidden" name="conta" value={conta} />
      <select name="plano" className={campo} defaultValue={planos[1]?.codigo ?? "solo"}>
        {planos.map((p) => (
          <option key={p.codigo} value={p.codigo}>
            {p.nome}
          </option>
        ))}
      </select>
      <select name="ciclo" className={campo} defaultValue="mensal">
        <option value="mensal">mensal</option>
        <option value="anual">anual</option>
      </select>
      <select name="origem" className={campo} defaultValue="painel">
        <option value="painel">painel</option>
        <option value="checkout">checkout</option>
        <option value="cortesia">cortesia</option>
        <option value="importada">importada</option>
      </select>
      <label className="flex items-center gap-1.5 text-[12px] text-tinta2">
        <input type="checkbox" name="trial" /> em teste
      </label>
      <Botao>Abrir assinatura</Botao>
      <Aviso r={r} />
    </form>
  );
}

export function MudarPlano({ conta, planos }: { conta: string; planos: Plano[] }) {
  const [r, acao] = useActionState(mudarPlano, INICIAL);
  return (
    <form action={acao} className="flex flex-wrap items-center gap-2">
      <input type="hidden" name="conta" value={conta} />
      <select name="plano" className={campo}>
        {planos.map((p) => (
          <option key={p.codigo} value={p.codigo}>
            {p.nome}
          </option>
        ))}
      </select>
      <input name="motivo" placeholder="por que mudou" className={`${campo} min-w-[16rem] flex-1`} />
      <Botao>Mudar de plano</Botao>
      <Aviso r={r} />
    </form>
  );
}

/**
 * Cancelar pede motivo, e o campo não é opcional nem no banco.
 *
 * Fica atrás de um clique de confirmação: é a ação que rebaixa a conta de
 * alguém, e um botão de cancelar assinatura ao lado de um botão de emitir
 * fatura é um acidente esperando o dia cansado.
 */
export function CancelarAssinatura({ assinatura }: { assinatura: string }) {
  const [r, acao] = useActionState(cancelarAssinatura, INICIAL);
  const [aberto, setAberto] = useState(false);

  if (!aberto) {
    return (
      <button
        type="button"
        onClick={() => setAberto(true)}
        className="toque text-[12.5px] text-tinta3 underline decoration-linha2 underline-offset-4 hover:text-vaga"
      >
        cancelar assinatura
      </button>
    );
  }

  return (
    <form action={acao} className="flex flex-col gap-2">
      <input type="hidden" name="assinatura" value={assinatura} />

      {/* **A frase primeiro, a categoria depois.** A ordem não é estética: o
          que aconteceu de verdade está na frase, e escolher a categoria antes
          de escrever faz a frase virar justificativa da caixinha escolhida. */}
      <input
        name="motivo"
        autoFocus
        placeholder="o que ela disse, com as palavras dela"
        className={`${campo} w-full`}
      />

      <div className="flex flex-wrap items-center gap-2">
        <select name="causa" defaultValue="" className={campo}>
          <option value="" disabled>
            e o que isso foi…
          </option>
          {causasParaEscolher().map((c) => (
            <option key={c.valor} value={c.valor}>
              {c.rotulo}
            </option>
          ))}
        </select>
        <Botao perigo>Confirmar cancelamento</Botao>
        <button
          type="button"
          onClick={() => setAberto(false)}
          className="text-[12px] text-tinta3 hover:text-tinta2"
        >
          deixa
        </button>
      </div>

      <p className="max-w-[62ch] text-[11.5px] leading-relaxed text-tinta3">
        A frase é dela; a categoria é minha. As duas existem porque juntar as
        duas perde uma das duas — a lista sozinha não diz o que construir, e a
        frase sozinha não se conta.
      </p>

      <Aviso r={r} />
    </form>
  );
}

// ============================================ a régua da assinatura

/**
 * Um aviso da régua, com o texto à mostra e um botão que só registra.
 *
 * O texto aparece inteiro de propósito: enquanto não houver provedor de
 * e-mail, quem manda sou eu, e um botão "enviar" que não envia seria uma
 * mentira de uma palavra. O que existe é "copiei e mandei".
 */
export function AvisoDaRegua({ aviso, assunto, corpo }: {
  aviso: string;
  assunto: string;
  corpo: string;
}) {
  const [r, acao] = useActionState(marcarAvisoEnviado, INICIAL);
  const [aberto, setAberto] = useState(false);

  return (
    <div>
      <button
        type="button"
        onClick={() => setAberto((v) => !v)}
        className="toque text-[12px] text-tinta3 underline decoration-linha2 underline-offset-4 hover:text-vaga"
      >
        {aberto ? "esconder o texto" : "ver o texto do aviso"}
      </button>

      {aberto && (
        <div className="mt-2 rounded-cartao border border-linha bg-folha px-4 py-3">
          <p className="text-[12.5px] font-medium text-tinta">{assunto}</p>
          <p className="mt-1.5 whitespace-pre-line text-[12.5px] leading-relaxed text-tinta2">
            {corpo}
          </p>
        </div>
      )}

      <form action={acao} className="mt-2 flex flex-wrap items-center gap-2">
        <input type="hidden" name="aviso" value={aviso} />
        <Botao>Já mandei este</Botao>
        <Aviso r={r} />
      </form>
    </div>
  );
}

// ============================================ fatura

export function EmitirFatura({ assinatura }: { assinatura: string }) {
  const [r, acao] = useActionState(emitirFatura, INICIAL);
  return (
    <form action={acao} className="flex flex-wrap items-center gap-2">
      <input type="hidden" name="assinatura" value={assinatura} />
      <label className="text-[12px] text-tinta3">
        competência
        <input type="month" name="competencia" className={`${campo} ml-1.5`} />
      </label>
      <Botao>Emitir fatura</Botao>
      <Aviso r={r} />
    </form>
  );
}

export function AcoesDaFatura({ fatura, estado }: { fatura: string; estado: string }) {
  const [rb, baixar] = useActionState(baixarFatura, INICIAL);
  const [rc, cancelar] = useActionState(cancelarFatura, INICIAL);
  const [re, estornar] = useActionState(estornarFatura, INICIAL);
  const [estornando, setEstornando] = useState(false);

  if (estado === "pendente" || estado === "vencida") {
    return (
      <div className="flex flex-wrap items-center gap-2">
        <form action={baixar}>
          <input type="hidden" name="fatura" value={fatura} />
          <Botao>Baixar</Botao>
        </form>
        <form action={cancelar}>
          <input type="hidden" name="fatura" value={fatura} />
          <Botao>Cancelar</Botao>
        </form>
        <Aviso r={rb.mensagem ? rb : rc} />
      </div>
    );
  }

  if (estado === "paga") {
    if (!estornando) {
      return (
        <button
          type="button"
          onClick={() => setEstornando(true)}
          className="toque text-[12px] text-tinta3 underline decoration-linha2 underline-offset-4 hover:text-vaga"
        >
          estornar
        </button>
      );
    }
    return (
      <form action={estornar} className="flex flex-wrap items-center gap-2">
        <input type="hidden" name="fatura" value={fatura} />
        <input
          name="motivo"
          autoFocus
          placeholder="por que estornou"
          className={`${campo} min-w-[16rem]`}
        />
        <Botao perigo>Estornar</Botao>
        <Aviso r={re} />
      </form>
    );
  }

  // Cancelada e estornada não voltam. Um botão aqui só saberia falhar.
  return null;
}

// ============================================ a marca de teste

export function MarcaDeTeste({ conta, marcada }: { conta: string; marcada: boolean }) {
  const [r, acao] = useActionState(marcarContaDeTeste, INICIAL);
  return (
    <form action={acao} className="inline-flex items-center gap-2">
      <input type="hidden" name="conta" value={conta} />
      <input type="hidden" name="marcar" value={marcada ? "nao" : "sim"} />
      <Botao>{marcada ? "Desmarcar conta de teste" : "Marcar como conta de teste"}</Botao>
      <Aviso r={r} />
    </form>
  );
}

// ============================================ custo e preço

export function LancarCusto({ mes }: { mes: string }) {
  const [r, acao] = useActionState(lancarCustoFixo, INICIAL);
  return (
    <form action={acao} className="flex flex-wrap items-end gap-2">
      <input type="hidden" name="mes" value={mes} />
      <label className="text-[12px] text-tinta3">
        rubrica
        <input name="rubrica" placeholder="supabase" className={`${campo} ml-1.5`} />
      </label>
      <label className="text-[12px] text-tinta3">
        valor em reais
        <input name="valor" inputMode="decimal" placeholder="120,00" className={`${campo} ml-1.5 w-28`} />
      </label>
      <label className="text-[12px] text-tinta3">
        nota
        <input name="nota" className={`${campo} ml-1.5`} />
      </label>
      <Botao>Lançar</Botao>
      <Aviso r={r} />
    </form>
  );
}

/**
 * O preço vai em **milésimos de centavo**, e o rótulo diz isso com exemplo.
 *
 * `precos_canal` guarda milésimos porque um e-mail custa 0,2 centavo:
 * arredondar para centavo daria zero, e mil e-mails custariam nada. Um campo
 * chamado só "preço" faria eu digitar `0,2` no dia cansado e o painel passaria
 * a mostrar margem cheia.
 */
export function DefinirPreco({ hoje }: { hoje: string }) {
  const [r, acao] = useActionState(definirPrecoCanal, INICIAL);
  return (
    <form action={acao} className="flex flex-wrap items-end gap-2">
      <label className="text-[12px] text-tinta3">
        canal
        <select name="canal" className={`${campo} ml-1.5`}>
          <option value="whatsapp">whatsapp</option>
          <option value="sms">sms</option>
          <option value="email">email</option>
        </select>
      </label>
      <label className="text-[12px] text-tinta3">
        a partir de
        <input type="date" name="vigencia" defaultValue={hoje} className={`${campo} ml-1.5`} />
      </label>
      <label className="text-[12px] text-tinta3">
        milésimos de centavo
        <input
          name="milesimos"
          inputMode="numeric"
          placeholder="5000 = 5 centavos"
          className={`${campo} ml-1.5 w-40`}
        />
      </label>
      <label className="text-[12px] text-tinta3">
        fonte
        <input name="fonte" placeholder="tabela Gupshup" className={`${campo} ml-1.5`} />
      </label>
      <Botao>Declarar</Botao>
      <Aviso r={r} />
    </form>
  );
}
