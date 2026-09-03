import Link from "next/link";
import { db } from "@/lib/db";
import { supabaseSessao } from "@/lib/supabase/server";
import { sessaoAtual, acessosDa } from "@/lib/conta";
import { fraseDoAcesso, ROTULO_PAPEL } from "@/lib/permissao";
import { destinos } from "@/lib/navegacao";
import { Sair } from "@/components/app/Sair";
import { FormPix, FormRitmo, FormAssinatura, FormRegua, FormRegime } from "@/components/app/Conta";
import type { Regime } from "@/lib/receitasaude";
import { FaixaNaConta } from "@/components/app/Faixa";
import { nomeDoPlano } from "@/lib/planos";
import { Avaliacao } from "@/components/app/Avaliacao";
import { faixaDaConta, avaliacaoPendente } from "@/app/(app)/encaixes/dados";

export const metadata = { title: "Perfil" };

type ContaLinha = {
  nome: string;
  plano: string;
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
  regime: Regime;
};

type ProfLinha = {
  id: string;
  crp: string | null;
  documento: string | null;
  assina_como: string | null;
};

export default async function Perfil() {
  const sessao = await sessaoAtual();
  const supabase = await supabaseSessao();

  const linhas = (await db(
    "conta.ler",
    supabase
      .from("contas")
      .select(
        "nome, plano, pix_chave, pix_nome, pix_cidade, cobranca_atraso_min, lembrete_horas, " +
          "silencio_inicio, silencio_fim, retencao_anos, cidade, regua_ativa, regua_dias, " +
          "mensalidade_dia, cobra_sessao, regime",
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

  // Só a contagem: a frase do rádio precisa saber quantas pendências a
  // mudança dispensaria, e ninguém decide o que não sabe que vai acontecer.
  const { count: pendentes } = await supabase
    .from("recibos_rfb")
    .select("id", { count: "exact", head: true })
    .eq("estado", "pendente");

  const [faixa, pendencia] = await Promise.all([faixaDaConta(), avaliacaoPendente()]);
  const acessos = acessosDa(sessao);

  return (
    <div className="mx-auto max-w-2xl">
      <h1 className="font-serif text-[28px] leading-tight tracking-[-0.015em]">
        {conta.nome}
      </h1>

      {/* ---------------------------------------------------- o "Mais" do celular

          No desktop estes caminhos estão no menu e no menu do perfil. No
          celular a barra de baixo tem cinco cadeiras e o Fechamento não cabe
          numa delas — é mensal, e o polegar é diário. Então ele mora aqui, que
          é onde a barra manda quem toca em "Mais".

          Não é duplicação de menu: é o mesmo destino aparecendo onde a mão
          alcança. */}
      <nav className="mt-6 grid gap-px overflow-hidden rounded-cartao border border-linha bg-linha sm:hidden">
        {destinos(acessos)
          .filter((d) => d.href === "/fechamento")
          .map((d) => (
            <Link key={d.href} href={d.href} className="bg-folha px-4 py-3 text-[13.5px] text-tinta2">
              {d.rotulo}
              <span className="mt-0.5 block text-[12px] text-tinta3">{d.descricao}</span>
            </Link>
          ))}
        <Link href="/perfil/horarios" className="bg-folha px-4 py-3 text-[13.5px] text-tinta2">
          Seus horários
          <span className="mt-0.5 block text-[12px] text-tinta3">A semana que você disponibiliza</span>
        </Link>
        <Link href="/perfil/integracoes" className="bg-folha px-4 py-3 text-[13.5px] text-tinta2">
          Integrações
          <span className="mt-0.5 block text-[12px] text-tinta3">Google Agenda</span>
        </Link>
        <Link href="/perfil/contrato" className="bg-folha px-4 py-3 text-[13.5px] text-tinta2">
          Contrato
          <span className="mt-0.5 block text-[12px] text-tinta3">O combinado por escrito</span>
        </Link>
        <div className="bg-folha px-4 py-3 text-[13.5px]">
          <Sair />
        </div>
      </nav>

      {/* --------------------------------------------------------- o seu acesso

          A frase descreve a **regra**, não uma suspeita sobre a pessoa: acesso
          clínico é decisão separada do cargo, e é isso que a psicóloga vai ter
          que explicar para quem trabalha com ela. Quem concede é a dona, e nem
          ela em si mesma — a tela não oferece o controle porque o banco recusa
          a operação (gatilho da migração 0049). */}
      <section className="mt-8">
        <h2 className="rotulo">O seu acesso</h2>
        <p className="mt-2 text-[13px] leading-relaxed text-tinta2">
          Você entra como <b className="font-medium text-tinta">{ROTULO_PAPEL[sessao.papel]}</b>.{" "}
          {fraseDoAcesso(acessos)}
        </p>
      </section>

      {/* ---------------------------------------------------------- o plano */}
      <section className="mt-8">
        <h2 className="rotulo">O seu plano</h2>
        {/* A unidade cobrada é a SESSÃO, e desde a 0060 ela é a única. O Grátis
            dá tudo o que é registro — agenda, prontuário, livro-razão, pacientes
            sem limite — e o que se cobra é o volume de trabalho que o sistema
            carrega junto. Fica visível o tempo todo: número que só aparece
            quando morde é armadilha.

            E ele **não** morde: passar da faixa não trava nada, não para
            mensagem nenhuma e não gera cobrança extra. */}
        <div className="mt-3 rounded-cartao border border-linha bg-folha px-5 py-4">
          {/* O nome do plano, que esta tela nunca escreveu.
              `nomeDoPlano` existe em `lib/planos.ts` desde sempre e não era
              chamada em tela nenhuma: o Perfil mostrava só a barra de uso, e
              quem quisesse saber em que plano está tinha de deduzir pelo
              tamanho do número. E é o **nome** que aparece, nunca o código
              (`gratis`, `solo`, `pro`) — a regra da OP10. */}
          <p className="text-[15px] font-semibold text-tinta">{nomeDoPlano(conta.plano)}</p>
          <div className="mt-2.5">
            <FaixaNaConta faixa={faixa} />
          </div>
        </div>
      </section>

      {/* ------------------------------------------------------- a avaliação */}
      {/* Fica no fim do Perfil, e é de propósito: a pergunta é o item menos
          importante de qualquer tela em que apareça, e ela não trava nada. Não
          aparece para conta nova, para quem usou pouco, para quem está com a
          assinatura em atraso, nem para quem já respondeu nos últimos 90 dias —
          e some de vez com um "agora não" que não pergunta por quê. */}
      <section className="mt-8">
        <h2 className="rotulo">O Sessões está servindo?</h2>
        <Avaliacao pendencia={pendencia} />
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

      {/* ---------------------------------------------------- horas declaradas

          Fica logo depois do plano porque é a primeira coisa que o produto
          precisa saber e a única que ele não consegue inferir de nada: quanto
          trabalhar é decisão dela. */}
      <section className="mt-8">
        <h2 className="rotulo">Quantas horas você disponibiliza</h2>
        <p className="mt-2 max-w-xl text-[13px] leading-relaxed text-tinta2">
          A sua semana declarada — atender, escrever prontuário, descansar. É o
          denominador de todo número que o sistema vai te mostrar, e o tempo que
          você reserva para não atender fica protegido: ele nunca aparece como
          hora vaga.
        </p>
        <Link
          href="/perfil/horarios"
          className="mt-3 inline-block rounded-full border border-linha2 px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2"
        >
          Ver e mudar a semana
        </Link>
      </section>

      {/* -------------------------------------------------------- regime fiscal

          Fica **acima** de "Como você recebe" de propósito: o regime decide
          qual obrigação existe, e a chave PIX é detalhe de operação dentro
          dela. E fica no Perfil, e não no Fechamento, porque não é uma
          preferência daquela tela — é um fato sobre quem atende. */}
      <section id="regime" className="mt-8 scroll-mt-20">
        <h2 className="rotulo">Como você atende</h2>
        <p className="mt-2 max-w-xl text-[13px] leading-relaxed text-tinta2">
          É esta escolha que decide a sua obrigação com a Receita — e não dá
          para o sistema adivinhar. Marcar errado aqui gera lista fiscal que
          você não tem, ou esconde a que você tem.
        </p>
        <div className="mt-3">
          <FormRegime
            regime={conta.regime ?? "pf"}
            pendentes={pendentes ?? 0}
            podeEditar={sessao.papel === "dona"}
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
          os números dela dentro — e que a pessoa aceita com data e hora. É o que
          dá base à cobrança de uma falta: sem ele, a regra é um combinado de boca
          que você precisa relembrar na hora mais difícil.
        </p>
        <Link
          href="/perfil/contrato"
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
      <section id="privacidade" className="mt-10 scroll-mt-20 border-t border-linha pt-6">
        <h2 className="rotulo">Privacidade e dados</h2>
        <p className="mt-2 max-w-xl text-[13px] leading-relaxed text-tinta2">
          Tudo o que está aqui é seu: pacientes, combinados, sessões, fila,
          cobranças e a trilha de acesso. Sai num arquivo, num clique, sem pedir
          para ninguém.
        </p>
        <div className="mt-3 flex flex-wrap items-center gap-2">
          <a
            href="/perfil/exportar"
            className="inline-block rounded-full border border-linha2 px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2"
          >
            Baixar tudo
          </a>
          {/* A trilha existe desde a B13 e ninguém nunca pôde lê-la. Ela vira
              link daqui porque é aqui que a promessa está escrita — "e a trilha
              de acesso" —, e registro que ninguém lê é registro que só serve
              depois do problema. */}
          <Link
            href="/perfil/trilha"
            className="inline-block rounded-full border border-linha2 px-4 py-2 text-[12.5px] font-medium text-tinta2 transition-colors hover:bg-folha2"
          >
            Ver a trilha de acesso
          </Link>
        </div>

        <p className="mt-3 text-[12px] leading-relaxed text-tinta3">
          Registro clínico fica guardado por {conta.retencao_anos} anos depois do
          último atendimento — é o que o Conselho exige.{" "}
          <Link href="/pacientes" className="underline underline-offset-2 hover:text-vaga">
            ver pacientes
          </Link>
        </p>

        {/* Discreto, e presente. Esconder a saída seria a mesma coisa que
            dificultá-la: um sistema que guarda prontuário e não mostra a porta
            não está retendo, está sequestrando — e é saber que a porta existe
            que torna razoável entrar. */}
        <p className="mt-4 text-[12px] leading-relaxed text-tinta3">
          <Link
            href="/perfil/encerrar"
            className="underline underline-offset-2 hover:text-vaga"
          >
            Encerrar a conta
          </Link>{" "}
          — apaga tudo, e só depois de você levar a sua cópia.
        </p>
      </section>
    </div>
  );
}
