import { Suspense } from "react";
import Link from "next/link";
import { Marca } from "@/components/site/Marca";
import { Entrar } from "@/components/app/Entrar";
import { Confirmar } from "@/components/app/Confirmar";

export const metadata = { title: "Entrar" };

const RECADO: Record<string, string> = {
  link_expirado:
    "Esse link de confirmação já foi usado ou passou da validade. Entre com a sua senha, ou peça outro.",
  sem_codigo: "O link de confirmação veio incompleto. Tente abrir de novo pelo e-mail.",
};

export default async function PaginaEntrar({
  searchParams,
}: {
  searchParams: Promise<{ erro?: string }>;
}) {
  const { erro } = await searchParams;
  const recado = erro ? RECADO[erro] : undefined;

  return (
    <div className="flex min-h-dvh flex-col items-center justify-center px-5 py-12">
      {/* O link de confirmação do Supabase pode devolver a sessão no fragmento
          da URL, que o servidor não enxerga. Ver o cabeçalho do componente. */}
      <Suspense fallback={null}>
        <Confirmar />
      </Suspense>

      <Link href="/">
        <Marca className="text-[26px]" />
      </Link>

      {recado && (
        <p className="mt-6 max-w-[42ch] rounded-cartao border border-vaga-linha bg-vaga-bg px-4 py-3 text-center text-[12.5px] leading-relaxed text-tinta2">
          {recado}
        </p>
      )}

      <div className="mt-7 w-full max-w-[420px]">
        <Suspense fallback={null}>
          <Entrar />
        </Suspense>
      </div>

      {/* O rodapé desta tela dizia "ainda em construção... se você chegou aqui
          sem convite, entre na lista de espera" — e apontava para `/#lista`,
          uma âncora que não existe mais na landing.

          Era o erro mais caro do funil, e não era de copy: a página inteira
          promete "comece de graça, a conta se cria agora", e o clique seguinte
          parecia retirar o convite. A pessoa ficava sem saber se o produto está
          aberto, se a conta seria bloqueada depois, ou se ela deveria ter
          recebido algum convite que não recebeu.

          O produto está em produção. Então esta tela diz isso, e o que ela
          oferece agora é o que a landing prometeu. */}
      <p className="mt-6 max-w-[46ch] text-center text-[12px] leading-relaxed text-tinta2">
        O plano Grátis não expira e não pede cartão. Agenda, prontuário e o
        registro do mês são dele — você escolhe um plano pago só quando quiser
        que o sistema trabalhe no seu lugar.
      </p>

      <p className="mt-3 max-w-[46ch] text-center text-[11.5px] leading-relaxed text-tinta3">
        Prefere conversar antes?{" "}
        <Link href="/#conversa" className="underline underline-offset-2 hover:text-vaga">
          deixe seu e-mail
        </Link>{" "}
        e a gente marca vinte minutos.
      </p>

      {/* Os três documentos, **na tela em que se cria a conta**.
 
          O Leandro foi direto: *"eles precisam estar disponíveis antes da
          assinatura"*. E não é formalidade de LGPD — é a única tela do produto
          em que alguém decide confiar prontuário a um terceiro, e o Manual do
          CFP de nov/2025 manda a psicóloga conferir as cláusulas de eliminação
          do software que ela usa **antes** de fazer isso. Um link que só existe
          no rodapé da landing é um link que ela não vê no momento em que a
          pergunta aparece.
 
          Eles ficam abaixo do formulário, e não acima: quem chegou aqui já
          decidiu experimentar, e a leitura é uma escolha dela — não um portão. */}
      <div className="mt-8 border-t border-linha pt-5 text-center">
        <p className="text-[11.5px] leading-relaxed text-tinta2">
          Criando a conta você aceita os{" "}
          <Link href="/termos" className="underline underline-offset-2 hover:text-vaga">
            termos de serviço
          </Link>
          . Vale a pena ler antes a{" "}
          <Link href="/privacidade" className="underline underline-offset-2 hover:text-vaga">
            privacidade
          </Link>{" "}
          e a{" "}
          <Link href="/seguranca" className="underline underline-offset-2 hover:text-vaga">
            segurança
          </Link>{" "}
          — as duas dizem, com prazo e com número, o que acontece com o registro
          dos seus pacientes.
        </p>
      </div>
    </div>
  );
}
