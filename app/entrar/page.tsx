import { Suspense } from "react";
import Link from "next/link";
import { Marca } from "@/components/site/Marca";
import { Entrar } from "@/components/app/Entrar";

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
    </div>
  );
}
