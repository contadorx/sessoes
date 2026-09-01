/**
 * O nome, com o ponto rosa.
 *
 * **A prop `peso` existe por causa de uma desproporção real.** A marca era
 * sempre `font-medium`; dentro de um título — que já é a mesma serif, num
 * peso mais leve — ela aparecia mais escura e mais pesada que a frase em
 * volta, e o nome saltava do meio da sentença como se estivesse gritando.
 *
 * Quando a marca é **assinatura** (cabeçalho, rodapé) ela é `medium` e é o
 * objeto mais firme da linha. Quando ela é **palavra dentro de uma frase**,
 * herda o peso de quem a contém: ali ela é sujeito da oração, não logotipo.
 *
 * O tamanho segue a mesma lógica e por isso não tem padrão embutido: quem
 * chama diz. Sem isso a marca dentro de um h1 de 46px virava um segundo
 * logotipo, duas vezes maior que o do cabeçalho, na mesma tela — que era
 * exatamente a desproporção que se via.
 */
export function Marca({
  className = "",
  peso = "assinatura",
}: {
  className?: string;
  peso?: "assinatura" | "texto";
}) {
  return (
    <span
      className={`font-serif tracking-[-0.01em] text-tinta ${
        peso === "assinatura" ? "font-medium" : "font-[inherit]"
      } ${className}`}
    >
      Sessões<span className="text-vaga">.</span>
    </span>
  );
}
