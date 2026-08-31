import { Suspense } from "react";
import Link from "next/link";
import { Marca } from "@/components/site/Marca";
import { Entrar } from "@/components/app/Entrar";

export const metadata = { title: "Entrar" };

export default function PaginaEntrar() {
  return (
    <div className="flex min-h-dvh flex-col items-center justify-center px-5 py-12">
      <Link href="/">
        <Marca className="text-[26px]" />
      </Link>

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
