import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { hoje } from "@/lib/tempo-servidor";
import { mesAFechar, type PastaLinha, type RetratoPasta } from "@/lib/contador";
import { PainelContador } from "@/components/app/Contador";
import { adaptadorPara } from "@/lib/mensageria/adaptadores";

export const metadata = { title: "Contador" };

type ContaLinha = {
  contador_email: string | null;
  contador_nome: string | null;
  pasta_dia: number;
  pasta_ativa: boolean;
};

type Bruta = {
  id: string;
  competencia: string;
  versao: number;
  estado: "gerada" | "enviada" | "falhou";
  destino: string | null;
  enviada_em: string | null;
  erro: string | null;
  retrato: RetratoPasta;
};

/** Os doze meses fechados mais recentes — o corrente nunca entra. */
function mesesFechaveis(dia: string): string[] {
  const meses: string[] = [];
  let m = mesAFechar(dia);
  for (let i = 0; i < 12; i++) {
    meses.push(m);
    m = mesAFechar(`${m}-01`);
  }
  return meses;
}

export default async function Contador() {
  const supabase = await supabaseSessao();

  const [contas, brutas] = await Promise.all([
    db(
      "contador.conta",
      supabase
        .from("contas")
        .select("contador_email, contador_nome, pasta_dia, pasta_ativa")
        .limit(1),
    ) as Promise<unknown>,
    db(
      "contador.pastas",
      supabase
        .from("pastas_contador")
        .select("id, competencia, versao, estado, destino, enviada_em, erro, retrato")
        .order("competencia", { ascending: false })
        .order("versao", { ascending: false })
        .limit(24),
    ) as Promise<unknown>,
  ]);

  const conta = ((contas ?? []) as ContaLinha[])[0];
  const pastas = ((brutas ?? []) as Bruta[]) as PastaLinha[];

  return (
    <div className="mx-auto max-w-3xl">
      <h1 className="font-serif text-[28px] leading-tight tracking-[-0.015em]">
        Pasta do contador
      </h1>

      <p className="mt-3 max-w-2xl text-[14px] leading-relaxed text-tinta2">
        Todo mês, um arquivo com o que entrou e o que saiu — nas datas em que entrou e saiu —
        pronto para o seu contador importar. <b className="font-semibold text-tinta">Sem nome
        de paciente nenhum</b>: numa clínica de psicologia, a lista de quem pagou é a lista de
        quem faz terapia, e isso não sai daqui.
      </p>

      <PainelContador
        email={conta?.contador_email ?? null}
        nome={conta?.contador_nome ?? null}
        dia={conta?.pasta_dia ?? 5}
        ativa={Boolean(conta?.pasta_ativa)}
        pastas={pastas}
        mesesFechaveis={mesesFechaveis(hoje())}
        envioPorEmail={adaptadorPara("email").disponivel}
      />

      {/* ---------------------------------------------- o que vai e o que não vai */}
      <section className="mt-10 border-t border-linha pt-6">
        <h2 className="rotulo">O que vai no arquivo — e o que nunca vai</h2>
        <ul className="mt-3 max-w-2xl space-y-2 text-[13px] leading-relaxed text-tinta2">
          <li>
            <b className="font-medium text-tinta">Vai:</b> data, tipo (atendimento,
            mensalidade, pacote, compensação por cancelamento), descrição da despesa, valor de
            entrada e de saída. Mais um resumo com os totais e o saldo do mês.
          </li>
          <li>
            <b className="font-medium text-tinta">Não vai:</b> nome, telefone, e-mail ou CPF de
            paciente. Nem quantas sessões cada pessoa fez. O contador escritura o livro caixa
            com datas e valores; quem precisa saber quem pagou é a Receita, e ela já sabe pelos
            recibos que você emite no Receita Saúde.
          </li>
          <li>
            <b className="font-medium text-tinta">Regime de caixa.</b> A data de cada linha é a
            do <i>pagamento</i>, não a do atendimento — é assim que o carnê-leão funciona, e é
            o que faz o número bater com o seu extrato.
          </li>
          <li>
            <b className="font-medium text-tinta">Fechado é fechado.</b> Se um pagamento
            atrasado entrar depois, a pasta antiga não muda: nasce uma versão nova, que diz que
            substitui a anterior. Número que muda sozinho depois de enviado é o jeito mais
            rápido de o contador parar de confiar no arquivo.
          </li>
          <li>
            <b className="font-medium text-tinta">Se precisar da lista identificada</b> — para
            uma fiscalização, por exemplo —, ela existe na exportação completa da conta, em
            Conta. É um ato deliberado seu, com registro, e não um anexo que sai todo dia 5.
          </li>
        </ul>
      </section>
    </div>
  );
}
