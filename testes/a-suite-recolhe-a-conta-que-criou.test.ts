import { describe, expect, it } from 'vitest'
import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'

// Conta de teste que fica de pé é linha a mais em toda métrica de operação do
// painel do negócio — e a pior parte é que ela não se anuncia: quem nasce pelo
// gatilho de `auth.users` nasce com `is_teste = false`, porque o gatilho não
// tem como saber que quem inseriu era uma suíte.
//
// Isso já foi achado três vezes, uma suíte por vez: a 0053 deixava a conta
// 'Fisca Teste', a 0040 deixava três ('Ana Solo', 'Bia Colega', 'Bia Outra') e
// a 0042 deixava duas. Três achados da mesma forma é o sinal da lei 7: a
// verificação não pode ser eu abrindo o próximo arquivo.
//
// A distinção que este teste faz é posicional, e é ela que separa as suítes
// certas das erradas. **Toda** suíte apaga contas no preâmbulo — é assim que
// ela garante um ponto de partida limpo. O que faltava nas três era apagar
// **depois**: o preâmbulo limpa o rastro da rodada passada, o desmonte limpa o
// da rodada de agora. Só o segundo devolve o banco como o encontrou.

const PASTA = join(process.cwd(), 'supabase', 'tests')

/** Cria conta quem insere em `auth.users`: o gatilho faz o resto. */
const CRIA_CONTA = /insert\s+into\s+auth\.users/gi

/** Recolhe a conta quem apaga de `public.contas` — ou chama a função que apaga. */
const RECOLHE = /(delete\s+from\s+public\.contas|eliminar_conta\s*\()/gi

function ultimaPosicao(texto: string, re: RegExp): number {
  let fim = -1
  for (const m of texto.matchAll(re)) fim = m.index ?? fim
  return fim
}

describe('a suíte recolhe a conta que criou', () => {
  const arquivos = readdirSync(PASTA).filter((f) => f.endsWith('.sql')).sort()

  it('há suítes para varrer', () => {
    expect(arquivos.length).toBeGreaterThan(50)
  })

  it.each(arquivos)('%s apaga a conta depois da última que cria', (arquivo) => {
    const sql = readFileSync(join(PASTA, arquivo), 'utf8')
    const criou = ultimaPosicao(sql, CRIA_CONTA)
    if (criou < 0) return // suíte que não cria conta não tem o que recolher

    const recolheu = ultimaPosicao(sql, RECOLHE)
    expect(
      recolheu,
      `${arquivo} insere em auth.users e nunca apaga de public.contas: a conta ` +
        `fica de pé com is_teste = false`,
    ).toBeGreaterThan(-1)
    expect(
      recolheu,
      `${arquivo} só apaga contas ANTES da última que cria — isso é preâmbulo, ` +
        `não desmonte. A rodada limpa o rastro da anterior e deixa o próprio.`,
    ).toBeGreaterThan(criou)
  })
})
