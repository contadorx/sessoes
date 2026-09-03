import { lerPanorama, fraseDoPanorama, type Panorama, type Gravidade } from "@/lib/mensageria/panorama";
import { fraseDoCusto, precoEmReais, type Canal } from "@/lib/mensageria/roteamento";

/**
 * O painel do canal, na tela do operador. (B56)
 *
 * **É uma lista de silêncios, e não um gráfico de volume.** Um sistema de
 * mensagens falha calado: não há tela vermelha, não há exceção, não há linha de
 * log — a mensagem simplesmente não chega, e quem descobre é a paciente que não
 * foi avisada. Volume não denuncia nenhum desses casos; a ausência de
 * confirmação denuncia todos.
 *
 * Ele mora em `/negocio` porque é **infraestrutura da plataforma**, e não conta
 * dela: credencial, disjuntor, batimento do cron. A psicóloga nunca lê esta
 * tela — o que ela precisa saber já aparece onde ela trabalha, na caixa "Na sua
 * mão", e o resto é problema nosso.
 *
 * Quando não há achado nenhum, a seção **não desaparece**: ela diz que está
 * quieto. Seção que some quando está tudo bem ensina a não procurá-la, e aí
 * ninguém a abre no dia em que ela teria algo a dizer.
 */

const COR: Record<Gravidade, string> = {
  cego: "border-vaga-linha bg-vaga-bg text-vaga",
  degradado: "border-aviso-linha bg-aviso-bg text-aviso",
  parado: "border-vaga-linha bg-vaga-bg text-vaga",
  quieto: "border-linha bg-folha2 text-tinta2",
};

const ROTULO: Record<Gravidade, string> = {
  cego: "cego",
  degradado: "degradado",
  parado: "parado",
  quieto: "quieto",
};

export function CanalPanorama({ panorama }: { panorama: Panorama | null }) {
  if (!panorama) {
    return (
      <section className="mt-10 border-t border-linha pt-6">
        <h2 className="rotulo">O canal</h2>
        <p className="mt-2 text-[13px] text-tinta2">
          O panorama não voltou. Isso é erro, não ausência de dado — vale olhar o log.
        </p>
      </section>
    );
  }

  const achados = lerPanorama(panorama);
  const frase = fraseDoPanorama(achados);

  return (
    <section className="mt-10 border-t border-linha pt-6">
      <div className="flex flex-wrap items-baseline gap-x-3">
        <h2 className="rotulo">O canal</h2>
        <span className="text-[11.5px] text-tinta3">
          o que está cego, o que está degradado, o que está parado
        </span>
      </div>

      {frase !== "" ? (
        <p className="mt-2 max-w-2xl text-[13px] leading-relaxed text-tinta">{frase}</p>
      ) : (
        <p className="mt-2 max-w-2xl text-[13px] leading-relaxed text-tinta2">
          Nada a olhar agora: a varredura está passando, nenhum disjuntor está aberto
          e nenhuma mensagem ficou sem confirmação além da janela.
        </p>
      )}

      {achados.length > 0 && (
        <ul className="mt-4 grid gap-2">
          {achados.map((a) => (
            <li
              key={a.titulo}
              className={`rounded-cartao border px-4 py-3 ${COR[a.gravidade]}`}
            >
              <div className="flex flex-wrap items-baseline gap-x-2">
                <span className="rounded-full border border-current px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider">
                  {ROTULO[a.gravidade]}
                </span>
                <span className="text-[13.5px] font-medium">{a.titulo}</span>
              </div>
              <p className="mt-1 max-w-2xl text-[12.5px] leading-relaxed opacity-90">{a.frase}</p>
            </li>
          ))}
        </ul>
      )}

      {/* A saída crua, em letra pequena: o painel diz o que fazer, e a tabela
          diz de onde ele tirou isso. Sem ela, um achado estranho não tem como
          ser conferido sem abrir o banco. */}
      {panorama.saida.length > 0 && (
        <div className="mt-4 overflow-x-auto">
          <table className="min-w-[22rem] text-[12px]">
            <thead>
              <tr className="text-left text-tinta3">
                <th className="py-1 pr-6 font-medium">canal</th>
                <th className="py-1 pr-6 font-medium">estado</th>
                <th className="py-1 font-medium">24h</th>
              </tr>
            </thead>
            <tbody className="text-tinta2">
              {panorama.saida.map((s) => (
                <tr key={`${s.canal}:${s.estado}`} className="border-t border-linha">
                  <td className="py-1 pr-6 font-mono">{s.canal}</td>
                  <td className="py-1 pr-6 font-mono">{s.estado}</td>
                  <td className="py-1 font-mono tabular-nums">{s.n}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* A cascata configurada, com o preço na mesma tela em que se muda a
          ordem. Decisão de risco contra dinheiro tomada no escuro vira fatura —
          e a pergunta "vale gastar quarenta vezes mais para não perder esta
          oferta?" é dela, não do código. */}
      {panorama.rota && panorama.rota.length > 0 && (
        <div className="mt-5">
          <h3 className="rotulo">A cascata, por classe</h3>
          <ul className="mt-2 grid gap-2">
            {["urgente", "rotina", "documento"].map((classe) => {
              const degraus = (panorama.rota ?? [])
                .filter((r) => r.classe === classe)
                .sort((a, b) => a.posicao - b.posicao);
              if (degraus.length === 0) return null;

              const canais = degraus.map((d) => d.canal as Canal);
              const precos = (panorama.precos ?? []).map((p) => ({
                canal: p.canal as Canal,
                centavosMilesimos: p.centavos_milesimos,
              }));

              return (
                <li key={classe} className="rounded-cartao border border-linha bg-folha px-4 py-3">
                  <div className="flex flex-wrap items-baseline gap-x-2">
                    <span className="font-mono text-[12px] text-tinta3">{classe}</span>
                    <span className="text-[13.5px] text-tinta">
                      {canais.join(" → ")} → sua mão
                    </span>
                  </div>
                  <p className="mt-1 text-[12px] leading-relaxed text-tinta2">
                    {fraseDoCusto(canais, precos)}
                  </p>
                </li>
              );
            })}
          </ul>

          {panorama.precos && panorama.precos.length > 0 && (
            <p className="mt-2 text-[11.5px] leading-relaxed text-tinta3">
              Por mensagem:{" "}
              {panorama.precos
                .map((p) => `${p.canal} ${precoEmReais(p.centavos_milesimos)}`)
                .join(" · ")}
              . São estimativas de `precos_canal` — quando a fatura do provedor chegar, é
              ela que entra ali, com vigência, para não reescrever o passado.
            </p>
          )}
        </div>
      )}

      <p className="mt-4 max-w-2xl text-[11.5px] leading-relaxed text-tinta3">
        A entrada recebeu {panorama.entrada.recebidas_24h} resposta
        {panorama.entrada.recebidas_24h === 1 ? "" : "s"} em 24 horas,{" "}
        {panorama.entrada.nao_entendidas_24h} sem o sistema entender. Taxa alta aqui é a
        fila funcionando e o produto parecendo quebrado para quem respondeu.
      </p>
    </section>
  );
}
