"use client";

import { useState } from "react";
import { SubirFigura, Biblioteca } from "@/components/app/Figuras";
import { tamanhoLegivel, type Figura } from "@/lib/blog";

/**
 * A biblioteca como página, e não como janela dentro do editor.
 *
 * A lista vive em estado local porque subir e tirar acontecem sem recarregar:
 * um `revalidatePath` traria a lista de volta do servidor, mas com um piscar de
 * página inteira a cada arquivo — e quem sobe figura costuma subir cinco.
 */
export function Acervo({ figuras }: { figuras: Figura[] }) {
  const [acervo, setAcervo] = useState<Figura[]>(figuras);

  const bytes = acervo.reduce((s, f) => s + f.bytes, 0);
  const presas = acervo.filter((f) => f.usos_no_ar > 0).length;

  return (
    <div>
      <SubirFigura aoSubir={(f) => setAcervo([f, ...acervo])} />

      {acervo.length > 0 && (
        <p className="mt-4 text-[12px] text-tinta3">
          {acervo.length} figura{acervo.length > 1 ? "s" : ""} · {tamanhoLegivel(bytes)}
          {presas > 0 && ` · ${presas} em texto que já estreou`}
        </p>
      )}

      <Biblioteca
        figuras={acervo}
        aoSumir={(id) => setAcervo(acervo.filter((f) => f.id !== id))}
      />
    </div>
  );
}
