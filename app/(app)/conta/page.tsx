import Link from "next/link";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { sessaoAtual } from "@/lib/conta";
import { FormPix, FormRitmo, FormAssinatura, FormRegua } from "@/components/app/Conta";
import { TetoNaConta } from "@/components/app/Teto";
import { tetoDaConta } from "@/app/(app)/fila/dados";

export const metadata = { title: "Conta" };

type ContaLinha = {
  nome: string;
  pix_chave: string | null;
  pix_nome: string | null;
  pix_cidade: string | null;
  cobranca_atraso_min: number;
  lembrete_horas: number;
  silencio_inicio: string;
  silencio_fim: string;
  retencao_anos: number;
  cidade: string | null;
  regua_ativa: boolean;
  regua_dias: number[];
  mensalidade_dia: number;
  cobra_sessao: boolean;
};

type ProfLinha = {
  id: string;
  crp: string | null;
  documento: string | null;
  assina_como: string | null;
};

export default async function Conta() {
  const sessao = await sessaoAtual();
  const supabase = await supabaseSessao();

  const linhas = (await db(
    "conta.ler",
    supabase
      .from("contas")
      .select(
        "nome, pix_chave, pix_nome, pix_cidade, cobranca_atraso_min, lembrete_horas, " +
          "silencio_inicio, silencio_fim, retencao_anos, cidade, regua_ativa, regua_dias, " +
          "mensalidade_dia, cobra_sessao",
      )
      .eq("id", sessao.contaId)
      .limit(1),
  )) as unknown as ContaLinha[];

  const conta = linhas[0];

  const profs = (await db(
    "conta.profissional",
    supabase.from("profissionais").select("id, crp, documento, assina_como").limit(1),
  )) as unknown as ProfLinha[];

  const prof = profs[0];
  const teto = await tetoDaConta();

  return (
    <div className="mx-auto max-w-2xl">
      <h1 className="font-serif text-[28px] leading-tight tracking-[-0.015em]">
        {conta.nome}
      </h1>

      {/* ---------------------------------------------------------- o plano */}
      <section className="mt-8">
        <h2 className="rotulo">O seu plano</h2>
        {/* Um limite só, e é este. O Grátis dá tudo o que é registro — agenda,
            prontuário, livro-razão, pacientes sem limite — e cobra o que
            economiza tempo, que é a mensageria. Fica visível o tempo todo:
            limite que só aparece quando morde é armadilha. */}
        <div className="mt-3 rounded-cartao border border-linha bg-folha px-5 py-4">
          <TetoNaConta teto={teto} />
        </div>
      </section>

      {/* ------------------------------------------------------ assinatura */}
      <section className="mt-8">
        <h2 className="rotulo">Como você assina</h2>
        <p className="mt-2 max-w-xl text-[13px] leading-relaxed text-tinta2">
          Vai no recibo, na declaração e no informe anual. O CRP e o CPF são o
          que permite a pessoa usar o documento no convênio e no imposto de
          renda.
        </p>
        <div className="mt-3">
          <FormAssinatura
            assinaComo={prof?.assina_como ?? null}
            crp={prof?.crp ?? null}
            documento={prof?.documento ?? null}
            cidade={conta.cidade}
            podeEditar={Boolean(prof)}
          />
        </div>
      </section>

      {/* ------------------------------------------------------ recebimento */}
      <section className="mt-8">
        <h2 className="rotulo">Como você recebe</h2>
        <p className="mt-2 max-w-xl text-[13px] leading-relaxed text-tinta2">
          Com a chave aqui, toda cobrança gera um PIX copia e cola com o valor
          certo e um identificador que aparece no seu extrato. <b>O dinheiro cai
          direto na sua conta</b> — não passa por nós, não tem tarifa e não
          depende de aprovação de ninguém.
        </p>
        <div className="mt-3">
          <FormPix
            chave={conta.pix_chave}
            nome={conta.pix_nome}
            cidade={conta.pix_cidade}
            podeEditar={sessao.papel === "dona"}
          />
        </div>
      </section>

      {/* ----------------------------------------------------------- ritmo */}
      <section className="mt-10">
        <h2 className="rotulo">O ritmo das mensagens</h2>
        <p className="mt-2 max-w-xl text-[13px] leading-relaxed text-tinta2">
          Nada aqui muda o que já foi enfileirado — só o que vier daqui em
          diante.
        </p>
        <div className="mt-3">
          <FormRitmo
            atraso={conta.cobranca_atraso_min}
            lembrete={conta.lembrete_horas}
            mensalidadeDia={conta.mensalidade_dia}
            cobraSessao={conta.cobra_sessao}
            podeEditar={sessao.papel === "dona"}
          />
        </div>

        <p className="mt-3 text-[12px] leading-relaxed text-tinta3">
          Silêncio noturno: nada sai entre {conta.silencio_inicio.slice(0, 5)} e{" "}
          {conta.silencio_fim.slice(0, 5)}. Uma mensagem que cairia nesse
          intervalo espera o dia começar.
        </p>
      </section>

      {/* -------------------------------------------------------- o contrato */}
      <section className="mt-10">
        <h2 className="rotulo">O combinado por escrito</h2>
        <p className="mt-2 max-w-xl text-[13px] leading-relaxed text-tinta2">
          Um texto só, escrito uma vez, que vira o documento de cada pessoa com
          os números dela dentro — e que a pessoa aceita com data e hora. É o
          lastro da cobrança automática: sem ele, a regra de falta é um combinado
          de boca que você precisa relembrar na hora mais difícil.
        </p>
        <Link
          href="/contratos"
          className="mt-3 inline-block rounded-full border border-linha2 px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2"
        >
          Escrever o combinado
        </Link>
      </section>

      {/* ----------------------------------------------------------- régua */}
      <section className="mt-10">
        <h2 className="rotulo">Os lembretes de pagamento</h2>
        <p className="mt-2 max-w-xl text-[13px] leading-relaxed text-tinta2">
          Quando alguém fica com uma cobrança em aberto, o sistema lembra — no
          mesmo texto neutro, sem endurecer, e parando sozinho. É para você não
          precisar puxar o assunto.
        </p>
        <div className="mt-3">
          <FormRegua
            ativa={conta.regua_ativa}
            dias={conta.regua_dias}
            podeEditar={sessao.papel === "dona"}
          />
        </div>
      </section>

      {/* -------------------------------------------------------- seus dados */}
      <section className="mt-10 border-t border-linha pt-6">
        <h2 className="rotulo">Seus dados</h2>
        <p className="mt-2 max-w-xl text-[13px] leading-relaxed text-tinta2">
          Tudo o que está aqui é seu: pacientes, combinados, sessões, fila,
          cobranças e a trilha de acesso. Sai num arquivo, num clique, sem pedir
          para ninguém.
        </p>
        <a
          href="/conta/exportar"
          className="mt-3 inline-block rounded-full border border-linha2 px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2"
        >
          Baixar tudo
        </a>
        <p className="mt-3 text-[12px] leading-relaxed text-tinta3">
          Registro clínico fica guardado por {conta.retencao_anos} anos depois do
          último atendimento — é o que o Conselho exige.{" "}
          <Link href="/pacientes" className="underline underline-offset-2 hover:text-vaga">
            ver pacientes
          </Link>
        </p>
      </section>
    </div>
  );
}
