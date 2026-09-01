import type { NextConfig } from "next";

/**
 * As URLs limpas do Panorama.
 *
 * As páginas da pesquisa são HTML estático em `public/panorama/`, e o que está
 * em `public/` já é servido como arquivo. O rewrite existe só para o endereço
 * que vai em post de Instagram e em ofício de CRP ser `/panorama` e não
 * `/panorama/index.html` — e porque `/panorama` sozinho, sem isto, é 404.
 *
 * **Isto não basta sozinho.** O `proxy.ts` fecha por padrão e o matcher dele
 * deixa de fora só os caminhos com extensão. `/panorama/pesquisa.html` tem
 * extensão e passa; `/panorama/pesquisa` não tem, acorda o proxy, e sem
 * sessão vira um 307 para `/entrar`. Ou seja: criar a URL limpa aqui sem
 * abrir o caminho lá manda toda respondente para uma tela de login de um
 * produto que ela não assina. Por isso `/panorama` está em `PREFIXOS_PUBLICOS`,
 * e há teste dos dois lados.
 */
/**
 * Os endereços antigos, depois da reorganização em cinco destinos.
 *
 * A auditoria mandou reduzir doze itens de menu a cinco, e reduzir o menu
 * significou mover as rotas: `/fila` virou `/encaixes`, `/em-aberto` virou
 * `/recebimentos`, `/receita-saude` virou `/fechamento/receita-saude`, e assim
 * por diante.
 *
 * Sem estas linhas, todo endereço que alguém salvou no navegador vira 404 no
 * dia do deploy — e um 404 numa tela que ela usa todo dia não se lê como
 * "mudou de lugar", se lê como "o produto quebrou e perdi meus dados". São
 * permanentes (308) porque a mudança é definitiva, e ficam: o custo é uma
 * linha, e o custo de tirar é a pessoa que só volta ao produto em fevereiro.
 */
const ENDERECOS_ANTIGOS: [string, string][] = [
  ["/fila", "/encaixes"],
  ["/fila/:caminho*", "/encaixes/:caminho*"],
  ["/vagas", "/encaixes/fixos"],
  ["/em-aberto", "/recebimentos"],
  ["/financeiro", "/recebimentos/movimentacoes"],
  ["/receita-saude", "/fechamento/receita-saude"],
  ["/contador", "/fechamento/contador"],
  ["/contador/:caminho*", "/fechamento/contador/:caminho*"],
  ["/documentos", "/fechamento/documentos"],
  ["/documentos/:caminho*", "/fechamento/documentos/:caminho*"],
  ["/contratos", "/perfil/contrato"],
  ["/calendario", "/perfil/integracoes"],
  ["/conta", "/perfil"],
  ["/conta/exportar", "/perfil/exportar"],
];

const nextConfig: NextConfig = {
  async redirects() {
    return ENDERECOS_ANTIGOS.map(([source, destination]) => ({
      source,
      destination,
      permanent: true,
    }));
  },

  async rewrites() {
    return [
      { source: "/panorama", destination: "/panorama/index.html" },
      { source: "/panorama/pesquisa", destination: "/panorama/pesquisa.html" },
      { source: "/panorama/contato", destination: "/panorama/contato.html" },
      { source: "/panorama/protocolo", destination: "/panorama/protocolo.pdf" },
    ];
  },
};

export default nextConfig;
