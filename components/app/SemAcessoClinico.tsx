/**
 * A frase que aparece no lugar de uma tela clínica, para quem não tem acesso.
 *
 * Ela existe porque **tela em branco se lê como defeito**. A RLS já devolveria
 * vazio — a migração 0049 fechou isso no banco, e é lá que a proteção vale —, e
 * uma página vazia faria a pessoa achar que o prontuário sumiu, ou que o
 * sistema quebrou, e procurar suporte por um problema que não existe.
 *
 * E a frase diz **de quem é a decisão**. "Sem permissão" sozinho manda a pessoa
 * reclamar de nós; dizer que quem concede é a responsável pela conta manda ela
 * conversar com quem pode resolver.
 */
export function SemAcessoClinico({ o }: { o: string }) {
  return (
    <section className="rounded-cartao border border-linha bg-folha2 px-5 py-6">
      <p className="max-w-xl text-[13.5px] leading-relaxed text-tinta2">
        O {o} desta pessoa não aparece no seu acesso.
      </p>
      <p className="mt-2 max-w-xl text-[12.5px] leading-relaxed text-tinta3">
        Não é omissão da tela: acesso clínico é uma decisão separada do cargo, e
        quem concede é a responsável pela conta. Nada aqui foi escondido de você
        por engano.
      </p>
    </section>
  );
}
