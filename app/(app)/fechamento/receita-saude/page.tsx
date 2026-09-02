import Link from "next/link";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { hoje } from "@/lib/tempo-servidor";
import {
  lerPainel,
  prazoDoAno,
  diaBr,
  fraseDmed,
  fraseNfse,
  type PainelBruto,
  type Regime,
} from "@/lib/receitasaude";
import {
  PainelReceitaSaude,
  type AEmitir,
  type Registrado,
} from "@/components/app/ReceitaSaude";

export const metadata = { title: "Receita Saúde" };

type Bruta = {
  id: string;
  pago_em: string;
  valor: string;
  estado: string;
  numero_rfb: string | null;
  emitido_em: string | null;
  dispensa_motivo: string | null;
  divergente_em: string | null;
  pacientes: { nome: string } | null;
};

export default async function ReceitaSaude({
  searchParams,
}: {
  searchParams: Promise<{ ano?: string }>;
}) {
  const params = await searchParams;
  const atual = Number(hoje().slice(0, 4));

  const ano = /^\d{4}$/.test(params.ano ?? "") ? Number(params.ano) : atual;
  const seguro = ano >= 2000 && ano <= 2100 ? ano : atual;

  const supabase = await supabaseSessao();

  // O regime primeiro, e sozinho: conta PJ não tem Receita Saúde nenhum, e
  // pedir painel, lista e histórico para depois esconder tudo seria três
  // consultas para desenhar uma tela que não é essa.
  const contas = (await db(
    "rfb.regime",
    supabase.from("contas").select("regime").limit(1),
  )) as unknown as { regime: Regime }[];
  const regime: Regime = contas[0]?.regime ?? "pf";

  if (regime === "pj") return <ContaPj ano={seguro} hoje={hoje()} />;

  const [bruto, lista, feitos] = await Promise.all([
    db("rfb.painel", supabase.rpc("receita_saude_do_ano", { p_ano: seguro })) as Promise<unknown>,
    db("rfb.a_emitir", supabase.rpc("recibos_rfb_a_emitir", { p_ano: seguro })) as Promise<unknown>,
    db(
      "rfb.registrados",
      supabase
        .from("recibos_rfb")
        .select(
          "id, pago_em, valor, estado, numero_rfb, emitido_em, dispensa_motivo, divergente_em, pacientes ( nome )",
        )
        .in("estado", ["emitido", "dispensado"])
        .gte("competencia", `${seguro}-01-01`)
        .lte("competencia", `${seguro}-12-31`)
        .order("pago_em", { ascending: false })
        .limit(60),
    ) as Promise<unknown>,
  ]);

  const painel = lerPainel(bruto as PainelBruto);
  const aEmitir = (lista ?? []) as AEmitir[];
  const registrados: Registrado[] = ((feitos ?? []) as Bruta[]).map((r) => ({
    id: r.id,
    nome: r.pacientes?.nome ?? "—",
    pago_em: r.pago_em,
    valor: r.valor,
    estado: r.estado,
    numero_rfb: r.numero_rfb,
    emitido_em: r.emitido_em,
    dispensa_motivo: r.dispensa_motivo,
    divergente_em: r.divergente_em,
  }));

  return (
    <div className="mx-auto max-w-3xl">
      <div className="flex flex-wrap items-baseline gap-x-4 gap-y-1">
        <h1 className="font-serif text-[28px] leading-tight tracking-[-0.015em]">
          Receita Saúde · {seguro}
        </h1>
        <nav className="ml-auto flex items-center gap-3 text-[12.5px]">
          <Link href={`/fechamento/receita-saude?ano=${seguro - 1}`} className="text-tinta2 hover:text-vaga">
            ← {seguro - 1}
          </Link>
          {seguro < atual && (
            <Link href="/fechamento/receita-saude" className="text-tinta3 hover:text-vaga">
              {atual}
            </Link>
          )}
        </nav>
      </div>

      <p className="mt-3 max-w-2xl text-[14px] leading-relaxed text-tinta2">
        Desde <b className="font-semibold text-tinta">1º de janeiro de 2025</b>, a profissional
        de saúde autônoma emite o recibo de <b>cada pagamento recebido</b> no app Receita Saúde
        ou no e-CAC — e é esse recibo que alimenta o carnê-leão. O retroativo de{" "}
        {seguro} fecha em <b className="font-semibold text-tinta">{diaBr(prazoDoAno(seguro))}</b>.
      </p>

      <PainelReceitaSaude
        painel={painel}
        aEmitir={aEmitir}
        registrados={registrados}
        hoje={hoje()}
        ano={seguro}
      />

      {/* ------------------------------------------- o que este modo não faz */}
      <section className="mt-10 border-t border-linha pt-6">
        <h2 className="rotulo">O que este modo não faz</h2>
        <ul className="mt-3 max-w-2xl space-y-2 text-[13px] leading-relaxed text-tinta2">
          <li>
            <b className="font-medium text-tinta">Não emite, e não vai emitir.</b> A Receita não
            publica API. Qualquer sistema que prometa emitir por você está prometendo o que não
            pode cumprir — e o preço de acreditar é a multa.
          </li>
          <li>
            <b className="font-medium text-tinta">Não inventa o valor da multa.</b> A regra é R$
            100 por mês-calendário ou fração, por recibo. O que aparece aqui é o{" "}
            <i>piso</i> — R$ 100 por pendência. O número real depende de quanto cada um atrasou,
            e chutar imposto é errar do lado que custa dinheiro.
          </li>
          <li>
            <b className="font-medium text-tinta">Não conta a falta cobrada.</b> Multa de
            cancelamento não é atendimento prestado, então não vira recibo de serviço de saúde.
            Ela continua no{" "}
            <Link href="/recebimentos/movimentacoes" className="underline underline-offset-2 hover:text-vaga">
              Financeiro
            </Link>{" "}
            e aparece aqui como o que ficou de fora.
          </li>
          <li>
            <b className="font-medium text-tinta">Não apaga o que venceu.</b> Passado o prazo, a
            pendência fica marcada como fora do prazo. Sumir com ela seria esta tela dizer
            &ldquo;tudo em dia&rdquo; no dia seguinte ao prejuízo.
          </li>
          <li>
            <b className="font-medium text-tinta">Não substitui o seu contador.</b> O sistema
            entrega o número certo e a lista na ordem; quem decide o que declarar e como é
            você, com quem cuida da sua contabilidade.
          </li>
        </ul>
      </section>
    </div>
  );
}

/**
 * A tela de quem atende por CNPJ.
 *
 * Ela existe porque a alternativa é pior: esconder o item do menu deixaria a
 * psicóloga que virou PJ achando que o produto quebrou, e mostrar a lista
 * vazia deixaria achando que está tudo em dia. O que ela precisa ver é que a
 * obrigação **é outra** — e quais são as datas dessa outra.
 *
 * Nenhuma das datas é calculada aqui. A DMED vence no último dia **útil** de
 * fevereiro, e fevereiro é o mês do Carnaval: o dia depende de feriado móvel e
 * de feriado municipal. Chutar seria pior que não dizer, porque quem confia num
 * dia errado perde o prazo achando que ainda tinha um.
 */
function ContaPj({ ano, hoje: dia }: { ano: number; hoje: string }) {
  return (
    <div className="mx-auto max-w-3xl">
      <h1 className="font-serif text-[28px] leading-tight tracking-[-0.015em]">
        Receita Saúde
      </h1>

      <p className="mt-3 max-w-2xl text-[14px] leading-relaxed text-tinta2">
        Esta conta está marcada como <b className="font-semibold text-tinta">pessoa jurídica</b>,
        e o Receita Saúde é obrigação do profissional na qualidade de{" "}
        <b className="font-semibold text-tinta">pessoa física</b>. Aqui não há recibo a emitir —
        o caminho é a NFS-e.{" "}
        <Link href="/perfil#regime" className="underline underline-offset-2 hover:text-vaga">
          Se isso estiver errado, mude em Perfil
        </Link>
        .
      </p>

      <section className="mt-8">
        <h2 className="rotulo">O que fica no lugar</h2>
        <ul className="mt-3 max-w-2xl space-y-2 text-[13px] leading-relaxed text-tinta2">
          <li>
            <b className="font-medium text-tinta">NFS-e a cada atendimento.</b> {fraseNfse(dia)}{" "}
            Até o fim de 2026 a nota não é rejeitada por erro de preenchimento, mas a
            obrigação de emitir já vale.
          </li>
          <li>
            <b className="font-medium text-tinta">DMED, uma vez por ano.</b> {fraseDmed(ano)}{" "}
            Ela declara quem pagou, quanto e o CPF — e é o que aparece na declaração
            pré-preenchida do paciente.
          </li>
          <li>
            <b className="font-medium text-tinta">O que sai da empresa para você</b> é
            pró-labore ou distribuição de lucro, e tem apuração própria. Nada disso passa
            pelo Receita Saúde.
          </li>
        </ul>
        <p className="mt-4 max-w-2xl text-[12.5px] leading-relaxed text-tinta3">
          O sistema não emite NFS-e e não transmite DMED. O que ele faz é o{" "}
          <Link href="/fechamento/contador" className="underline underline-offset-2 hover:text-vaga">
            fechamento do mês para o seu contador
          </Link>
          , com o valor recebido, a data e a pessoa — que é o que ele precisa para
          fazer as duas coisas.
        </p>
      </section>
    </div>
  );
}
