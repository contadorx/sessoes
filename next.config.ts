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
const nextConfig: NextConfig = {
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
