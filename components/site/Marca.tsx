export function Marca({ className = "" }: { className?: string }) {
  return (
    <span
      className={`font-serif font-medium tracking-[-0.01em] text-tinta ${className}`}
    >
      Sessões<span className="text-vaga">.</span>
    </span>
  );
}
