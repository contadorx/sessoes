export const ENTRADA =
  "mt-1.5 w-full rounded-[5px] border border-linha2 bg-folha px-3 py-2.5 text-[14px] text-tinta";

export function Campo({
  rotulo,
  dica,
  children,
}: {
  rotulo: string;
  dica?: string;
  children: React.ReactNode;
}) {
  return (
    <label className="block">
      <span className="rotulo">{rotulo}</span>
      {children}
      {dica && <span className="mt-1 block text-[11px] text-tinta3">{dica}</span>}
    </label>
  );
}

export function Erros({ erros }: { erros: string[] }) {
  if (erros.length === 0) return null;
  return (
    <ul className="mt-4 rounded-cartao border border-vaga-linha bg-vaga-bg px-4 py-3">
      {erros.map((e) => (
        <li key={e} className="text-[12.5px] font-medium text-vaga">
          {e}
        </li>
      ))}
    </ul>
  );
}

export function Secao({ titulo, nota, children }: { titulo: string; nota?: string; children: React.ReactNode }) {
  return (
    <fieldset className="mt-6 border-t border-linha pt-5 first:mt-0 first:border-0 first:pt-0">
      <legend className="sr-only">{titulo}</legend>
      <p className="rotulo">{titulo}</p>
      {nota && <p className="mt-1 text-[12px] leading-relaxed text-tinta3">{nota}</p>}
      <div className="mt-3">{children}</div>
    </fieldset>
  );
}
