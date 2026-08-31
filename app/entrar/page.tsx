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

      <p className="mt-6 max-w-[42ch] text-center text-[11.5px] leading-relaxed text-tinta3">
        Ainda em construção, com as primeiras psicólogas. Se você chegou aqui sem
        convite,{" "}
        <Link href="/#lista" className="underline underline-offset-2 hover:text-vaga">
          entre na lista de espera
        </Link>
        .
      </p>
    </div>
  );
}
